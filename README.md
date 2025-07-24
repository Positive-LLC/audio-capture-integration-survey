# Audio Capture Integration Survey

This repository contains Proof of Concept (POC) code for integrating macOS system audio capture capabilities into the BIAS_ONE application.

## Integration Notes

Integrating this functionality into the main BIAS_ONE repository will require careful configuration of the build system. Specifically, the following macOS frameworks and entitlements must be correctly linked and set up:

### Required Frameworks

-   `CoreAudio`
-   `CoreMedia`
-   `AVFoundation`
-   `CoreFoundation`
-   `AudioToolbox`
-   `ScreenCaptureKit`

### Entitlements

The required entitlements differ based on the capture method:

-   **Core Audio Tap**: Requires the `NSAudioCaptureUsageDescription` key in the `.entitlements` file to describe the reason for capturing audio.
-   **ScreenCaptureKit**: Does not require a specific entitlement, as user permission is granted through the framework's UI prompt.

## Further Reading

-   **Basic Concepts & Initial POC**: For a foundational understanding of the approach, please refer to the original experiment: [https://git.positivegrid.com:8443/experiment/audio-capture-macos](https://git.positivegrid.com:8443/experiment/audio-capture-macos)
-   **Detailed Report**: For a comprehensive analysis of the different capture methods, implementation details, and a comparison, please see the detailed report: [`audio-tap-analysis/audio-capture-poc-survey-report.md`](audio-tap-analysis/audio-capture-poc-survey-report.md)