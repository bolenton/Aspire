#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <UIKit/UIKit.h>

extern "C" void UnitySendMessage(const char *, const char *, const char *);

@interface LanternSpeechBridge : NSObject <AVSpeechSynthesizerDelegate>
@property(nonatomic, copy) NSString *receiver;
@property(nonatomic, strong) AVSpeechSynthesizer *synthesizer;
@property(nonatomic, strong) AVAudioEngine *audio;
@property(nonatomic, strong) SFSpeechRecognizer *recognizer;
@property(nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property(nonatomic, strong) SFSpeechRecognitionTask *task;
@property(nonatomic, strong) AVSpeechUtterance *utterance;
@property(nonatomic) NSInteger requestID;
@property(nonatomic) NSInteger generation;
@property(nonatomic) BOOL installedTap;
@property(nonatomic, copy) NSString *partialText;
- (void)stop;
- (void)listen:(NSInteger)requestID;
- (void)emit:(NSString *)kind text:(NSString *)text;
@end

@implementation LanternSpeechBridge
- (instancetype)init {
    if ((self = [super init])) {
        _synthesizer = [AVSpeechSynthesizer new];
        _synthesizer.delegate = self;
        _audio = [AVAudioEngine new];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}
- (void)emit:(NSString *)kind text:(NSString *)text {
    if (!self.receiver) return;
    NSDictionary *payload = @{ @"kind": kind, @"text": text ?: @"", @"request": @(self.requestID) };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    UnitySendMessage(self.receiver.UTF8String, "OnSpeechMessage", json.UTF8String);
}
- (void)stop {
    self.generation++;
    self.utterance = nil;
    [self.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self.audio stop];
    if (self.installedTap) { [self.audio.inputNode removeTapOnBus:0]; self.installedTap = NO; }
    [self.recognitionRequest endAudio];
    [self.task cancel];
    self.task = nil;
    self.recognitionRequest = nil;
    self.partialText = @"";
}
- (void)interrupted:(NSNotification *)notification {
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan) {
        [self stop];
        [self emit:@"error" text:@"The sound was interrupted. We have stopped. Tap Talk when you're ready."];
    }
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance == self.utterance) { self.utterance = nil; [self emit:@"finished" text:@""]; }
}
- (void)finishListening {
    NSString *words = self.partialText;
    [self stop];
    if (words.length) [self emit:@"recognized" text:words];
    else [self emit:@"error" text:@"I didn't hear that. Try Talk again, or use the buttons."];
}
- (void)startRecognition:(NSInteger)generation {
    if (generation != self.generation) return;
    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
    if (!self.recognizer.available || !self.recognizer.supportsOnDeviceRecognition) {
        [self emit:@"error" text:@"Offline speech is not available on this device yet. You can still use every adventure button."];
        return;
    }
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothHFP error:&error];
    if (!error) [session setActive:YES error:&error];
    if (error) { [self emit:@"error" text:@"The microphone is unavailable. Use the buttons for now."]; return; }
    self.recognitionRequest = [SFSpeechAudioBufferRecognitionRequest new];
    self.recognitionRequest.shouldReportPartialResults = YES;
    self.recognitionRequest.requiresOnDeviceRecognition = YES;
    AVAudioInputNode *input = self.audio.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate == 0 || format.channelCount == 0) { [self emit:@"error" text:@"No microphone is connected."]; return; }
    __weak LanternSpeechBridge *weakSelf = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [weakSelf.recognitionRequest appendAudioPCMBuffer:buffer];
    }];
    self.installedTap = YES;
    self.task = [self.recognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LanternSpeechBridge *owner = weakSelf;
            if (!owner || generation != owner.generation) return;
            if (result) {
                owner.partialText = result.bestTranscription.formattedString;
                [owner emit:@"partial" text:owner.partialText];
            }
            if (result.isFinal || error) [owner finishListening];
        });
    }];
    [self.audio prepare];
    if (![self.audio startAndReturnError:&error]) { [self stop]; [self emit:@"error" text:@"I couldn't start listening. Use the buttons or try again."]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == weakSelf.generation) [weakSelf finishListening];
    });
}
- (void)listen:(NSInteger)requestID {
    [self stop]; self.requestID = requestID;
    NSInteger generation = self.generation;
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) { [self emit:@"error" text:@"Speech permission is off. The adventure buttons still work."]; return; }
            [AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.generation) return;
                    if (granted) [self startRecognition:generation];
                    else [self emit:@"error" text:@"Microphone permission is off. The adventure buttons still work."];
                });
            }];
        });
    }];
}
@end

static LanternSpeechBridge *bridge;
extern "C" void LanternSpeechInitialize(const char *receiver) {
    bridge = [LanternSpeechBridge new];
    bridge.receiver = [NSString stringWithUTF8String:receiver];
}
extern "C" void LanternSpeechStop(void) { [bridge stop]; }
extern "C" void LanternListen(int requestID) { [bridge listen:requestID]; }
extern "C" void LanternSpeak(const char *text, float rate, float pitch, float volume, int requestID) {
    [bridge stop]; bridge.requestID = requestID;
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    if (!error) [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) { [bridge emit:@"error" text:@"Narration is unavailable. The words are on screen."]; return; }
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:[NSString stringWithUTF8String:text]];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    utterance.rate = fminf(AVSpeechUtteranceMaximumSpeechRate, fmaxf(AVSpeechUtteranceMinimumSpeechRate, .45f * rate));
    utterance.pitchMultiplier = fminf(2, fmaxf(.5f, pitch));
    utterance.volume = fminf(1, fmaxf(0, volume));
    bridge.utterance = utterance;
    [bridge.synthesizer speakUtterance:utterance];
}
