# Core Audio Tap POC Report

This document provides a technical overview of the Proof of Concept (POC) for using Core Audio's "Tap" functionality to capture system audio output.

## 1. Introduction: What is Core Audio Tap?

Core Audio Tap is a mechanism provided by Apple's Core Audio framework on macOS that allows an application to "tap into" and monitor the audio data of a running process or a system audio device.

For this POC, the primary goal is to tap into an **aggregate audio device** that contains system **default audio device**. An aggregate device is a virtual audio device in macOS that combines multiple physical audio inputs and outputs into a single, unified virtual device. By tapping this device, we can capture the system's mixed audio output.

## 2. How to Initialize and Listen for Output

The process of setting up a Core Audio Tap involves several steps using specific Core Audio APIs to create the necessary components and hook into the audio stream.

The general workflow is as follows:

1.  **Get Default Output Device**: Identify the system's current default audio output device. This is the device whose audio we intend to capture.
2.  **Create Tap Description**: An instance of `CATapDescription` is created. It is configured to tap the default output device identified in the previous step and can specify which processes to include or exclude. The key API for this is `-[CATapDescription initWithProcesses:andDeviceUID:withStream:]`.
3.  **Create Aggregate Device**: An aggregate device is created based on the tap description. This virtual device will expose the tapped audio stream.
4.  **Create Process Tap**: With the description configured, the actual tap is created by calling `AudioHardwareCreateProcessTap`, which provides the `AudioObjectID` of the new tap via an output parameter.
5.  **Set Up IO Callback**: To process the audio data, an I/O procedure (a callback function) is registered with the aggregate device using `AudioDeviceCreateIOProcID`. Once registered, the device is started with `AudioDeviceStart`.
6.  **Process Audio**: After the device is started, the registered callback function is repeatedly invoked, receiving audio data in an `AudioBufferList` which can then be processed or saved.

## 3. How to Detect Device Changes

To ensure the tap remains valid and handles system changes gracefully, it's necessary to listen for property changes on the audio devices.

This is achieved by registering a property listener with `AudioObjectAddPropertyListener`. This function takes an `AudioObjectPropertyAddress`, which specifies a set of properties to monitor. When a monitored property changes (e.g., the sample rate of a device is altered), a registered callback function is invoked, allowing the application to react accordingly.

## 4. Current Implementation Status

The current POC successfully implements the core tapping functionality with the following characteristics:

-   **Taps Default Device**: The implementation listens to the system's default output device. As a result, it can capture audio from any application that outputs to this device.
-   **Self-Monitoring**: Currently, if our own application plays audio to the default device, that audio is also captured. This can be resolved by configuring the `CATapDescription` to exclude our own process.
-   **CAF Output**: When recording is stopped, the captured audio is saved to a file in the Core Audio Format (CAF). The audio data is currently uncompressed.
-   **Handles Configuration Changes**: If the properties of the tapped device change (e.g., sample rate), the recording will automatically stop.
-   **Known Limitation**: If the user switches the system's default device *after* recording has started (e.g., from built-in speakers to headphones), the recording continues but will not capture audio from the new device.

## 5. Implementation Details

The implementation is structured with a primary coordinator class, `CoreAudioTapRecorder`, which uses the Pimpl idiom. The private implementation (`CoreAudioTapRecorder::Impl`) owns and manages several RAII (Resource Acquisition Is Initialization) wrapper classes that handle the complexities of Core Audio objects.

### CoreAudioTapRecorder (The Coordinator)

The `CoreAudioTapRecorder` class serves as the public-facing interface for the audio tapping functionality. Its internal `Impl` class coordinates the different components of the system. It owns the main RAII wrappers for:

-   The tap session itself (`TappingSessionHandle`)
-   The audio data handling and file writing (`AudioDataHandler`)
-   The Core Audio IO procedure callback (`IOProcHandle`)

### RAII Wrappers for Core Audio Objects

The implementation is broken down into several classes, each responsible for managing a specific Core Audio object or concept. This encapsulates the C-style Core Audio APIs in a modern C++ interface.

-   **`AudioDeviceUtils`**: A utility class providing static methods to query for and interact with system audio devices, such as finding the default output device.

-   **`SystemAudioTapper`**: A singleton class responsible for managing the lifecycle of the aggregate device used for tapping. It ensures that only one aggregate device is created for the application.

-   **`TappingSessionHandle`**: A RAII-style wrapper that manages the `CATap` instance. Its primary responsibility is to acquire a tap session from the `SystemAudioTapper` and release it upon destruction. It also encapsulates the logic for adding and removing property listeners to detect device changes.

-   **`IOProcHandle`**: This class wraps the `AudioDeviceIOProcID`. It simplifies the creation and destruction of the I/O callback. It takes a C++ `std::function` in its constructor, which it invokes with the audio data from within the C-style `AudioDeviceIOProc` callback, bridging the Core Audio C API with modern C++.

-   **`AudioDataHandler`**: This component is responsible for processing the incoming audio data (`AudioBufferList`) from the `IOProcHandle`. It allocates a fixed-size buffer to store audio data; when the buffer becomes full, it invokes a callback to notify the system. It also manages writing the buffered data to a `.caf` file using `ExtAudioFile` APIs when recording stops.

## 6. TODO List

-   Investigate alternative `CATapDescription` initializers beyond the current approach of tapping a single device. The goal is to explore more robust methods for system-wide audio capture. This includes, but is not limited to:
    -   Tapping a mixdown of specific processes (`initStereoMixdownOfProcesses:`).
    -   Using a global tap that excludes certain processes (`initStereoGlobalTapButExcludeProcesses:`), which seems like a promising option for capturing all system audio except our own application.
    -   Experimenting with different combinations of aggregate devices and tap configurations.
-   Address the known limitation where switching the default audio device during a recording session does not stop the recording or switch the tap to the new device.
