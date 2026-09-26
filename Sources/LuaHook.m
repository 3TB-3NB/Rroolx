// language: Objective-C, file: LuaHook.m, runtime: iOS 15+

#import "LuaHook.h"
#import "LuauRuntime.h"
#import <dlfcn.h>
#import <os/log.h>

static os_log_t g_log;

static lua_State *g_luaState = NULL;

// Function pointers (من binary — ممكن تفشل لو stripped)
typedef int  (*lua_pcall_t)(lua_State *L, int nargs, int nresults, int errfunc);
typedef int  (*lua_getfield_t)(lua_State *L, int idx, const char *k);
typedef int  (*lua_getglobal_t)(lua_State *L, const char *name);
typedef double (*lua_tonumberx_t)(lua_State *L, int idx, int *isnum);
typedef int  (*lua_type_t)(lua_State *L, int idx);
typedef void (*lua_settop_t)(lua_State *L, int idx);
typedef int  (*luau_load_t)(lua_State *L, const char *chunkname,
                             const char *data, size_t size, int env);

static lua_pcall_t      g_lua_pcall = NULL;
static lua_getfield_t   g_lua_getfield = NULL;
static lua_getglobal_t  g_lua_getglobal = NULL;
static lua_tonumberx_t  g_lua_tonumberx = NULL;
static lua_type_t       g_lua_type = NULL;
static lua_settop_t     g_lua_settop = NULL;
static luau_load_t      g_luau_load = NULL;

@interface LuaHook ()
@property (nonatomic, assign) BOOL hooksInstalled;
@end

@implementation LuaHook

+ (instancetype)sharedInstance {
    static LuaHook *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[LuaHook alloc] init];
        g_log = os_log_create("com.alpha.executor", "luahook");
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) _hooksInstalled = NO;
    return self;
}

- (BOOL)installHooks {
    if (self.hooksInstalled) return YES;
    
    os_log_info(g_log, "installing hooks...");
    
    void *handle = dlopen(NULL, RTLD_NOW);
    if (!handle) return NO;
    
    g_lua_pcall     = (lua_pcall_t)    dlsym(handle, "lua_pcall");
    g_lua_getfield  = (lua_getfield_t) dlsym(handle, "lua_getfield");
    g_lua_getglobal = (lua_getglobal_t)dlsym(handle, "lua_getglobal");
    g_lua_tonumberx = (lua_tonumberx_t)dlsym(handle, "lua_tonumberx");
    g_lua_type      = (lua_type_t)     dlsym(handle, "lua_type");
    g_lua_settop    = (lua_settop_t)   dlsym(handle, "lua_settop");
    g_luau_load     = (luau_load_t)    dlsym(handle, "luau_load");
    
    os_log_info(g_log, "lua_pcall:   %p", g_lua_pcall);
    os_log_info(g_log, "luau_load:   %p", g_luau_load);
    os_log_info(g_log, "lua_getglobal:%p", g_lua_getglobal);
    
    self.hooksInstalled = YES;
    return YES;
}

- (void)removeHooks {
    g_lua_pcall = NULL;
    g_luau_load = NULL;
    self.hooksInstalled = NO;
}

- (lua_State *)mainState {
    return g_luaState;
}

#pragma mark - Execute

- (BOOL)executeLua:(NSString *)script error:(NSError **)error {
    // أول شي: تأكد من hooks
    if (!self.hooksInstalled) {
        [self installHooks];
    }
    
    // تحقق من lua_State
    if (!g_luaState) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaHook"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"lua_State not discovered — يحتاج hook على luau_execute"}];
        }
        return NO;
    }
    
    // تحقق من luau_load
    if (!g_luau_load) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaHook"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"luau_load symbol not found"}];
        }
        return NO;
    }
    
    const char *code = [script UTF8String];
    size_t len = strlen(code);
    
    // 1. حمّل السكربت
    int loadResult = g_luau_load(g_luaState, "=executor", code, len, 0);
    if (loadResult != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaHook"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"script load failed"}];
        }
        return NO;
    }
    
    // 2. نفّذه
    if (!g_lua_pcall) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaHook"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"lua_pcall not found"}];
        }
        return NO;
    }
    
    int pcallResult = g_lua_pcall(g_luaState, 0, 0, 0);
    if (pcallResult != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaHook"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"script execution failed"}];
        }
        return NO;
    }
    
    return YES;
}

- (NSNumber *)currentPlaceId {
    if (!g_luaState || !g_lua_getglobal || !g_lua_getfield) return nil;
    
    g_lua_getglobal(g_luaState, "game");
    if (g_lua_type && g_lua_type(g_luaState, -1) == LUA_TNIL) {
        if (g_lua_settop) g_lua_settop(g_luaState, -2);
        return nil;
    }
    
    g_lua_getfield(g_luaState, -1, "PlaceId");
    int isnum = 0;
    double val = g_lua_tonumberx ? g_lua_tonumberx(g_luaState, -1, &isnum) : 0;
    if (g_lua_settop) g_lua_settop(g_luaState, -3);
    
    if (!isnum) return nil;
    return @((long long)val);
}

@end
