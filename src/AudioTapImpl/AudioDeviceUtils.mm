#include "AudioDeviceUtils.h"

#include "JuceHeader.h"
#include <AudioToolbox/ExtendedAudioFile.h>
#include <vector>

namespace pg {
namespace audio_tap {
    namespace utils {

        AudioDeviceID getDefaultOutputDevice()
        {
            AudioDeviceID deviceID = kAudioObjectUnknown;
            UInt32 propertySize = sizeof(deviceID);
            AudioObjectPropertyAddress propertyAddress = {kAudioHardwarePropertyDefaultOutputDevice,
                                                          kAudioObjectPropertyScopeGlobal,
                                                          kAudioObjectPropertyElementMain};

            OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress,
                                                         0, nullptr, &propertySize, &deviceID);
            if (status != kAudioHardwareNoError) { return kAudioObjectUnknown; }

            return deviceID;
        }

        auto allocateBufferForFormat(const AudioStreamBasicDescription &format,
                                     int durationInSeconds) -> std::vector<float>
        {
            if (format.mSampleRate <= 0 || format.mChannelsPerFrame == 0) { return {}; }
            const size_t totalSamples = static_cast<size_t>(format.mSampleRate * durationInSeconds *
                                                            format.mChannelsPerFrame);
            return std::vector<float>(totalSamples);
        }

        void saveBufferToFile(const AudioStreamBasicDescription &format, const juce::File &file,
                              const std::vector<float> &buffer)
        {
            if (buffer.empty()) { return; }

            CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(
                    kCFAllocatorDefault, (const UInt8 *)file.getFullPathName().toRawUTF8(),
                    strlen(file.getFullPathName().toRawUTF8()), false);

            if (!fileURL) { return; }

            ExtAudioFileRef audioFile = nullptr;
            AudioStreamBasicDescription fileFormat = format;

            OSStatus status =
                    ExtAudioFileCreateWithURL(fileURL, kAudioFileCAFType, &fileFormat, nullptr,
                                              kAudioFileFlags_EraseFile, &audioFile);

            CFRelease(fileURL);

            if (status != noErr) { return; }

            AudioStreamBasicDescription clientFormat = format;
            status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat,
                                             sizeof(clientFormat), &clientFormat);

            if (status != noErr) {
                ExtAudioFileDispose(audioFile);
                return;
            }

            AudioBufferList bufferList;
            bufferList.mNumberBuffers = 1;
            bufferList.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
            bufferList.mBuffers[0].mDataByteSize = (UInt32)(buffer.size() * sizeof(float));
            bufferList.mBuffers[0].mData = const_cast<float *>(buffer.data());

            UInt32 framesToWrite = (UInt32)(buffer.size() / format.mChannelsPerFrame);
            status = ExtAudioFileWrite(audioFile, framesToWrite, &bufferList);

            ExtAudioFileDispose(audioFile);
        }

    } // namespace utils
} // namespace audio_tap
} // namespace pg
