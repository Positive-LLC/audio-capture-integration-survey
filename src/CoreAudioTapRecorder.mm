#include "CoreAudioTapRecorder.h"

#include "AudioTapImpl/AudioDataHandler.h"
#include "AudioTapImpl/AudioDeviceUtils.h"
#include "AudioTapImpl/IOProcHandle.h"
#include "AudioTapImpl/SystemAudioTapper.h"
#include <functional>
#include <memory>
#include <vector>

namespace pg {

enum class RecorderState
{
    Idle,      // Not recording, ready to start.
    Starting,  // `startRecording` called, in the process of setting up.
    Recording, // Actively capturing audio.
    Stopping,  // `stopRecording` called, in the process of finalizing.
    Succeeded, // Recording finished successfully.
    Failed     // Recording terminated due to an error.
};

class CoreAudioTapRecorder::Impl
{
public:
    Impl() = default;

    ~Impl()
    {
        auto expectedState = state_.load();
        if (expectedState == RecorderState::Recording || expectedState == RecorderState::Starting) {
            // In the destructor, we must stop synchronously to avoid use-after-free.
            if (state_.compare_exchange_strong(expectedState, RecorderState::Stopping)) {
                lastStopReason_ = StopReason::UserRequested;
                performStopLogic();
            }
        }
    }

    auto startRecording(const juce::File &outputFile) -> bool
    {
        if (!canStartRecording()) { return false; }

        setupInitialState(outputFile);

        if (!setupTappingSession()) {
            cleanupAfterFailure();
            return false;
        }

        if (tappingSession_.getAudioFormat().mSampleRate == 0) { // Check for a valid format
            DBG("CoreAudioTapRecorder: Error - Invalid audio format received from session handle.");
            cleanupAfterFailure();
            return false;
        }
        audioDataHandler_ = std::make_unique<audio_tap::AudioDataHandler>(
                tappingSession_.getAudioFormat(), 600);
        audioDataHandler_->setBufferFullCallback(
                [this]
                {
                    auto expected = RecorderState::Recording;
                    if (state_.compare_exchange_strong(expected, RecorderState::Stopping)) {
                        lastStopReason_ = StopReason::BufferFull;
                        asyncPerformStop();
                    }
                });

        if (!setupIOProc(tappingSession_.getAggregateDeviceID())) {
            cleanupAfterFailure();
            return false;
        }

        state_.store(RecorderState::Recording);
        tappingSession_.registerPropertyListener([this](auto reason)
                                                 { handleDevicePropertyChanged(reason); });
        return true;
    }

    auto stopRecording() -> void
    {
        auto expected = RecorderState::Recording;
        if (state_.compare_exchange_strong(expected, RecorderState::Stopping)) {
            // If the state transition succeeds, it means no other stop reason was set.
            // We can safely set the reason to UserRequested.
            lastStopReason_ = StopReason::UserRequested;
            asyncPerformStop();
        }
    }

    auto isRecording() const -> bool
    {
        auto const currentState = state_.load();
        return currentState == RecorderState::Recording || currentState == RecorderState::Stopping;
    }

    auto hasRecordingFinished() const -> bool
    {
        const auto currentState = state_.load();
        return currentState == RecorderState::Succeeded || currentState == RecorderState::Failed;
    }

private:
    auto canStartRecording() -> bool
    {
        auto const currentState = state_.load();
        return currentState == RecorderState::Idle || currentState == RecorderState::Succeeded ||
               currentState == RecorderState::Failed;
    }

    void setupInitialState(const juce::File &outputFile)
    {
        outputFile_ = outputFile;
        state_.store(RecorderState::Starting);
        lastStopReason_ = StopReason::UserRequested;
    }

    auto setupTappingSession() -> bool
    {
        tappingSession_ = audio_tap::SystemAudioTapper::getInstance().acquireSession();
        return tappingSession_.isValid();
    }


    auto setupIOProc(AudioDeviceID aggregateDeviceID) -> bool
    {
        auto processCallback = [handler = audioDataHandler_.get()](const auto *buffer)
        {
            if (handler) { handler->process(buffer); }
        };

        ioProcHandle_.emplace(aggregateDeviceID, processCallback);
        return ioProcHandle_->isValid();
    }

    void cleanupAfterFailure()
    {
        state_.store(RecorderState::Failed);
        tappingSession_ = {}; // Release resources via RAII
        ioProcHandle_.reset();
        audioDataHandler_.reset();
    }

    void asyncPerformStop()
    {
        // Asynchronously dispatch the synchronous cleanup logic to the main message thread.
        juce::MessageManager::callAsync([this] { performStopLogic(); });
    }

    void performStopLogic()
    {
        tappingSession_.unregisterPropertyListener();

        // IOProcHandle's destructor will automagically handle stopping and destroying the IOProcID.
        ioProcHandle_.reset();

        if (audioDataHandler_) {
            audioDataHandler_->saveToFile(outputFile_, tappingSession_.getAudioFormat());
        }

        // Now that saving is complete, we can reset the session handle and handler.
        tappingSession_ = {};
        audioDataHandler_.reset();

        // Any stop reason other than an explicit failure should be considered a success.
        // The caller can query `wasStoppedDueToConfigChange()` to understand why it stopped.
        if (lastStopReason_ == StopReason::ExplicitError) {
            state_.store(RecorderState::Failed);
            DBG("CoreAudioTapRecorder: Recording failed due to an explicit error.");
        } else {
            state_.store(RecorderState::Succeeded);
            if (lastStopReason_ != StopReason::UserRequested) {
                DBG("CoreAudioTapRecorder: Recording stopped for a reason other than user "
                    "request.");
            }
        }
    }


    // =================================================================================
    // MARK: - Core Audio Callbacks & Helpers
    // =================================================================================

    void handleDevicePropertyChanged(audio_tap::DevicePropertyChangeReason reason)
    {
        if (state_.load() != RecorderState::Recording) { return; }

        bool shouldStop = false;
        switch (reason) {
        case audio_tap::DevicePropertyChangeReason::StreamFormatChanged:
        case audio_tap::DevicePropertyChangeReason::StreamConfigurationChanged:
            lastStopReason_ = StopReason::ConfigurationChanged;
            shouldStop = true;
            break;
        case audio_tap::DevicePropertyChangeReason::DeviceIsAliveChanged:
            lastStopReason_ = StopReason::DeviceRemoved;
            shouldStop = true;
            break;
        }

        if (shouldStop) {
            auto expected = RecorderState::Recording;
            if (state_.compare_exchange_strong(expected, RecorderState::Stopping)) {
                asyncPerformStop();
            }
        }
    }

    enum class StopReason
    {
        UserRequested,
        BufferFull,
        ConfigurationChanged,
        DeviceRemoved,
        ExplicitError
    };

    // State
    std::atomic<RecorderState> state_{RecorderState::Idle};
    StopReason lastStopReason_ = StopReason::UserRequested;

    // Core Audio & JUCE
    audio_tap::TappingSessionHandle tappingSession_;
    // The `audioDataHandler_` must be declared before `ioProcHandle_` to ensure correct
    // initialization order, as the lambda passed to `ioProcHandle_` captures a pointer to the
    // handler.
    std::unique_ptr<audio_tap::AudioDataHandler> audioDataHandler_;
    std::optional<audio_tap::IOProcHandle> ioProcHandle_;
    juce::File outputFile_;
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Impl)
};

CoreAudioTapRecorder::CoreAudioTapRecorder()
{
    pImpl_ = std::make_unique<Impl>();
}
CoreAudioTapRecorder::~CoreAudioTapRecorder() = default;

auto CoreAudioTapRecorder::startRecording(const juce::File &outputFile) -> bool
{
    return pImpl_->startRecording(outputFile);
}
auto CoreAudioTapRecorder::stopRecording() -> void
{
    pImpl_->stopRecording();
}
auto CoreAudioTapRecorder::isRecording() const -> bool
{
    return pImpl_->isRecording();
}
auto CoreAudioTapRecorder::hasRecordingFinished() const -> bool
{
    return pImpl_->hasRecordingFinished();
}

} // namespace pg
