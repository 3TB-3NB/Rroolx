// language: Objective-C, file: Entry.m, runtime: iOS 15+, arm64/arm64e
// *Constructor — يشتغل عند تحميل dylib*

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Executor.h"
#import "Stealth.h"

__attribute__((constructor))
static void executor_init(void) {
    @autoreleasepool {
        [Stealth initializeStealth];
        
        // انتظر لين Roblox يخلّص إقلاع (8 ثواني)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSThread sleepForTimeInterval:8.0];
            [[Executor sharedInstance] start];
        });
    }
}
