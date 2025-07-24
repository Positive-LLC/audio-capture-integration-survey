#include "ScreenCaptureAudioRecorder.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

// ---
// MARK: Pimpl Idiom: Objective-C Implementation Class
// ---

typedef NS_ENUM(NSInteger, PGRecorderState) {
    PGRecorderStateIdle,      // Initial state, ready to start.
    PGRecorderStateStarting,  // `startRecording` called, configuring stream.
    PGRecorderStateRecording, // Actively capturing and writing samples.
    PGRecorderStateStopping,  // `stopRecording` called, finalizing asset writer.
    PGRecorderStateSucceeded, // Operation finished successfully.
    PGRecorderStateFailed     // Operation terminated with an error.
};

@interface PGScreenRecorderImpl : NSObject <SCStreamDelegate, SCStreamOutput>

// Public properties (derived from state)
@property(nonatomic, readonly) BOOL isRecording;
@property(nonatomic, readonly) BOOL hasFinished;

// Public properties (stored)
@property(nonatomic, strong, nullable) NSError *lastError;
@property(nonatomic, strong, nullable) NSURL *outputURL;

// Private properties
@property(nonatomic, assign) PGRecorderState state;
@property(nonatomic, strong, nullable) SCStream *stream;
@property(nonatomic, strong, nullable) AVAssetWriter *assetWriter;
@property(nonatomic, strong, nullable) AVAssetWriterInput *assetWriterInput;

// Public methods
- (void)startRecording;
- (void)stopRecording;

@end

@implementation PGScreenRecorderImpl

- (instancetype)init
{
    self = [super init];
    if (self) {
        _state = PGRecorderStateIdle;
        _lastError = nil;
    }
    return self;
}

- (BOOL)isRecording
{
    return self.state == PGRecorderStateRecording;
}

- (BOOL)hasFinished
{
    return self.state == PGRecorderStateSucceeded || self.state == PGRecorderStateFailed;
}

- (void)startRecording
{
    if (self.state != PGRecorderStateIdle && self.state != PGRecorderStateSucceeded &&
        self.state != PGRecorderStateFailed) {
        return;
    }

    if (!self.outputURL) {
        self.lastError =
                [NSError errorWithDomain:@"com.pg.AudioRecorderError"
                                    code:-1
                                userInfo:@{NSLocalizedDescriptionKey : @"Output URL was not set."}];
        self.state = PGRecorderStateFailed;
        return;
    }

    // Reset for the new recording session.
    self.state = PGRecorderStateStarting;
    self.lastError = nil;
    self.assetWriter = nil;
    self.assetWriterInput = nil;

    [SCShareableContent
            getShareableContentExcludingDesktopWindows:NO
                                   onScreenWindowsOnly:YES
                                     completionHandler:^(SCShareableContent *_Nullable content,
                                                         NSError *_Nullable error) {
                                       if (error) {
                                           // This handles errors like lack of screen capture
                                           // permission. Note: On macOS, even if the user accepts
                                           // permission, the app often needs to be restarted for
                                           // the permission change to take effect. This means the
                                           // first recording attempt after launching and being
                                           // prompted might fail, and a subsequent attempt after a
                                           // restart will succeed.
                                           self.lastError = error;
                                           self.state = PGRecorderStateFailed;
                                           return;
                                       }
                                       [self setupAndStartStreamWithContent:content];
                                     }];
}

- (void)stopRecording
{
    if (self.state != PGRecorderStateRecording) { return; }

    self.state = PGRecorderStateStopping;

    if (!self.assetWriter || self.assetWriter.status != AVAssetWriterStatusWriting) {
        if (self.stream) [self.stream stopCaptureWithCompletionHandler:nil];
        self.state = PGRecorderStateFailed;
        return;
    }

    [self.assetWriterInput markAsFinished];
    [self.assetWriter finishWritingWithCompletionHandler:^{
      if (self.stream) [self.stream stopCaptureWithCompletionHandler:nil];

      if (self.assetWriter.status == AVAssetWriterStatusFailed) {
          self.lastError = self.assetWriter.error;
          self.state = PGRecorderStateFailed;
      } else {
          self.state = PGRecorderStateSucceeded;
      }
    }];
}

#pragma mark - Private Methods

- (void)setupAndStartStreamWithContent:(SCShareableContent *)content
{
    SCDisplay *mainDisplay = content.displays.firstObject;
    if (!mainDisplay) {
        self.lastError = [NSError
                errorWithDomain:@"com.pg.AudioRecorderError"
                           code:-1
                       userInfo:@{NSLocalizedDescriptionKey : @"No available display found."}];
        self.state = PGRecorderStateFailed;
        return;
    }

    SCContentFilter *filter = [self createContentFilterForDisplay:mainDisplay];

    SCStreamConfiguration *config = [self createStreamConfiguration];

    self.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];

    if (![self setupStreamOutputs]) { return; }

    [self startCapture];
}

- (SCContentFilter *)createContentFilterForDisplay:(SCDisplay *)display
{
    return [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
}

- (SCStreamConfiguration *)createStreamConfiguration
{
    SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
    config.capturesAudio = YES;
    config.channelCount = 2;
    config.width = 2;
    config.height = 2;
    return config;
}

- (BOOL)setupStreamOutputs
{
    NSError *streamError = nil;
    [self.stream addStreamOutput:self
                            type:SCStreamOutputTypeAudio
              sampleHandlerQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                           error:&streamError];

    if (streamError) {
        self.lastError = streamError;
        self.state = PGRecorderStateFailed;
        return NO;
    }

    // Add a screen output to satisfy ScreenCaptureKit, even if we don't process it.
    [self.stream addStreamOutput:self
                            type:SCStreamOutputTypeScreen
              sampleHandlerQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                           error:nil];
    return YES;
}

- (void)startCapture
{
    [self.stream startCaptureWithCompletionHandler:^(NSError *_Nullable captureError) {
      if (captureError) {
          self.lastError = captureError;
          self.state = PGRecorderStateFailed;
          return;
      }
      self.state = PGRecorderStateRecording;
    }];
}

- (AVAssetWriterInput *)createAssetWriterInputWithSourceFormatDescription:
        (CMFormatDescriptionRef)formatDescription
{
    const AudioStreamBasicDescription *sourceFormat =
            CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);

    NSDictionary *outputSettings = @{
        AVFormatIDKey : @(kAudioFormatMPEG4AAC),
        AVNumberOfChannelsKey : @(sourceFormat->mChannelsPerFrame),
        AVSampleRateKey : @(sourceFormat->mSampleRate),
        AVEncoderAudioQualityKey : @(AVAudioQualityHigh)
    };

    AVAssetWriterInput *input =
            [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                               outputSettings:outputSettings
                                             sourceFormatHint:formatDescription];
    input.expectsMediaDataInRealTime = YES;
    return input;
}

- (BOOL)setupAssetWriterWithInitialSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    NSError *writerError = nil;
    self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputURL
                                                 fileType:AVFileTypeMPEG4
                                                    error:&writerError];
    if (writerError) {
        self.lastError = writerError;
        [self stopRecording];
        return NO;
    }

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    self.assetWriterInput =
            [self createAssetWriterInputWithSourceFormatDescription:formatDescription];

    if (![self.assetWriter canAddInput:self.assetWriterInput]) {
        self.lastError = [NSError
                errorWithDomain:@"com.pg.AudioRecorderError"
                           code:-2
                       userInfo:@{NSLocalizedDescriptionKey : @"Cannot add asset writer input."}];
        [self stopRecording];
        return NO;
    }

    [self.assetWriter addInput:self.assetWriterInput];
    return YES;
}

- (void)assetWriterAppendSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (self.assetWriter.status != AVAssetWriterStatusWriting ||
        !self.assetWriterInput.isReadyForMoreMediaData) {
        return;
    }

    if (![self.assetWriterInput appendSampleBuffer:sampleBuffer]) {
        self.lastError = self.assetWriter.error;
    }
}

#pragma mark - SCStreamDelegate

- (void)startWritingSessionWithInitialSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self.assetWriter startWriting];
    [self.assetWriter
            startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
}

- (void)stream:(SCStream *)stream
        didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                       ofType:(SCStreamOutputType)type
{
    if (type != SCStreamOutputTypeAudio) { return; }

    if (!self.assetWriter) {
        if (![self setupAssetWriterWithInitialSampleBuffer:sampleBuffer]) { return; }
        [self startWritingSessionWithInitialSampleBuffer:sampleBuffer];
    }

    [self assetWriterAppendSampleBuffer:sampleBuffer];
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error
{
    self.lastError = error;
    self.state = PGRecorderStateFailed;
}

@end


// ---
// MARK: C++ Wrapper Implementation
// ---

// Helper to convert juce::File to NSURL
static NSURL *juceFileToNSURL(const juce::File &file)
{
    return [NSURL
            fileURLWithPath:[NSString stringWithUTF8String:file.getFullPathName().toRawUTF8()]];
}

namespace pg {

// C++ Pimpl class definition
class ScreenCaptureAudioRecorder::Impl
{
public:
    Impl() { recorder_ = [[PGScreenRecorderImpl alloc] init]; }

    ~Impl()
    {
        if (recorder_) {
            [recorder_ stopRecording];
            [recorder_ release];
            recorder_ = nil;
        }
    }

    auto startRecording(const juce::File &outputFile) -> bool
    {
        if ([recorder_ isRecording]) { return false; }

        NSURL *nsURL = juceFileToNSURL(outputFile);
        [recorder_ setOutputURL:nsURL];
        [recorder_ startRecording];
        return true;
    }

    auto stopRecording() -> void
    {
        if ([recorder_ isRecording]) { [recorder_ stopRecording]; }
    }

    auto isRecording() const -> bool { return [recorder_ isRecording]; }

    auto hasFinishedRecording() const -> bool { return [recorder_ hasFinished]; }

private:
    PGScreenRecorderImpl *recorder_ = nil;
};

// C++ Public Interface implementation (delegating to Pimpl)
ScreenCaptureAudioRecorder::ScreenCaptureAudioRecorder() : pImpl_(std::make_unique<Impl>()) {}

ScreenCaptureAudioRecorder::~ScreenCaptureAudioRecorder() = default;

auto ScreenCaptureAudioRecorder::startRecording(const juce::File &outputFile) -> bool
{
    return pImpl_->startRecording(outputFile);
}

auto ScreenCaptureAudioRecorder::stopRecording() -> void
{
    pImpl_->stopRecording();
}

auto ScreenCaptureAudioRecorder::isRecording() const -> bool
{
    return pImpl_->isRecording();
}

auto ScreenCaptureAudioRecorder::hasFinishedRecording() const -> bool
{
    return pImpl_->hasFinishedRecording();
}

auto ScreenCaptureAudioRecorder::hasScreenRecordingPermission() -> bool
{
    if (@available(macOS 12.3, *)) { return CGPreflightScreenCaptureAccess(); }
    return false;
}

auto ScreenCaptureAudioRecorder::requestScreenRecordingPermission() -> void
{
    if (@available(macOS 12.3, *)) { CGRequestScreenCaptureAccess(); }
}

} // namespace pg
