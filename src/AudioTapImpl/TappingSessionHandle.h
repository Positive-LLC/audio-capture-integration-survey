#pragma once

#include <CoreAudio/CoreAudio.h>
#include <functional>

namespace pg {
namespace audio_tap {

    class SystemAudioTapper;

    enum class DevicePropertyChangeReason
    {
        StreamFormatChanged,
        StreamConfigurationChanged,
        DeviceIsAliveChanged,
    };

    using PropertyChangeCallback = std::function<void(DevicePropertyChangeReason)>;

    class TappingSessionHandle
    {
    public:
        TappingSessionHandle() = default;
        TappingSessionHandle(TappingSessionHandle &&other) noexcept;
        TappingSessionHandle &operator=(TappingSessionHandle &&other) noexcept;
        ~TappingSessionHandle();

        TappingSessionHandle(const TappingSessionHandle &) = delete;
        TappingSessionHandle &operator=(const TappingSessionHandle &) = delete;

        AudioObjectID getTapSessionID() const;
        AudioDeviceID getAggregateDeviceID() const;
        const AudioStreamBasicDescription &getAudioFormat() const;
        auto getSampleRate() const -> double;
        auto getChannelCount() const -> uint32_t;
        bool isValid() const;

        void registerPropertyListener(PropertyChangeCallback callback);
        void unregisterPropertyListener();

    private:
        // Only SystemAudioTapper can create instances of this handle.
        friend class SystemAudioTapper;
        TappingSessionHandle(AudioObjectID tapID, AudioDeviceID aggID, SystemAudioTapper *manager);

        void release();

        void queryDefaultDeviceFormat();

        static OSStatus
        staticPropertyListenerCallback(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                                       const AudioObjectPropertyAddress inAddresses[],
                                       void *__nullable inClientData);

        AudioObjectID tapSessionID_{kAudioObjectUnknown};
        AudioDeviceID aggregateDeviceID_{kAudioDeviceUnknown};
        SystemAudioTapper *manager_{nullptr};
        AudioStreamBasicDescription audioFormat_{};

        // Listener-related members
        AudioDeviceID defaultDeviceID_{kAudioObjectUnknown};
        PropertyChangeCallback propertyChangeCallback_{nullptr};
    };

} // namespace audio_tap
} // namespace pg
