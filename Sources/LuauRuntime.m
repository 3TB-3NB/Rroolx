// language: Objective-C, file: LuauRuntime.m, runtime: iOS 15+

#import "LuauRuntime.h"
#import <os/log.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>
#import <string.h>

static os_log_t g_log;

// ⭐ Pattern من Ghidra — luau_execute في RobloxLib
static const uint8_t kLuauExecutePattern[] = {
    0xff, 0x83, 0x07, 0xd1,   // sub  sp, sp, #0x1e0
    0xe9, 0x23, 0x17, 0x6d,   // stp  d9, d8, [sp, #0x170]
    0xfc, 0x6f, 0x18, 0xa9,   // stp  x28, x27, [sp, #0x180]
    0xfa, 0x67, 0x19, 0xa9,   // stp  x26, x25, [sp, #0x190]
    0xf8, 0x5f, 0x1a, 0xa9,   // stp  x24, x23, [sp, #0x1a0]
    0xf6, 0x57, 0x1b, 0xa9,   // stp  x22, x21, [sp, #0x1b0]
    0xf4, 0x4f, 0x1c, 0xa9,   // stp  x20, x19, [sp, #0x1c0]
    0xfd, 0x7b, 0x1d, 0xa9,   // stp  x29, x30, [sp, #0x1d0]
};

// Offset داخل RobloxLib binary (من Ghidra)
#define LUAU_EXECUTE_OFFSET   0x03aaf108

@interface LuauRuntime () {
    LuaRuntimeInfo _info;
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
    if (self) memset(&_info, 0, sizeof(_info));
    return self;
}

#pragma mark - Locate RobloxLib framework

- (void)locateRoblox {
    if (_info.robloxBase) return;
    
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        
        // ⭐ ابحث عن RobloxLib.framework (مش Roblox.app)
        if (strstr(name, "RobloxLib")) {
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
            
            os_log_info(g_log, "RobloxLib @ 0x%lx (size 0x%lx)",
                        _info.robloxBase, _info.robloxSize);
            return;
        }
    }
    os_log_error(g_log, "RobloxLib not found");
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

#pragma mark - Find luau_execute

- (uintptr_t)findLuauExecuteInRoblox {
    if (_info.luauExecuteAddr) return _info.luauExecuteAddr;
    
    os_log_info(g_log, "searching for luau_execute...");
    
    // ⭐ الطريقة 1: offset مباشر
    if (_info.robloxBase) {
        uintptr_t addr = _info.robloxBase + LUAU_EXECUTE_OFFSET;
        os_log_info(g_log, "trying direct offset: 0x%lx", addr);
        
        // تأكد أن العنوان قابل للقراءة
        uint32_t insn = *(uint32_t *)addr;
        if (insn == 0xD10783FF) {  // little-endian sub sp, sp, #0x1e0
            _info.luauExecuteAddr = addr;
            os_log_info(g_log, "✅ luau_execute @ 0x%lx (direct)", addr);
            return addr;
        }
    }
    
    // ⭐ الطريقة 2: pattern scanning
    uintptr_t addr = [self scanForPattern:kLuauExecutePattern
                                   length:sizeof(kLuauExecutePattern)
                                     mask:NULL
                                  maxHits:1];
    
    if (addr) {
        _info.luauExecuteAddr = addr;
        os_log_info(g_log, "✅ luau_execute @ 0x%lx (pattern)", addr);
        return addr;
    }
    
    os_log_error(g_log, "❌ luau_execute not found");
    return 0;
}

#pragma mark - Discovery

- (BOOL)discoverAll {
    if (_info.found) return YES;
    
    [self locateRoblox];
    if (!_info.robloxBase) return NO;
    
    [self findLuauExecuteInRoblox];
    
    _info.found = YES;
    return YES;
}

- (LuaRuntimeInfo)info { return _info; }
- (lua_State *)mainState { return (lua_State *)_info.luaStateAddr; }

@end
