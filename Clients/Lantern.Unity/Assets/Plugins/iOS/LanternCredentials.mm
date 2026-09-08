#import <Foundation/Foundation.h>
#import <Security/Security.h>
extern "C" const char *LanternCredentialLoad(const char *server) {
 NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"Lantern companion",(__bridge id)kSecAttrAccount:[NSString stringWithUTF8String:server],(__bridge id)kSecReturnData:@YES};
 CFTypeRef data=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)query,&data)!=errSecSuccess)return NULL;
 NSString *token=[[NSString alloc]initWithData:(__bridge NSData *)data encoding:NSUTF8StringEncoding];CFRelease(data);return token?strdup(token.UTF8String):NULL;
}
extern "C" void LanternCredentialFree(const char *value){free((void *)value);}
extern "C" void LanternCredentialSave(const char *server,const char *token){
 NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"Lantern companion",(__bridge id)kSecAttrAccount:[NSString stringWithUTF8String:server]};
 NSData *data=[[NSString stringWithUTF8String:token] dataUsingEncoding:NSUTF8StringEncoding];
 if(SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data})==errSecItemNotFound){NSMutableDictionary *item=[query mutableCopy];item[(__bridge id)kSecValueData]=data;item[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;SecItemAdd((__bridge CFDictionaryRef)item,NULL);}
}
