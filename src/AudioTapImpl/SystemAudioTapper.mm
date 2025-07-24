#include "SystemAudioTapper.h"
#include "AudioDeviceUtils.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <vector>

namespace pg {
namespace audio_tap {

    // --- Singleton Implementation ---

    SystemAudioTapper &SystemAudioTapper::getInstance()
    {
        static SystemAudioTapper instance;
        return instance;
    }

    SystemAudioTapper::~SystemAudioTapper()
    {
        if (tapSessionID_ != kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapSessionID_); }
        if (aggregateDeviceID_ != kAudioDeviceUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID_);
        }
    }

    // --- Public API ---

    TappingSessionHandle SystemAudioTapper::acquireSession()
    {
        std::lock_guard<std::mutex> lock(sessionMutex_);

        if (activeSessions_ == 0) {
            if (!setupTapAndAggregateDevice()) {
                // PGLOG_LOGGER(logger).error("Failed to setup tap and aggregate device.");
                // Ensure cleanup happens if partial setup failed.
                if (tapSessionID_ != kAudioObjectUnknown) {
                    AudioHardwareDestroyProcessTap(tapSessionID_);
                    tapSessionID_ = kAudioObjectUnknown;
                }
                if (aggregateDeviceID_ != kAudioDeviceUnknown) {
                    AudioHardwareDestroyAggregateDevice(aggregateDeviceID_);
                    aggregateDeviceID_ = kAudioDeviceUnknown;
                }
                return {}; // Return invalid handle
            }
        }

        activeSessions_++;
        return TappingSessionHandle(tapSessionID_, aggregateDeviceID_, this);
    }

    // --- Private Methods ---

    void SystemAudioTapper::releaseSession(AudioObjectID /*tapID*/,
                                           AudioDeviceID /*aggregateDeviceID*/)
    {
        std::lock_guard<std::mutex> lock(sessionMutex_);

        if (activeSessions_ > 0) { activeSessions_--; }

        if (activeSessions_ == 0) {
            if (tapSessionID_ != kAudioObjectUnknown) {
                AudioHardwareDestroyProcessTap(tapSessionID_);
                tapSessionID_ = kAudioObjectUnknown;
            }
            if (aggregateDeviceID_ != kAudioDeviceUnknown) {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID_);
                aggregateDeviceID_ = kAudioDeviceUnknown;
            }
        }
    }

    // This now combines the logic of tap and aggregate device creation
    // to follow the correct dependency order from CoreAudioTapRecorder.mm.
    bool SystemAudioTapper::setupTapAndAggregateDevice()
    {
        // First, find the default output device to tap
        AudioDeviceID mainDeviceID = utils::getDefaultOutputDevice();
        if (mainDeviceID == kAudioDeviceUnknown) { return false; }

        // Create the CATapDescription, which is needed for BOTH tap creation and agg device
        // creation
        CFStringRef deviceUIDRef = nullptr;
        UInt32 uidSize = sizeof(deviceUIDRef);
        AudioObjectPropertyAddress uidAddress = {kAudioDevicePropertyDeviceUID,
                                                 kAudioObjectPropertyScopeGlobal,
                                                 kAudioObjectPropertyElementMain};
        OSStatus status = AudioObjectGetPropertyData(mainDeviceID, &uidAddress, 0, nullptr,
                                                     &uidSize, &deviceUIDRef);

        if (status != noErr || deviceUIDRef == nullptr) { return false; }

        CATapDescription *tapDescription =
                [[CATapDescription alloc] initWithProcesses:@[]
                                               andDeviceUID:(__bridge NSString *)deviceUIDRef
                                                 withStream:0];
        CFRelease(deviceUIDRef);
        if (!tapDescription) { return false; }

        [tapDescription setMuteBehavior:CATapUnmuted];
        [tapDescription setName:@"BIASAudioTap"];
        [tapDescription setPrivate:YES];
        [tapDescription setExclusive:YES];

        // Second, create or find the aggregate device. It depends on the tap's UUID from the
        // description.
        aggregateDeviceID_ = findOrCreateAggregateDevice(tapDescription);
        if (aggregateDeviceID_ == kAudioObjectUnknown) {
            [tapDescription release];
            return false;
        }

        // Third, with the aggregate device ready, create the actual process tap.
        status = AudioHardwareCreateProcessTap(tapDescription, &tapSessionID_);
        [tapDescription release]; // release the description now that it's been used

        if (status != noErr) {
            // If tap creation fails, the calling function `acquireSession` will handle cleanup
            // of the aggregate device we might have just found/created.
            return false;
        }

        return true;
    }

    AudioDeviceID SystemAudioTapper::findOrCreateAggregateDevice(CATapDescription *tapDescription)
    {
        // Check if the device already exists in the system
        AudioObjectPropertyAddress propertyAddress = {kAudioHardwarePropertyDevices,
                                                      kAudioObjectPropertyScopeGlobal,
                                                      kAudioObjectPropertyElementMain};

        UInt32 dataSize = 0;
        OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress,
                                                         0, nullptr, &dataSize);

        if (status == noErr && dataSize > 0) {
            std::vector<AudioDeviceID> devices(dataSize / sizeof(AudioDeviceID));
            status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                                nullptr, &dataSize, devices.data());

            if (status == noErr) {
                for (AudioDeviceID deviceID : devices) {
                    CFStringRef deviceUID = nullptr;
                    UInt32 uidSize = sizeof(deviceUID);
                    AudioObjectPropertyAddress uidAddress = {kAudioDevicePropertyDeviceUID,
                                                             kAudioObjectPropertyScopeGlobal,
                                                             kAudioObjectPropertyElementMain};

                    status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nullptr, &uidSize,
                                                        &deviceUID);

                    if (status == noErr && deviceUID != nullptr) {
                        NSString *nsUID = (__bridge NSString *)deviceUID;
                        if ([nsUID isEqualToString:@(kAggregateDeviceUID)]) {
                            CFRelease(deviceUID);
                            return deviceID; // Found it
                        }
                        CFRelease(deviceUID); // Not a match, release it
                    }
                }
            }
        }

        // --- Create a new one if not found ---

        // Get the UUID string from the tap description provided.
        NSString *tapUID = [[tapDescription UUID] UUIDString];

        NSArray<NSDictionary *> *taps = @[ @{
            @kAudioSubTapUIDKey : tapUID,
            @kAudioSubTapDriftCompensationKey : @YES,
        } ];

        NSDictionary *aggregateDeviceProperties = @{
            @kAudioAggregateDeviceNameKey : @"BIASAggregateDevice",
            @kAudioAggregateDeviceUIDKey : @(SystemAudioTapper::kAggregateDeviceUID),

            @kAudioAggregateDeviceTapListKey : taps,
            @kAudioAggregateDeviceTapAutoStartKey : @NO,
            @kAudioAggregateDeviceIsPrivateKey : @YES,
        };

        AudioDeviceID newDeviceID = kAudioObjectUnknown;
        status = AudioHardwareCreateAggregateDevice(
                (__bridge CFDictionaryRef)aggregateDeviceProperties, &newDeviceID);

        return (status == noErr) ? newDeviceID : kAudioObjectUnknown;
    }

} // namespace audio_tap
} // namespace pg
