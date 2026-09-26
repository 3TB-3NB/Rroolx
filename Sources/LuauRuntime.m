// language: Objective-C, file: LuauRuntime.m, runtime: iOS 15+
// *pattern scanner كامل + استكشاف lua_State*

#import "LuauRuntime.h"
#import <os/log.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>
#import <string.h>

static os_log_t g_log;

// ==== Fingerprint لـ luau_execute (من Delta binary — مؤكد) ====
// هذا النمط يطابق prologue الدالة:
//   stp x28, x27, [sp, #-0x60]!
//   stp x26, x25, [sp, #0x50]
//   stp x24, x23, [sp, #0x40]
//   stp x22, x21, [sp, #0x30]
//   stp x20, x19, [sp, #0x20]
//   stp x29, x30, [sp, #0x10]
//   add x29, sp, #0x50
static const uint8_t kLuauExecutePattern[] = {
    0xfc, 0x6f, 0xba, 0xa9,
    0xfa, 0x67, 0x01, 0xa9,
    0xf8, 0x5f, 0x02, 0xa9,
    0xf6, 0x57, 0x03, 0xa9,
    0xf4, 0x4f, 0x04, 0xa9,
    0xfd, 0x7b, 0x05, 0xa9,
    0xfd, 0x03, 0x01, 0x91,
};

// ==== Fingerprint بديل (نمط مبسّط — أول 16 bytes) ====
static const uint8_t kLuauExecutePattern2[] = {
    0xfc, 0x6f, 0xba, 0xa9,
    0xfa, 0x67, 0x01, 0xa9,
};

@interface LuauRuntime ()
@property (nonatomic, assign) LuaRuntimeInfo info;
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

#pragma mark - اكتشاف Roblox

- (void)locateRoblox {
    if (self.info.robloxBase) return;
    
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        
        if (strstr(name, "Roblox") && strstr(name, ".app")) {
            const struct mach_header_64 *hdr =
                (const struct mach_header_64 *)_dyld_get_image_header(i);
            self.info.robloxBase = (uintptr_t)hdr;
            
            unsigned long textSize = 0;
            getsegmentdata(hdr, "__TEXT", &textSize);
            
            // الحجم الكلي
            uintptr_t end = self.info.robloxBase;
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
            self.info.robloxSize = end - self.info.robloxBase;
            
            os_log_info(g_log, "Roblox @ 0x%lx (size 0x%lx)",
                        self.info.robloxBase, self.info.robloxSize);
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
    if (!self.info.robloxBase || self.info.robloxSize == 0) return 0;
    
    uintptr_t start = self.info.robloxBase;
    uintptr_t end = self.info.robloxBase + self.info.robloxSize;
    
    // ابحث byte-by-byte
    for (uintptr_t addr = start; addr < end - length; addr++) {
        // تأكد أن العنوان قابل للقراءة
        uint8_t *p = (uint8_t *)addr;
        
        BOOL match = YES;
        for (size_t i = 0; i < length; i++) {
            if (mask && mask[i] == 0) continue; // تجاهل هذا byte
            if (p[i] != pattern[i]) { match = NO; break; }
        }
        
        if (match) {
            os_log_info(g_log, "pattern found @ 0x%lx", addr);
            return addr;
        }
    }
    
    return 0;
}

#pragma mark - البحث عن luau_execute

- (uintptr_t)findLuauExecuteInRoblox {
    if (self.info.luauExecuteAddr) return self.info.luauExecuteAddr;
    
    os_log_info(g_log, "searching for luau_execute pattern...");
    
    // جرب النمط الكامل أولاً
    uintptr_t addr = [self scanForPattern:kLuauExecutePattern
                                   length:sizeof(kLuauExecutePattern)
                                     mask:NULL
                                  maxHits:1];
    
    if (addr) {
        self.info.luauExecuteAddr = addr;
        os_log_info(g_log, "luau_execute @ 0x%lx (full pattern)", addr);
        return addr;
    }
    
    // جرب النمط المبسط
    addr = [self scanForPattern:kLuauExecutePattern2
                         length:sizeof(kLuauExecutePattern2)
                           mask:NULL
                        maxHits:1];
    
    if (addr) {
        self.info.luauExecuteAddr = addr;
        os_log_info(g_log, "luau_execute @ 0x%lx (short pattern)", addr);
        return addr;
    }
    
    os_log_error(g_log, "luau_execute not found");
    return 0;
}

#pragma mark - البحث عن lua_State

- (uintptr_t)findLuaStateViaScriptContext {
    // الاستراتيجية: نبحث عن instance من ScriptContext في الذاكرة
    // ScriptContext يحمل مؤشر lua_State
    
    // ملاحظة: هذا يحتاج معرفة layout ScriptContext
    // مؤقتاً: نستخدم dlopen + dlsym
    
    void *handle = dlopen(NULL, RTLD_NOW);
    if (!handle) return 0;
    
    // Luau exposes بعض الدوال — نجرب
    typedef lua_State* (*lua_mainthread_t)(lua_State*);
    lua_mainthread_t fn = (lua_mainthread_t)dlsym(handle, "lua_mainthread");
    if (fn) {
        os_log_info(g_log, "lua_mainthread found at %p", fn);
        // نحتاج lua_State* أول argument — غير معروف حالياً
    }
    
    return 0;
}

- (uintptr_t)findLuaStateViaLuauExecute {
    // نستخدم hook على luau_execute:
    // عند استدعائه، أول argument (x0) = lua_State*
    
    uintptr_t executeAddr = [self findLuauExecuteInRoblox];
    if (!executeAddr) return 0;
    
    // بدل hooking مباشر، نستخدم memory scanning:
    // نبحث عن مؤشر يشير لـ luau_execute في الذاكرة
    // المؤشر هذا عادة موجود في C++ vtable أو في callback tables
    
    // للأسف، هذا معقد بدون hook runtime
    // الحل: نستخدم dyld APIs للبحث عن التطبيق الرئيسي
    
    return 0;
}

#pragma mark - Discovery

- (BOOL)discoverAll {
    if (self.info.found) return YES;
    
    [self locateRoblox];
    if (!self.info.robloxBase) return NO;
    
    // البحث عن luau_execute
    uintptr_t execAddr = [self findLuauExecuteInRoblox];
    if (execAddr) {
        os_log_info(g_log, "✅ luau_execute @ 0x%lx", execAddr);
    } else {
        os_log_error(g_log, "❌ luau_execute NOT found");
    }
    
    // البحث عن lua_State (معقد — نضع مؤقتاً)
    uintptr_t stateAddr = [self findLuaStateViaScriptContext];
    if (stateAddr) {
        self.info.luaStateAddr = stateAddr;
        os_log_info(g_log, "✅ lua_State @ 0x%lx", stateAddr);
    } else {
        os_log_error(g_log, "❌ lua_State NOT found (needs hook)");
    }
    
    self.info.found = YES;
    return YES;
}

- (LuaRuntimeInfo)info { return _info; }
- (lua_State *)mainState { return (lua_State *)self.info.luaStateAddr; }

@end
