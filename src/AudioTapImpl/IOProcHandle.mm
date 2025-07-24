#include "IOProcHandle.h"
namespace pg {
namespace audio_tap {

    IOProcHandle::IOProcHandle(AudioDeviceID deviceID, AudioCallback callback)
      : ownerDeviceID_(deviceID), callback_(std::move(callback))
    {
        if (ownerDeviceID_ == kAudioObjectUnknown || !callback_) { return; }

        OSStatus status =
                AudioDeviceCreateIOProcID(ownerDeviceID_, ioproc_callback, this, &ioProcID_);
        if (status != noErr) {
            ioProcID_ = nullptr;
            return;
        }

        status = AudioDeviceStart(ownerDeviceID_, ioProcID_);
        if (status != noErr) {
            AudioDeviceDestroyIOProcID(ownerDeviceID_, ioProcID_);
            ioProcID_ = nullptr;
        }
    }

    IOProcHandle::~IOProcHandle()
    {
        if (isValid()) {
            AudioDeviceStop(ownerDeviceID_, ioProcID_);
            AudioDeviceDestroyIOProcID(ownerDeviceID_, ioProcID_);
        }
    }

    // Move constructor
    IOProcHandle::IOProcHandle(IOProcHandle &&other) noexcept
      : ownerDeviceID_(other.ownerDeviceID_),
        ioProcID_(other.ioProcID_),
        callback_(std::move(other.callback_))
    {
        other.ownerDeviceID_ = kAudioObjectUnknown;
        other.ioProcID_ = nullptr;
    }

    // Move assignment
    IOProcHandle &IOProcHandle::operator=(IOProcHandle &&other) noexcept
    {
        if (this != &other) {
            if (isValid()) {
                AudioDeviceStop(ownerDeviceID_, ioProcID_);
                AudioDeviceDestroyIOProcID(ownerDeviceID_, ioProcID_);
            }
            ownerDeviceID_ = other.ownerDeviceID_;
            ioProcID_ = other.ioProcID_;
            callback_ = std::move(other.callback_);
            other.ownerDeviceID_ = kAudioObjectUnknown;
            other.ioProcID_ = nullptr;
        }
        return *this;
    }

    OSStatus IOProcHandle::ioproc_callback(AudioObjectID, const AudioTimeStamp *,
                                           const AudioBufferList *inInputData,
                                           const AudioTimeStamp *, AudioBufferList *,
                                           const AudioTimeStamp *, void *__nullable inClientData)
    {
        auto *self = static_cast<IOProcHandle *>(inClientData);
        if (self && self->callback_) { self->callback_(inInputData); }
        return noErr;
    }

} // namespace audio_tap
} // namespace pg
