// language: Objective-C, file: Entry.m, runtime: iOS 15+, arm64/arm64e
// *Constructor يشتغل قبل main() — هنا نبدأ كل شي بدون ما نلمس main app*

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "Executor.h"
#import "Stealth.h"

__attribute__((constructor))
static void executor_init(void) {
    @autoreleasepool {
        // 1. شغّل طبقة التخفي أول شي
        [Stealth initializeStealth];
        
        // 2. انتظر لين Roblox يخلّص إقلاعه
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            // انتظر 3 ثواني — Roblox يحتاج وقت لتحميل الـ engine
            [NSThread sleepForTimeInterval:3.0];
            
            // 3. شغّل الـ executor
            [[Executor sharedInstance] start];
        });
    }
}
