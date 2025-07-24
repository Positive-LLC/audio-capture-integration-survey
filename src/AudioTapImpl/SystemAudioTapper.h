#pragma once

#include "TappingSessionHandle.h"
#include <CoreAudio/CoreAudio.h>
#include <memory>
#include <mutex>

@class CATapDescription;

namespace pg {
namespace audio_tap {

    class SystemAudioTapper
    {
    public:
        // --- Public API ---
        static SystemAudioTapper &getInstance();

        // Not copyable or movable
        SystemAudioTapper(const SystemAudioTapper &) = delete;
        SystemAudioTapper &operator=(const SystemAudioTapper &) = delete;

        TappingSessionHandle acquireSession();

    private:
        friend class TappingSessionHandle; // Allow handle to call releaseSession
        void releaseSession(AudioObjectID tapID, AudioDeviceID aggregateDeviceID);

        // --- Singleton Implementation ---
        SystemAudioTapper() = default;
        ~SystemAudioTapper();

        // --- Private Helper Methods ---
        bool setupTapAndAggregateDevice();
        AudioDeviceID findDefaultOutputDevice();
        AudioDeviceID findOrCreateAggregateDevice(CATapDescription *tapDescription);

        // --- Class Constants ---
        static constexpr const char *kAggregateDeviceUID = "PG-Aggregate-Device";

        // --- Member Variables ---
        std::mutex sessionMutex_;
        int activeSessions_{0};
        AudioDeviceID aggregateDeviceID_{kAudioDeviceUnknown};
        AudioObjectID tapSessionID_{kAudioObjectUnknown};
    };

} // namespace audio_tap
} // namespace pg
