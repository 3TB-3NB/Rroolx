// language: Objective-C, file: LuaHook.m, runtime: iOS 15+
// *Hook في Luau VM + قراءة game.PlaceId*

#import "LuaHook.h"
#import "Stealth.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <os/log.h>

static os_log_t g_log;

// Function pointer types
typedef int   (*luaL_loadstring_t)(lua_State *L, const char *s);
typedef int   (*lua_pcall_t)(lua_State *L, int nargs, int nresults, int errfunc);
typedef int   (*lua_gettop_t)(lua_State *L);
typedef void  (*lua_getglobal_t)(lua_State *L, const char *name);
typedef int   (*lua_type_t)(lua_State *L, int idx);
typedef double (*lua_tonumberx_t)(lua_State *L, int idx, int *isnum);
typedef const char* (*lua_tolstring_t)(lua_State *L, int idx, size_t *len);
typedef void  (*lua_getfield_t)(lua_State *L, int idx, const char *k);
typedef void  (*lua_settop_t)(lua_State *L, int idx);
typedef int   (*lua_isnil_t)(lua_State *L, int idx);

// المقابس
static luaL_loadstring_t g_luaL_loadstring = NULL;
static lua_pcall_t       g_lua_pcall = NULL;
static lua_gettop_t      g_lua_gettop = NULL;
static lua_getglobal_t   g_lua_getglobal = NULL;
static lua_type_t        g_lua_type = NULL;
static lua_tonumberx_t   g_lua_tonumberx = NULL;
static lua_tolstring_t   g_lua_tolstring = NULL;
static lua_getfield_t    g_lua_getfield = NULL;
static lua_settop_t      g_lua_settop = NULL;

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
    
    // لاقط Roblox main image
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
    
    void *handle = dlopen(robloxPath, RTLD_NOW | RTLD_NOLOAD);
    if (!handle) {
        os_log_error(g_log, "dlopen failed: %s", dlerror());
        return NO;
    }
    
    // حاول تلاقي الـ symbols
    g_luaL_loadstring = (luaL_loadstring_t)dlsym(handle, "luaL_loadstring");
    g_lua_pcall       = (lua_pcall_t)dlsym(handle, "lua_pcall");
    g_lua_gettop      = (lua_gettop_t)dlsym(handle, "lua_gettop");
    g_lua_getglobal   = (lua_getglobal_t)dlsym(handle, "lua_getglobal");
    g_lua_type        = (lua_type_t)dlsym(handle, "lua_type");
    g_lua_tonumberx   = (lua_tonumberx_t)dlsym(handle, "lua_tonumberx");
    g_lua_tolstring   = (lua_tolstring_t)dlsym(handle, "lua_tolstring");
    g_lua_getfield    = (lua_getfield_t)dlsym(handle, "lua_getfield");
    g_lua_settop      = (lua_settop_t)dlsym(handle, "lua_settop");
    
    if (!g_luaL_loadstring || !g_lua_pcall) {
        os_log_error(g_log, "Luau symbols not found — Roblox stripped");
        return NO;
    }
    
    os_log_info(g_log, "Luau symbols resolved");
    self.hooksInstalled = YES;
    return YES;
}

- (void)removeHooks {
    g_luaL_loadstring = NULL;
    g_lua_pcall = NULL;
    g_lua_gettop = NULL;
    g_lua_getglobal = NULL;
    g_lua_type = NULL;
    g_lua_tonumberx = NULL;
    g_lua_tolstring = NULL;
    g_lua_getfield = NULL;
    g_lua_settop = NULL;
    g_mainState = NULL;
    self.hooksInstalled = NO;
}

- (lua_State *)mainState {
    return g_mainState;
}

#pragma mark - PlaceId Reading

- (NSNumber *)currentPlaceId {
    if (!g_mainState || !g_lua_getglobal || !g_lua_getfield) {
        return nil;
    }
    
    // game = getglobal("game")
    g_lua_getglobal(g_mainState, "game");
    if (g_lua_type && g_lua_type(g_mainState, -1) == 0) {  // LUA_TNIL = 0
        g_lua_settop(g_mainState, -2);
        return nil;
    }
    
    // PlaceId = game.PlaceId
    g_lua_getfield(g_mainState, -1, "PlaceId");
    
    NSNumber *placeId = nil;
    if (g_lua_tonumberx) {
        int isnum = 0;
        double val = g_lua_tonumberx(g_mainState, -1, &isnum);
        if (isnum) {
            placeId = @((long long)val);
        }
    }
    
    // نظّف الـ stack
    if (g_lua_settop) {
        g_lua_settop(g_mainState, -3);
    }
    
    return placeId;
}

- (NSString *)currentGameName {
    if (!g_mainState || !g_lua_getglobal || !g_lua_getfield) {
        return nil;
    }
    
    g_lua_getglobal(g_mainState, "game");
    g_lua_getfield(g_mainState, -1, "Name");
    
    NSString *name = nil;
    if (g_lua_tolstring) {
        const char *cstr = g_lua_tolstring(g_mainState, -1, NULL);
        if (cstr) {
            name = [NSString stringWithUTF8String:cstr];
        }
    }
    
    if (g_lua_settop) {
        g_lua_settop(g_mainState, -3);
    }
    
    return name;
}

#pragma mark - Execute

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
    
    int loadResult = g_luaL_loadstring(g_mainState, code);
    if (loadResult != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"load failed"}];
        }
        return NO;
    }
    
    int pcallResult = g_lua_pcall(g_mainState, 0, 0, 0);
    if (pcallResult != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"execution failed"}];
        }
        return NO;
    }
    
    return YES;
}

@end
