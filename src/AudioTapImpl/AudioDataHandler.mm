#include "AudioDataHandler.h"
#include "AudioDeviceUtils.h"

namespace pg {
namespace audio_tap {

    AudioDataHandler::AudioDataHandler(const AudioStreamBasicDescription &format,
                                       int durationInSeconds)
    {
        audioBuffer_ = utils::allocateBufferForFormat(format, durationInSeconds);
    }

    void AudioDataHandler::process(const AudioBufferList *inInputData)
    {
        for (UInt32 i = 0; i < inInputData->mNumberBuffers; ++i) {
            auto *inputData = static_cast<float *>(inInputData->mBuffers[i].mData);
            size_t samplesInBuffer = inInputData->mBuffers[i].mDataByteSize / sizeof(float);

            size_t currentIndex = bufferIndex_.load();
            if (currentIndex + samplesInBuffer < audioBuffer_.size()) {
                std::copy(inputData, inputData + samplesInBuffer,
                          audioBuffer_.begin() + currentIndex);
                bufferIndex_.fetch_add(samplesInBuffer);
            } else {
                if (onBufferFull_) {
                    onBufferFull_();
                    onBufferFull_ = {}; // Reset after calling to make it a one-shot.
                }
            }
        }
    }

    void AudioDataHandler::saveToFile(const juce::File &file,
                                      const AudioStreamBasicDescription &format)
    {
        audioBuffer_.resize(bufferIndex_.load());
        if (!audioBuffer_.empty()) { utils::saveBufferToFile(format, file, audioBuffer_); }
    }

    void AudioDataHandler::setBufferFullCallback(std::function<void()> callback)
    {
        onBufferFull_ = std::move(callback);
    }

} // namespace audio_tap
} // namespace pg
