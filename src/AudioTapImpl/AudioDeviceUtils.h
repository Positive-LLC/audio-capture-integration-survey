#pragma once

#include <CoreAudio/CoreAudio.h>
#include <vector>

namespace juce {
class File;
}

namespace pg {
namespace audio_tap {
    namespace utils {

        /**
         * @brief Finds the default audio output device for the system.
         * @return The AudioDeviceID of the default output device, or kAudioObjectUnknown if not
         * found or an error occurs.
         */
        AudioDeviceID getDefaultOutputDevice();

        /**
         * @brief Allocates a buffer to hold audio for a given format and duration.
         * @param format The ASBD describing the audio format.
         * @param durationInSeconds The desired duration of the buffer in seconds.
         * @return A std::vector<float> pre-sized to hold the audio data.
         */
        auto allocateBufferForFormat(const AudioStreamBasicDescription &format,
                                     int durationInSeconds) -> std::vector<float>;

        /**
         * @brief Saves a raw float audio buffer to a CAF file.
         * @param format The ASBD describing the audio format of the raw buffer.
         * @param file The destination file. The file will be overwritten if it exists.
         * @param buffer The buffer containing the raw float audio data.
         */
        void saveBufferToFile(const AudioStreamBasicDescription &format, const juce::File &file,
                              const std::vector<float> &buffer);

    } // namespace utils
} // namespace audio_tap
} // namespace pg
