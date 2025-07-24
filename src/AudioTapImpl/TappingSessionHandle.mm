#include "TappingSessionHandle.h"
#include "AudioDeviceUtils.h"
#include "SystemAudioTapper.h"

#include "JuceHeader.h"

#include <utility>

namespace pg {
namespace audio_tap {
    TappingSessionHandle::TappingSessionHandle(TappingSessionHandle &&other) noexcept
      : tapSessionID_(std::exchange(other.tapSessionID_, kAudioObjectUnknown)),
        aggregateDeviceID_(std::exchange(other.aggregateDeviceID_, kAudioObjectUnknown)),
        manager_(std::exchange(other.manager_, nullptr)),
        audioFormat_(std::exchange(other.audioFormat_, {})),
        defaultDeviceID_(std::exchange(other.defaultDeviceID_, kAudioObjectUnknown)),
        propertyChangeCallback_(std::move(other.propertyChangeCallback_))
    {
    }

    TappingSessionHandle &TappingSessionHandle::operator=(TappingSessionHandle &&other) noexcept
    {
        if (this != &other) {
            release();
            tapSessionID_ = std::exchange(other.tapSessionID_, kAudioObjectUnknown);
            aggregateDeviceID_ = std::exchange(other.aggregateDeviceID_, kAudioObjectUnknown);
            manager_ = std::exchange(other.manager_, nullptr);
            audioFormat_ = std::exchange(other.audioFormat_, {});
            defaultDeviceID_ = std::exchange(other.defaultDeviceID_, kAudioObjectUnknown);
            propertyChangeCallback_ = std::move(other.propertyChangeCallback_);
        }
        return *this;
    }

    TappingSessionHandle::~TappingSessionHandle()
    {
        release();
    }

    TappingSessionHandle::TappingSessionHandle(AudioObjectID tapID, AudioDeviceID aggID,
                                               SystemAudioTapper *manager)
      : tapSessionID_(tapID),
        aggregateDeviceID_(aggID),
        manager_(manager),
        defaultDeviceID_(utils::getDefaultOutputDevice())
    {
        queryDefaultDeviceFormat();
    }

    AudioObjectID TappingSessionHandle::getTapSessionID() const
    {
        return tapSessionID_;
    }
    AudioDeviceID TappingSessionHandle::getAggregateDeviceID() const
    {
        return aggregateDeviceID_;
    }

    const AudioStreamBasicDescription &TappingSessionHandle::getAudioFormat() const
    {
        return audioFormat_;
    }

    auto TappingSessionHandle::getSampleRate() const -> double
    {
        return audioFormat_.mSampleRate;
    }

    auto TappingSessionHandle::getChannelCount() const -> uint32_t
    {
        return audioFormat_.mChannelsPerFrame;
    }

    bool TappingSessionHandle::isValid() const
    {
        return tapSessionID_ != kAudioObjectUnknown;
    }

    void TappingSessionHandle::registerPropertyListener(PropertyChangeCallback callback)
    {
        if (!isValid() || defaultDeviceID_ == kAudioObjectUnknown) { return; }

        propertyChangeCallback_ = std::move(callback);

        constexpr AudioObjectPropertyAddress addresses[] = {
                {kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
                {kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
                {kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
        };

        for (const auto &address : addresses) {
            AudioObjectAddPropertyListener(defaultDeviceID_, &address,
                                           staticPropertyListenerCallback, this);
        }
    }

    void TappingSessionHandle::unregisterPropertyListener()
    {
        if (defaultDeviceID_ == kAudioObjectUnknown) { return; }

        constexpr AudioObjectPropertyAddress addresses[] = {
                {kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
                {kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
                {kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeOutput,
                 kAudioObjectPropertyElementMain},
        };

        for (const auto &address : addresses) {
            AudioObjectRemovePropertyListener(defaultDeviceID_, &address,
                                              staticPropertyListenerCallback, this);
        }

        propertyChangeCallback_ = nullptr;
        defaultDeviceID_ = kAudioObjectUnknown;
    }


    void TappingSessionHandle::release()
    {
        if (manager_ && tapSessionID_ != kAudioObjectUnknown) {
            manager_->releaseSession(tapSessionID_, aggregateDeviceID_);
        }
        tapSessionID_ = kAudioObjectUnknown;
        aggregateDeviceID_ = kAudioObjectUnknown;
        manager_ = nullptr;
    }

    void TappingSessionHandle::queryDefaultDeviceFormat()
    {
        if (defaultDeviceID_ == kAudioObjectUnknown) {
            DBG("TappingSessionHandle: Cannot query format, default output device is unknown.");
            return;
        }

        AudioObjectPropertyAddress propertyAddress = {kAudioDevicePropertyStreamFormat,
                                                      kAudioObjectPropertyScopeOutput,
                                                      kAudioObjectPropertyElementMain};
        UInt32 dataSize = sizeof(audioFormat_);
        OSStatus status = AudioObjectGetPropertyData(defaultDeviceID_, &propertyAddress, 0, nullptr,
                                                     &dataSize, &audioFormat_);

        if (status != noErr) {
            DBG("TappingSessionHandle: Warning - Could not query device format, using defaults. "
                "Error: "
                << status);
            memset(&audioFormat_, 0, sizeof(audioFormat_));
        }
    }

    OSStatus TappingSessionHandle::staticPropertyListenerCallback(
            AudioObjectID inObjectID, UInt32 inNumberAddresses,
            const AudioObjectPropertyAddress inAddresses[], void *__nullable inClientData)
    {
        auto *self = static_cast<TappingSessionHandle *>(inClientData);
        if (!self || !self->propertyChangeCallback_) { return noErr; }

        for (UInt32 i = 0; i < inNumberAddresses; ++i) {
            const auto &address = inAddresses[i];
            if (address.mSelector == kAudioDevicePropertyStreamFormat) {
                self->propertyChangeCallback_(DevicePropertyChangeReason::StreamFormatChanged);
            } else if (address.mSelector == kAudioDevicePropertyStreamConfiguration) {
                self->propertyChangeCallback_(
                        DevicePropertyChangeReason::StreamConfigurationChanged);
            } else if (address.mSelector == kAudioDevicePropertyDeviceIsAlive) {
                self->propertyChangeCallback_(DevicePropertyChangeReason::DeviceIsAliveChanged);
            }
        }

        return noErr;
    }
} // namespace audio_tap
} // namespace pg
