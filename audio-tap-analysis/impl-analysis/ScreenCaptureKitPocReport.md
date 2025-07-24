# ScreenCaptureKit POC Report

This document provides a technical overview of the Proof of Concept (POC) for using Apple's ScreenCaptureKit framework to record system audio.

## 1. Introduction: What is ScreenCaptureKit?

ScreenCaptureKit is a modern Apple framework designed for high-performance screen recording. While its primary function is capturing video from displays and applications, it also provides robust capabilities for capturing system audio.

For this POC, we leverage ScreenCaptureKit to capture the system-wide audio mix, which includes audio from all applications. This approach offers a more resilient alternative to lower-level Core Audio APIs, as it is less susceptible to changes in the user's audio device configuration.

Key resources:
-   Apple Documentation: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
-   Inspiration from Open Source: [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder)

## 2. How to Initialize and Capture Output

The initialization process involves creating and configuring an `SCStream` object to capture audio data and an `AVAssetWriter` to write that data to a file.

The general workflow is as follows:

1.  **Get Shareable Content**: Call `[SCShareableContent getShareableContentExcludingDesktopWindows:onScreenWindowsOnly:completionHandler:]` to asynchronously fetch a list of capturable content (displays, windows, etc.). This step also implicitly handles screen recording permissions.
2.  **Create a Content Filter**: An `SCContentFilter` is created to define what content will be captured. For our purposes, this is configured to capture the main display (`initWithDisplay:excludingWindows:`).
3.  **Configure the Stream**: An `SCStreamConfiguration` object is created. The crucial setting for our use case is `config.capturesAudio = YES;`. We must also set a minimal video size (e.g., 2x2 pixels) because the framework requires a video track to be configured, even if we don't process it.
4.  **Create the Stream**: An `SCStream` instance is initialized with the filter, configuration, and a delegate object. The delegate must conform to `SCStreamDelegate` and `SCStreamOutput`.
5.  **Add Stream Output**: The delegate is added as an output handler for `SCStreamOutputTypeAudio` by calling `[stream addStreamOutput:self type:...]`. This directs the captured audio samples to our delegate methods. A handler for `SCStreamOutputTypeScreen` must also be added to satisfy the framework's requirements, but we can ignore the video samples it provides.
6.  **Start Capture**: Call `[stream startCaptureWithCompletionHandler:]` to begin the asynchronous capture process.
7.  **Receive Audio Data**: The delegate method `-stream:didOutputSampleBuffer:ofType:` will be called repeatedly with audio data encapsulated in a `CMSampleBufferRef`.
8.  **Write to File**: The first time an audio buffer is received, an `AVAssetWriter` and `AVAssetWriterInput` are initialized. Subsequent buffers are appended to the file until the stream is stopped.

## 3. Current Implementation Status

-   **System-Wide Audio Capture**: The POC successfully captures the mixed audio output of the entire system, not tied to a specific audio device.
-   **Resilience to Device Changes**: A key advantage of this method is its resilience. The recording continues uninterrupted and captures audio correctly even if the user changes the default audio device (e.g., switches from speakers to headphones) or modifies the sample rate during the session.
-   **M4A (AAC) Output**: The captured audio is written to an M4A file (`.m4a`) using the AAC codec for efficient compression.
-   **Asynchronous Operation**: The entire recording process is asynchronous and callback-based, ensuring the main thread is not blocked.
-   **Permission Handling**: The implementation correctly handles scenarios where screen capture permission has not been granted.

## 4. Implementation Details

The implementation is encapsulated within the `ScreenCaptureAudioRecorder` C++ class, which uses the Pimpl idiom to hide the Objective-C details.

### Pimpl Implementation (`PGScreenRecorderImpl`)

The core logic resides in `PGScreenRecorderImpl`, an Objective-C class that acts as the delegate and handler for the ScreenCaptureKit stream.

-   **Delegate and Handler**: It conforms to the `SCStreamDelegate` and `SCStreamOutput` protocols to manage the stream's lifecycle and process incoming data.
-   **State Management**: It uses an internal state machine (`PGRecorderState`) to track the recorder's status (Idle, Starting, Recording, Stopping, Succeeded, Failed), ensuring operations are performed in the correct sequence.
-   **Component Coordination**: It is responsible for orchestrating the interaction between the `SCStream` (capturing) and the `AVAssetWriter` (file writing). When the first audio buffer arrives, it configures and starts the asset writer. When `stopRecording` is called, it finalizes the asset writer and then stops the capture stream.

## 5. TODO List

-   N/A
