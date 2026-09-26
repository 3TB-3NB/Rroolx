// language: Objective-C, file: LuauRuntime.m, runtime: iOS 15+

#import "LuauRuntime.h"
#import <os/log.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>
#import <string.h>

static os_log_t g_log;

static const uint8_t kLuauExecutePattern[] = {
    0xfc, 0x6f, 0xba, 0xa9,
    0xfa, 0x67, 0x01, 0xa9,
    0xf8, 0x5f, 0x02, 0xa9,
    0xf6, 0x57, 0x03, 0xa9,
    0xf4, 0x4f, 0x04, 0xa9,
    0xfd, 0x7b, 0x05, 0xa9,
    0xfd, 0x03, 0x01, 0x91,
};

static const uint8_t kLuauExecutePattern2[] = {
    0xfc, 0x6f, 0xba, 0xa9,
    0xfa, 0x67, 0x01, 0xa9,
};

@interface LuauRuntime () {
    LuaRuntimeInfo _info;  // ← متغير عضو داخلي (مش property)
}
@end

@implementation LuauRuntime

+ (instancetype)shared {
    static LuauRuntime *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[LuauRuntime alloc] init];
        g_log = os_log_create("com.alpha.executor", "runtime");
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        memset(&_info, 0, sizeof(_info));
    }
    return self;
}

#pragma mark - اكتشاف Roblox

- (void)locateRoblox {
    if (_info.robloxBase) return;
    
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        
        if (strstr(name, "Roblox") && strstr(name, ".app")) {
            const struct mach_header_64 *hdr =
                (const struct mach_header_64 *)_dyld_get_image_header(i);
            _info.robloxBase = (uintptr_t)hdr;
            
            uintptr_t end = _info.robloxBase;
            const struct load_command *cmd = (const struct load_command *)(hdr + 1);
            for (uint32_t j = 0; j < hdr->ncmds; j++) {
                if (cmd->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *seg =
                        (const struct segment_command_64 *)cmd;
                    uintptr_t segEnd = seg->vmaddr + seg->vmsize;
                    if (segEnd > end) end = segEnd;
                }
                cmd = (const struct load_command *)((char *)cmd + cmd->cmdsize);
            }
            _info.robloxSize = end - _info.robloxBase;
            
            os_log_info(g_log, "Roblox @ 0x%lx (size 0x%lx)",
                        _info.robloxBase, _info.robloxSize);
            return;
        }
    }
    os_log_error(g_log, "Roblox not found");
}

#pragma mark - Pattern Scanning

- (uintptr_t)scanForPattern:(const uint8_t *)pattern
                     length:(size_t)length
                       mask:(const uint8_t *)mask
                    maxHits:(int)maxHits {
    [self locateRoblox];
    if (!_info.robloxBase || _info.robloxSize == 0) return 0;
    
    uintptr_t start = _info.robloxBase;
    uintptr_t end = _info.robloxBase + _info.robloxSize;
    int hits = 0;
    
    for (uintptr_t addr = start; addr < end - length; addr++) {
        uint8_t *p = (uint8_t *)addr;
        
        BOOL match = YES;
        for (size_t i = 0; i < length; i++) {
            if (mask && mask[i] == 0) continue;
            if (p[i] != pattern[i]) { match = NO; break; }
        }
        
        if (match) {
            os_log_info(g_log, "pattern found @ 0x%lx", addr);
            hits++;
            if (maxHits > 0 && hits >= maxHits) return addr;
        }
    }
    
    return 0;
}

#pragma mark - البحث عن luau_execute

- (uintptr_t)findLuauExecuteInRoblox {
    if (_info.luauExecuteAddr) return _info.luauExecuteAddr;
    
    os_log_info(g_log, "searching for luau_execute pattern...");
    
    uintptr_t addr = [self scanForPattern:kLuauExecutePattern
                                   length:sizeof(kLuauExecutePattern)
                                     mask:NULL
                                  maxHits:1];
    
    if (addr) {
        _info.luauExecuteAddr = addr;
        os_log_info(g_log, "luau_execute @ 0x%lx (full pattern)", addr);
        return addr;
    }
    
    addr = [self scanForPattern:kLuauExecutePattern2
                         length:sizeof(kLuauExecutePattern2)
                           mask:NULL
                        maxHits:1];
    
    if (addr) {
        _info.luauExecuteAddr = addr;
        os_log_info(g_log, "luau_execute @ 0x%lx (short pattern)", addr);
        return addr;
    }
    
    os_log_error(g_log, "luau_execute not found");
    return 0;
}

#pragma mark - Discovery

- (BOOL)discoverAll {
    if (_info.found) return YES;
    
    [self locateRoblox];
    if (!_info.robloxBase) return NO;
    
    uintptr_t execAddr = [self findLuauExecuteInRoblox];
    if (execAddr) {
        os_log_info(g_log, "luau_execute @ 0x%lx", execAddr);
    } else {
        os_log_error(g_log, "luau_execute NOT found");
    }
    
    _info.found = YES;
    return YES;
}

- (LuaRuntimeInfo)info {
    return _info;
}

- (lua_State *)mainState {
    return (lua_State *)_info.luaStateAddr;
}

@end
