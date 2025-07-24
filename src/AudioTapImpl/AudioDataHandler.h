#pragma once

#include <CoreAudio/CoreAudio.h>
#include <JuceHeader.h>
#include <atomic>
#include <functional>
#include <vector>

namespace pg {
namespace audio_tap {

    class AudioDataHandler
    {
    public:
        AudioDataHandler(const AudioStreamBasicDescription &format, int durationInSeconds);

        // Called from the real-time audio thread (IOProc)
        void process(const AudioBufferList *inInputData);

        // Called from the main thread to save the buffer
        void saveToFile(const juce::File &file, const AudioStreamBasicDescription &format);

        // Set a callback to be invoked when the buffer is full
        void setBufferFullCallback(std::function<void()> callback);

    private:
        std::vector<float> audioBuffer_;
        std::atomic<size_t> bufferIndex_{0};
        std::function<void()> onBufferFull_;
    };

} // namespace audio_tap
} // namespace pg
