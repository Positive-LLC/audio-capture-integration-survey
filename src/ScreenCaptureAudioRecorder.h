#pragma once

#include <JuceHeader.h>
#include <chrono>
#include <memory>

namespace pg {

/**
 * @brief C++ wrapper for macOS ScreenCaptureKit audio recording
 *
 * Records system audio using Apple's ScreenCaptureKit framework.
 * Uses pimpl idiom to hide Objective-C implementation details.
 */
class ScreenCaptureAudioRecorder
{
public:
    /**
     * @brief Constructor
     */
    ScreenCaptureAudioRecorder();

    ~ScreenCaptureAudioRecorder();

    /**
     * @brief Start recording system audio
     * @param outputFile The file to save the recording to.
     * @return true if recording started successfully
     */
    auto startRecording(const juce::File &outputFile) -> bool;

    /**
     * @brief Stop recording manually
     */
    auto stopRecording() -> void;

    /**
     * @brief Check if currently recording
     */
    auto isRecording() const -> bool;

    /**
     * @brief Check if recording has finished and the file is ready.
     */
    auto hasFinishedRecording() const -> bool;

    /**
     * @brief Check if screen recording permission is granted
     */
    static auto hasScreenRecordingPermission() -> bool;

    /**
     * @brief Request screen recording permission
     */
    static auto requestScreenRecordingPermission() -> void;

public:
    // Forward declaration for Objective-C delegate access
    class Impl;

private:
    // Pimpl idiom to hide Objective-C implementation
    std::unique_ptr<Impl> pImpl_;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ScreenCaptureAudioRecorder)
};

} // namespace pg
