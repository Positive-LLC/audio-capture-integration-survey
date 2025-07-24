#pragma once

#include <CoreAudio/AudioHardwareBase.h>
#include <JuceHeader.h>

namespace pg {
class CoreAudioTapRecorder
{
public:
    CoreAudioTapRecorder();
    ~CoreAudioTapRecorder();

    auto startRecording(const juce::File &outputFile) -> bool;
    auto stopRecording() -> void;
    auto isRecording() const -> bool;
    auto hasRecordingFinished() const -> bool;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl_;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(CoreAudioTapRecorder)
};

} // namespace pg
