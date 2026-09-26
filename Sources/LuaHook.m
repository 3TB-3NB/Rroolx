// language: Objective-C, file: LuaHook.m, runtime: iOS 15+

#import "LuaHook.h"
#import "LuauRuntime.h"
#import <dlfcn.h>
#import <os/log.h>

static os_log_t g_log;

typedef int  (*lua_pcall_t)(lua_State *L, int nargs, int nresults, int errfunc);
typedef int  (*lua_getfield_t)(lua_State *L, int idx, const char *k);
typedef int  (*lua_getglobal_t)(lua_State *L, const char *name);
typedef double (*lua_tonumberx_t)(lua_State *L, int idx, int *isnum);
typedef int  (*lua_type_t)(lua_State *L, int idx);
typedef void (*lua_settop_t)(lua_State *L, int idx);

static lua_pcall_t      g_lua_pcall = NULL;
static lua_getfield_t   g_lua_getfield = NULL;
static lua_getglobal_t  g_lua_getglobal = NULL;
static lua_tonumberx_t  g_lua_tonumberx = NULL;
static lua_type_t       g_lua_type = NULL;
static lua_settop_t     g_lua_settop = NULL;

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
    if (!handle) {
        os_log_error(g_log, "dlopen failed");
        return NO;
    }
    
    g_lua_pcall     = (lua_pcall_t)    dlsym(handle, "lua_pcall");
    g_lua_getfield  = (lua_getfield_t) dlsym(handle, "lua_getfield");
    g_lua_getglobal = (lua_getglobal_t)dlsym(handle, "lua_getglobal");
    g_lua_tonumberx = (lua_tonumberx_t)dlsym(handle, "lua_tonumberx");
    g_lua_type      = (lua_type_t)     dlsym(handle, "lua_type");
    g_lua_settop    = (lua_settop_t)   dlsym(handle, "lua_settop");
    
    os_log_info(g_log, "lua_pcall:     %p", g_lua_pcall);
    os_log_info(g_log, "lua_getfield:  %p", g_lua_getfield);
    os_log_info(g_log, "lua_getglobal: %p", g_lua_getglobal);
    
    if (!g_lua_pcall) {
        os_log_error(g_log, "symbols stripped — pattern scanning needed");
        return NO;
    }
    
    self.hooksInstalled = YES;
    return YES;
}

- (void)removeHooks {
    g_lua_pcall = NULL;
    g_lua_getfield = NULL;
    g_lua_getglobal = NULL;
    g_lua_tonumberx = NULL;
    g_lua_type = NULL;
    g_lua_settop = NULL;
    self.hooksInstalled = NO;
}

- (lua_State *)mainState {
    return [[LuauRuntime shared] mainState];
}

- (BOOL)executeLua:(NSString *)script error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:@"LuaHook"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"execution not yet implemented"}];
    }
    return NO;
}

- (NSNumber *)currentPlaceId {
    return nil;
}

@end
