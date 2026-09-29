// KRB Discovery — يبحث عن كل شي مفيد في libgloop

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <os/log.h>

// ═══════════════════════════════════════════
// Logging helper
// ═══════════════════════════════════════════

static void klog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    
    // NSLog — يظهر في Roblox Developer Console (/console)
    NSLog(@"[KRB] %@", msg);
    
    // os_log — يظهر في Console.app
    os_log_t log = os_log_create("com.krb.discovery", "main");
    os_log_info(log, "%{public}@", msg);
}

// ═══════════════════════════════════════════
// Forward declarations
// ═══════════════════════════════════════════

static void scan_subviews_helper(UIView *v, int depth, NSString *indent);

// ═══════════════════════════════════════════
// البحث عن libgloop
// ═══════════════════════════════════════════

static void *find_libgloop(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "libgloop")) {
            klog(@"Found libgloop: %s", name);
            const struct mach_header_64 *hdr =
                (const struct mach_header_64 *)_dyld_get_image_header(i);
            klog(@"libgloop base: %p", hdr);
            klog(@"libgloop slide: 0x%lx",
                 (uintptr_t)_dyld_get_image_vmaddr_slide(i));
            return dlopen(name, RTLD_NOW | RTLD_NOLOAD);
        }
    }
    klog(@"libgloop NOT FOUND");
    return NULL;
}

// ═══════════════════════════════════════════
// 1. فحص dlsym
// ═══════════════════════════════════════════

static void scan_dlsym(void *handle) {
    if (!handle) return;
    
    klog(@"═══ Scanning dlsym ═══");
    
    const char *symbols[] = {
        // Luau
        "luau_compile", "luau_load", "luau_loadbuffer",
        "luau_bytecode", "luau_parse", "luau_compile_source",
        "luau_compile_string", "luau_compile_buffer",
        "luau_run", "luau_execute", "luau_pcall", "luau_call",
        
        // Lua API
        "lua_pcall", "lua_call", "lua_load", "lua_loadbuffer",
        "luaL_loadbuffer", "luaL_loadstring", "luaL_loadfile",
        "lua_getglobal", "lua_setglobal", "lua_getfield", "lua_setfield",
        "lua_settop", "lua_gettop", "lua_tonumber", "lua_tolstring",
        "lua_type", "lua_newstate", "lua_close", "lua_pushcclosure",
        "lua_register",
        
        // Delta
        "delta_execute", "delta_run", "delta_script", "delta_load",
        "delta_compile", "DeltaExecute", "DeltaRun", "DeltaScript",
        "DeltaLoad", "DeltaCompile", "run_script", "runScript",
        "execute_script", "executeScript", "exec", "run", "execute",
        "loadstring", "loadbuffer",
        
        // generic
        "init", "main", "entry", "start",
        NULL
    };
    
    for (int i = 0; symbols[i] != NULL; i++) {
        void *sym = dlsym(handle, symbols[i]);
        if (sym) {
            klog(@"FOUND: %s @ %p", symbols[i], sym);
        }
    }
    
    klog(@"═══ End dlsym scan ═══");
}

// ═══════════════════════════════════════════
// 2. فحص Objective-C classes
// ═══════════════════════════════════════════

static void scan_objc_classes(void) {
    klog(@"═══ Scanning ObjC classes ═══");
    
    int count = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    objc_getClassList(classes, count);
    
    const char *keywords[] = {
        "Delta", "delta", "DELTA",
        "Gloop", "gloop", "GLOOP",
        "Executor", "executor",
        "Script", "script",
        "Lua", "lua", "Luau", "luau",
        "KRB", "krb",
        "Console", "console",
        NULL
    };
    
    for (int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        
        for (int k = 0; keywords[k] != NULL; k++) {
            if (strstr(name, keywords[k])) {
                klog(@"Class: %s", name);
                break;
            }
        }
    }
    
    free(classes);
    klog(@"═══ End ObjC classes scan ═══");
}

// ═══════════════════════════════════════════
// 3. فحص UI views
// ═══════════════════════════════════════════

static void scan_subviews_helper(UIView *v, int depth, NSString *indent) {
    if (depth > 3) return;
    if (!v) return;
    
    NSString *next = [indent stringByAppendingString:@"  "];
    for (UIView *sub in v.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Button"] ||
            [cls containsString:@"Text"] ||
            [cls containsString:@"Label"] ||
            [cls containsString:@"View"] ||
            [cls containsString:@"Window"] ||
            [cls containsString:@"Menu"] ||
            [cls containsString:@"Panel"]) {
            klog(@"%@%@ frame=%@", indent, cls, NSStringFromCGRect(sub.frame));
        }
        scan_subviews_helper(sub, depth + 1, next);
    }
}

static void scan_ui_views(void) {
    klog(@"═══ Scanning UI views ═══");
    
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            klog(@"Window: %@ class=%@ level=%f",
                 w, NSStringFromClass([w class]), w.windowLevel);
            scan_subviews_helper(w.rootViewController.view, 0, @"  ");
        }
    }
    
    klog(@"═══ End UI views scan ═══");
}

// ═══════════════════════════════════════════
// 4. Entry
// ═══════════════════════════════════════════

__attribute__((constructor))
static void krb_init(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSThread sleepForTimeInterval:10.0];
            
            klog(@"═══════════════════════════════════════");
            klog(@"       KRB DISCOVERY");
            klog(@"═══════════════════════════════════════");
            
            void *handle = find_libgloop();
            scan_dlsym(handle);
            scan_objc_classes();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                scan_ui_views();
            });
            
            klog(@"═══════════════════════════════════════");
            klog(@"       END DISCOVERY");
            klog(@"═══════════════════════════════════════");
        });
    }
}
