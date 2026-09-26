// language: Objective-C, file: Executor.m, runtime: iOS 15+

#import "Executor.h"
#import "LuaHook.h"
#import "LuauRuntime.h"
#import "UIOverlay.h"
#import <os/log.h>

static os_log_t g_log;
static NSArray<NSNumber *> *kAllowedPlaceIds = nil;

@interface Executor ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) UIOverlay *overlay;
@end

@implementation Executor

+ (instancetype)sharedInstance {
    static Executor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[Executor alloc] init];
        g_log = os_log_create("com.alpha.executor", "main");
        kAllowedPlaceIds = @[ @(4924922222) ];
    });
    return instance;
}

+ (NSArray<NSNumber *> *)allowedPlaceIds { return kAllowedPlaceIds; }

- (instancetype)init {
    self = [super init];
    if (self) _isRunning = NO;
    return self;
}

- (void)start {
    if (self.isRunning) return;
    os_log_info(g_log, "executor starting...");
    
    BOOL discovered = [[LuauRuntime shared] discoverAll];
    LuaRuntimeInfo info = [[LuauRuntime shared] info];
    
    NSString *diag = [NSString stringWithFormat:
        @"Roblox: %lx\nluau_exec: %lx\nlua_State: %lx",
        info.robloxBase, info.luauExecuteAddr, info.luaStateAddr];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlay = [[UIOverlay alloc] init];
        [self.overlay startSilentMode];
        [self.overlay setDiagnostics:diag];
    });
    
    self.isRunning = YES;
}

- (void)stop {
    if (!self.isRunning) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.overlay stop];
        self.overlay = nil;
    });
    self.isRunning = NO;
}

- (BOOL)executeScript:(NSString *)script error:(NSError **)error {
    return [[LuaHook sharedInstance] executeLua:script error:error];
}

- (BOOL)executeFile:(NSString *)path error:(NSError **)error {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!s) return NO;
    return [self executeScript:s error:error];
}

@end
