#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
extern "C" void UnitySendMessage(const char *,const char *,const char *);

@interface LanternMicrophoneBridge:NSObject
@property(nonatomic,strong)AVAudioEngine *engine;
@property(nonatomic,strong)AVAudioConverter *converter;
@property(nonatomic,copy)NSString *receiver;
@property(nonatomic)NSInteger generation;
@property(nonatomic)int request;
@property(nonatomic)BOOL tapped;
-(void)stop;
-(void)start:(int)request;
@end
@implementation LanternMicrophoneBridge
-(void)emit:(NSString *)type value:(NSString *)value request:(int)request {
 NSDictionary *event=@{@"type":type,@"id":@(request),[type isEqual:@"pcm"]?@"pcm":@"text":value?:@""};
 NSData *raw=[NSJSONSerialization dataWithJSONObject:event options:0 error:nil];NSString *json=[[NSString alloc]initWithData:raw encoding:NSUTF8StringEncoding];UnitySendMessage(self.receiver.UTF8String,"OnMicrophoneMessage",json.UTF8String);
}
-(void)stop { self.generation++;[self.engine stop];if(self.tapped){[self.engine.inputNode removeTapOnBus:0];self.tapped=NO;}self.engine=nil;self.converter=nil; }
-(void)start:(int)request {
 [self stop];self.request=request;NSInteger generation=self.generation;
 [AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted){dispatch_async(dispatch_get_main_queue(),^{
  if(generation!=self.generation)return;
  if(!granted){[self emit:@"error" value:@"Microphone permission is off. You can still explore with touch." request:request];return;}
  NSError *error=nil;AVAudioSession *audio=[AVAudioSession sharedInstance];
  [audio setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetoothHFP error:&error];
  if(!error)[audio setActive:YES error:&error];
  if(error){[self emit:@"error" value:@"The microphone is unavailable. Try again when you're ready." request:request];return;}
  self.engine=[AVAudioEngine new];AVAudioInputNode *input=self.engine.inputNode;
  [input setVoiceProcessingEnabled:YES error:&error];
  if(error){[self stop];[self emit:@"error" value:@"Voice recording could not start." request:request];return;}
  AVAudioFormat *format=[input outputFormatForBus:0];
  AVAudioFormat *target=[[AVAudioFormat alloc]initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:16000 channels:1 interleaved:YES];
  if(format.sampleRate==0||format.channelCount==0){[self stop];[self emit:@"error" value:@"No microphone is available." request:request];return;}
  self.converter=[[AVAudioConverter alloc]initFromFormat:format toFormat:target];
  __weak LanternMicrophoneBridge *weakSelf=self;
  [input installTapOnBus:0 bufferSize:4096 format:format block:^(AVAudioPCMBuffer *buffer,AVAudioTime *when){
   LanternMicrophoneBridge *owner=weakSelf;if(!owner||generation!=owner.generation)return;
   AVAudioPCMBuffer *output=[[AVAudioPCMBuffer alloc]initWithPCMFormat:target frameCapacity:(AVAudioFrameCount)(buffer.frameLength*16000.0/format.sampleRate+32)];
   __block BOOL consumed=NO;NSError *conversionError=nil;
   [owner.converter convertToBuffer:output error:&conversionError withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount packets,AVAudioConverterInputStatus *status){if(consumed){*status=AVAudioConverterInputStatus_NoDataNow;return nil;}consumed=YES;*status=AVAudioConverterInputStatus_HaveData;return buffer;}];
   if(conversionError||output.frameLength==0)return;
   NSData *pcm=[NSData dataWithBytes:output.int16ChannelData[0] length:output.frameLength*2];NSString *encoded=[pcm base64EncodedStringWithOptions:0];
   dispatch_async(dispatch_get_main_queue(),^{if(generation==weakSelf.generation)[weakSelf emit:@"pcm" value:encoded request:request];});
  }];self.tapped=YES;[self.engine prepare];
  if(![self.engine startAndReturnError:&error]){[self stop];[self emit:@"error" value:@"I couldn't start listening. Please try again." request:request];}
 });}];
}
@end
static LanternMicrophoneBridge *microphone;
extern "C" void LanternMicrophoneInitialize(const char *receiver){microphone=[LanternMicrophoneBridge new];microphone.receiver=[NSString stringWithUTF8String:receiver];}
extern "C" void LanternMicrophoneStart(int request){[microphone start:request];}
extern "C" void LanternMicrophoneStop(){[microphone stop];}
