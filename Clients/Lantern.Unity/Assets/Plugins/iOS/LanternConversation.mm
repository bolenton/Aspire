#import <Foundation/Foundation.h>

extern "C" void UnitySendMessage(const char *, const char *, const char *);
// The Swift class has this explicit Objective-C runtime name.
@interface LanternConversationBridge : NSObject
+ (int32_t)availability;
+ (void)cancel:(int32_t)request;
+ (void)respond:(NSString *)payload request:(int32_t)request completion:(void (^)(NSString *))completion;
@end

extern "C" int LanternConversationAvailability(void) { return [LanternConversationBridge availability]; }
extern "C" void LanternConversationCancel(int request) {
    dispatch_async(dispatch_get_main_queue(), ^{ [LanternConversationBridge cancel:request]; });
}
extern "C" void LanternConversationReply(const char *receiver, const char *payload, int request) {
    NSString *target = [NSString stringWithUTF8String:receiver];
    NSString *input = [NSString stringWithUTF8String:payload];
    dispatch_async(dispatch_get_main_queue(), ^{
        [LanternConversationBridge respond:input request:request completion:^(NSString *result) {
            UnitySendMessage(target.UTF8String, "OnConversationMessage", result.UTF8String);
        }];
    });
}
