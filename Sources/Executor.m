// language: Objective-C, file: Executor.m, runtime: iOS 15+
// *المنطق الأساسي — ينسّق بين الـ LuaHook والـ UI*

#import "Executor.h"
#import "LuaHook.h"
#import "UIOverlay.h"
#import <os/log.h>

static os_log_t g_log;

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
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isRunning = NO;
    }
    return self;
}

- (void)start {
    if (self.isRunning) return;
    
    os_log_info(g_log, "executor starting...");
    
    // 1. هوّك في Luau VM
    BOOL hooked = [[LuaHook sharedInstance] installHooks];
    if (!hooked) {
        os_log_error(g_log, "failed to hook Luau VM");
        // حتى لو فشل، نكمل — يمكن الـ VM يتحمّل لاحقاً
    }
    
    // 2. اعرض الواجهة
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlay = [[UIOverlay alloc] init];
        [self.overlay show];
    });
    
    self.isRunning = YES;
    os_log_info(g_log, "executor started");
}

- (void)stop {
    if (!self.isRunning) return;
    
    [[LuaHook sharedInstance] removeHooks];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.overlay hide];
        self.overlay = nil;
    });
    
    self.isRunning = NO;
    os_log_info(g_log, "executor stopped");
}

- (BOOL)executeScript:(NSString *)script error:(NSError **)error {
    if (!script || script.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"executor"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"empty script"}];
        }
        return NO;
    }
    
    os_log_info(g_log, "executing script (%lu chars)", (unsigned long)script.length);
    
    return [[LuaHook sharedInstance] executeLua:script error:error];
}

- (BOOL)executeFile:(NSString *)path error:(NSError **)error {
    NSString *script = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:error];
    if (!script) return NO;
    return [self executeScript:script error:error];
}

@end
