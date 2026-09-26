// language: Objective-C, file: LuaHook.m, runtime: iOS 15+
// *Hook في Luau VM — يلاقي الدوال الأساسية ويثبّت hooks*
// *هام: Roblox يستخدم Luau (Lua 5.1 معدّل) — الأسماء غالباً: luaL_loadstring, lua_pcall*

#import "LuaHook.h"
#import "Stealth.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <os/log.h>

static os_log_t g_log;

// Function pointer types — حسب Luau
typedef int (*luaL_loadstring_t)(lua_State *L, const char *s);
typedef int (*lua_pcall_t)(lua_State *L, int nargs, int nresults, int errfunc);
typedef int (*lua_gettop_t)(lua_State *L);

// Elements محفوظة
static luaL_loadstring_t g_luaL_loadstring = NULL;
static lua_pcall_t       g_lua_pcall = NULL;
static lua_gettop_t      g_lua_gettop = NULL;

// الـ state الرئيسي (نلتقطه من hook)
static lua_State *g_mainState = NULL;

@interface LuaHook ()
@property (nonatomic, assign) BOOL hooksInstalled;
@end

@implementation LuaHook

+ (instancetype)sharedInstance {
    static LuaHook *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LuaHook alloc] init];
        g_log = os_log_create("com.alpha.executor", "luahook");
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hooksInstalled = NO;
    }
    return self;
}

- (BOOL)installHooks {
    if (self.hooksInstalled) return YES;
    
    os_log_info(g_log, "scanning for Luau symbols...");
    
    // 1. لقّط Roblox main image
    const char *robloxPath = NULL;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "Roblox")) {
            robloxPath = name;
            break;
        }
    }
    
    if (!robloxPath) {
        os_log_error(g_log, "Roblox image not found");
        return NO;
    }
    
    os_log_info(g_log, "found Roblox: %s", robloxPath);
    
    // 2. افتح الـ handle
    void *handle = dlopen(robloxPath, RTLD_NOW | RTLD_NOLOAD);
    if (!handle) {
        os_log_error(g_log, "dlopen failed: %s", dlerror());
        return NO;
    }
    
    // 3. حاول تلاقي الـ symbols
    // ملاحظة: Roblox stripped → احتمال كبير ما نلاقيها بالاسم
    // الحل: نستخدم pattern scanning لاحقاً
    
    g_luaL_loadstring = (luaL_loadstring_t)dlsym(handle, "luaL_loadstring");
    g_lua_pcall       = (lua_pcall_t)dlsym(handle, "lua_pcall");
    g_lua_gettop      = (lua_gettop_t)dlsym(handle, "lua_gettop");
    
    if (!g_luaL_loadstring || !g_lua_pcall) {
        os_log_error(g_log, "Luau symbols not found by name — need pattern scanning");
        // TODO: pattern scanning — نضيفه في إصدار لاحق
        return NO;
    }
    
    os_log_info(g_log, "Luau symbols resolved");
    os_log_info(g_log, "  luaL_loadstring @ %p", g_luaL_loadstring);
    os_log_info(g_log, "  lua_pcall       @ %p", g_lua_pcall);
    
    self.hooksInstalled = YES;
    return YES;
}

- (void)removeHooks {
    g_luaL_loadstring = NULL;
    g_lua_pcall = NULL;
    g_lua_gettop = NULL;
    g_mainState = NULL;
    self.hooksInstalled = NO;
}

- (lua_State *)mainState {
    return g_mainState;
}

- (BOOL)executeLua:(NSString *)script error:(NSError **)error {
    if (!self.hooksInstalled) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"hooks not installed"}];
        }
        return NO;
    }
    
    if (!g_mainState) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"main lua_State not captured"}];
        }
        return NO;
    }
    
    const char *code = [script UTF8String];
    if (!code) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"script encoding failed"}];
        }
        return NO;
    }
    
    // 1. حمّل الـ script
    int loadResult = g_luaL_loadstring(g_mainState, code);
    if (loadResult != 0) {
        // خطأ في التحميل — اقرأ الرسالة
        const char *err = "unknown load error";
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithUTF8String:err]}];
        }
        return NO;
    }
    
    // 2. نفّذه
    int pcallResult = g_lua_pcall(g_mainState, 0, 0, 0);
    if (pcallResult != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"script execution failed"}];
        }
        return NO;
    }
    
    return YES;
}

@end
