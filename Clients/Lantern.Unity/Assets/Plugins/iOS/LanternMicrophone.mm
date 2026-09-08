#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#include <math.h>
extern "C" void UnitySendMessage(const char *,const char *,const char *);

@interface LanternMicrophoneBridge : NSObject
@property(nonatomic,strong) AVAudioEngine *engine;
@property(nonatomic,strong) dispatch_queue_t controlQueue;
@property(nonatomic,copy) NSString *receiver;
@property(atomic) NSInteger generation;
@property(atomic) int request;
@property(atomic) BOOL capturing;
@property(nonatomic) BOOL tapped;
-(void)pause;
-(void)shutdown;
-(void)start:(int)request;
@end

@implementation LanternMicrophoneBridge
-(instancetype)init {
 if((self=[super init])) _controlQueue=dispatch_queue_create("lantern.microphone.control",DISPATCH_QUEUE_SERIAL);
 return self;
}
-(void)emit:(NSString *)type text:(NSString *)text pcm:(NSString *)pcm level:(double)level request:(int)request {
 NSDictionary *event=@{@"type":type,@"id":@(request),@"text":text?:@"",@"pcm":pcm?:@"",@"level":@(level)};
 NSData *raw=[NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
 NSString *json=[[NSString alloc]initWithData:raw encoding:NSUTF8StringEncoding];
 dispatch_async(dispatch_get_main_queue(),^{
  if(request!=self.request)return;
  if([type isEqualToString:@"pcm"]&&!self.capturing)return;
  UnitySendMessage(self.receiver.UTF8String,"OnMicrophoneMessage",json.UTF8String);
 });
}
-(void)pause { self.capturing=NO;self.generation++; }
-(void)closeEngine {
 [self.engine stop];
 if(self.tapped){[self.engine.inputNode removeTapOnBus:0];self.tapped=NO;}
 self.engine=nil;
}
-(void)shutdown {
 [self pause];
 dispatch_async(self.controlQueue,^{[self closeEngine];});
}
-(void)start:(int)request {
 [self pause];self.request=request;NSInteger generation=self.generation;
 void (^begin)(BOOL)=^(BOOL granted){
  if(generation!=self.generation)return;
  if(!granted){[self emit:@"error" text:@"Microphone permission is off. You can enable it in Settings, or turn voice mode off and explore." pcm:nil level:0 request:request];return;}
  dispatch_async(self.controlQueue,^{
   if(generation!=self.generation)return;
   if(!self.engine.isRunning){
    [self closeEngine];NSError *error=nil;
    AVAudioSession *audio=[AVAudioSession sharedInstance];
    [audio setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetoothHFP error:&error];
    if(!error)[audio setPreferredIOBufferDuration:.01 error:&error];
    if(!error)[audio setActive:YES error:&error];
    if(error){[self emit:@"error" text:@"The microphone is unavailable. Voice mode will try again." pcm:nil level:0 request:request];return;}
    self.engine=[AVAudioEngine new];AVAudioInputNode *input=self.engine.inputNode;
    [input setVoiceProcessingEnabled:YES error:&error];
    AVAudioFormat *format=[input outputFormatForBus:0];
    if(error||format.sampleRate==0||format.channelCount==0){[self closeEngine];[self emit:@"error" text:@"The microphone could not start. Voice mode will try again." pcm:nil level:0 request:request];return;}
    AVAudioFormat *target=[[AVAudioFormat alloc]initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:16000 channels:1 interleaved:YES];
    AVAudioConverter *converter=[[AVAudioConverter alloc]initFromFormat:format toFormat:target];
    __weak LanternMicrophoneBridge *weakSelf=self;
    [input installTapOnBus:0 bufferSize:2048 format:format block:^(AVAudioPCMBuffer *buffer,AVAudioTime *when){
     LanternMicrophoneBridge *owner=weakSelf;if(!owner.capturing)return;
     int captureID=owner.request;
     AVAudioPCMBuffer *output=[[AVAudioPCMBuffer alloc]initWithPCMFormat:target frameCapacity:(AVAudioFrameCount)(buffer.frameLength*16000.0/format.sampleRate+32)];
     __block BOOL consumed=NO;NSError *conversionError=nil;
     [converter convertToBuffer:output error:&conversionError withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount packets,AVAudioConverterInputStatus *status){
      if(consumed){*status=AVAudioConverterInputStatus_NoDataNow;return nil;}
      consumed=YES;*status=AVAudioConverterInputStatus_HaveData;return buffer;
     }];
     if(conversionError||output.frameLength==0||!owner.capturing)return;
     const int16_t *samples=output.int16ChannelData[0];double energy=0;
     for(AVAudioFrameCount i=0;i<output.frameLength;i++){double v=samples[i]/32768.0;energy+=v*v;}
     double level=fmin(1,sqrt(energy/output.frameLength)*8);
     NSData *pcm=[NSData dataWithBytes:samples length:output.frameLength*2];
     [owner emit:@"pcm" text:nil pcm:[pcm base64EncodedStringWithOptions:0] level:level request:captureID];
    }];
    self.tapped=YES;[self.engine prepare];
    if(![self.engine startAndReturnError:&error]){[self closeEngine];[self emit:@"error" text:@"The microphone could not start. Voice mode will try again." pcm:nil level:0 request:request];return;}
   }
   if(generation!=self.generation)return;
   self.capturing=YES;
   [self emit:@"ready" text:nil pcm:nil level:0 request:request];
  });
 };
 if(AVAudioApplication.sharedInstance.recordPermission==AVAudioApplicationRecordPermissionGranted)begin(YES);
 else [AVAudioApplication requestRecordPermissionWithCompletionHandler:begin];
}
@end
static LanternMicrophoneBridge *microphone;
extern "C" void LanternMicrophoneInitialize(const char *receiver){microphone=[LanternMicrophoneBridge new];microphone.receiver=[NSString stringWithUTF8String:receiver];}
extern "C" void LanternMicrophoneStart(int request){[microphone start:request];}
extern "C" void LanternMicrophoneStop(){[microphone pause];}
extern "C" void LanternMicrophoneShutdown(){[microphone shutdown];}
