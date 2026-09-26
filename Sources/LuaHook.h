// language: Objective-C, file: LuaHook.h, runtime: iOS 15+
// *الـ interface للتفاعل مع Luau VM + قراءة PlaceId*

#import <Foundation/Foundation.h>

typedef struct lua_State lua_State;

@interface LuaHook : NSObject

+ (instancetype)sharedInstance;

- (BOOL)installHooks;
- (void)removeHooks;

- (BOOL)executeLua:(NSString *)script error:(NSError **)error;

// 🔧 جديد: قراءة PlaceId الحالي من Luau VM
- (NSNumber *)currentPlaceId;

// قراءة اسم اللعبة
- (NSString *)currentGameName;

- (lua_State *)mainState;

@end
