#pragma once

#include <CoreAudio/CoreAudio.h>
#include <JuceHeader.h> // For JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR
#include <functional>

namespace pg {
namespace audio_tap {

    // RAII wrapper for an AudioDeviceIOProcID
    class IOProcHandle
    {
    public:
        using AudioCallback = std::function<void(const AudioBufferList *)>;

        IOProcHandle(AudioDeviceID deviceID, AudioCallback callback);
        ~IOProcHandle();

        // Move semantics
        IOProcHandle(IOProcHandle &&other) noexcept;
        IOProcHandle &operator=(IOProcHandle &&other) noexcept;

        auto isValid() const -> bool { return ioProcID_ != nullptr; }

    private:
        // This is a static callback required by the Core Audio C API.
        static OSStatus ioproc_callback(AudioObjectID inDevice, const AudioTimeStamp *inNow,
                                        const AudioBufferList *inInputData,
                                        const AudioTimeStamp *inInputTime,
                                        AudioBufferList *outOutputData,
                                        const AudioTimeStamp *inOutputTime,
                                        void *__nullable inClientData);

        AudioDeviceID ownerDeviceID_ = kAudioObjectUnknown;
        AudioDeviceIOProcID ioProcID_ = nullptr;
        AudioCallback callback_;

        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(IOProcHandle)
    };

} // namespace audio_tap
} // namespace pg
