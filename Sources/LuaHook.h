// language: Objective-C, file: LuaHook.h, runtime: iOS 15+
// *الـ interface للتفاعل مع Luau VM*

#import <Foundation/Foundation.h>

typedef struct lua_State lua_State;

@interface LuaHook : NSObject

+ (instancetype)sharedInstance;

- (BOOL)installHooks;
- (void)removeHooks;

- (BOOL)executeLua:(NSString *)script error:(NSError **)error;

// للوصول لـ lua_State الرئيسي (لو احتجناه لاحقاً)
- (lua_State *)mainState;

@end
