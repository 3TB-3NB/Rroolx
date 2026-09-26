// language: Objective-C, file: LuaHook.h, runtime: iOS 15+

#import <Foundation/Foundation.h>
#import "LuauTypes.h"

@interface LuaHook : NSObject

+ (instancetype)sharedInstance;

- (BOOL)installHooks;
- (void)removeHooks;

- (BOOL)executeLua:(NSString *)script error:(NSError **)error;
- (NSNumber *)currentPlaceId;

- (lua_State *)mainState;

@end
