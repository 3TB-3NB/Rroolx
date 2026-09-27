// language: Objective-C, file: LuauRuntime.h, runtime: iOS 15+

#ifndef LuauRuntime_h
#define LuauRuntime_h

#import <Foundation/Foundation.h>
#import "LuauTypes.h"

typedef struct {
    uintptr_t  luaStateAddr;
    uintptr_t  luauExecuteAddr;
    uintptr_t  robloxBase;
    uintptr_t  robloxSize;
    BOOL       found;
} LuaRuntimeInfo;

@interface LuauRuntime : NSObject

+ (instancetype)shared;

- (BOOL)discoverAll;
- (uintptr_t)scanForPattern:(const uint8_t *)pattern
                     length:(size_t)length
                       mask:(const uint8_t *)mask
                    maxHits:(int)maxHits;
- (uintptr_t)findLuauExecuteInRoblox;
- (LuaRuntimeInfo)info;
- (lua_State *)mainState;

@end

#endif
