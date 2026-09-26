// language: Objective-C, file: Executor.h, runtime: iOS 15+
// *الـ API الأساسي للـ Executor*

#import <Foundation/Foundation.h>

@interface Executor : NSObject

+ (instancetype)sharedInstance;

- (void)start;
- (void)stop;

// API لتنفيذ سكربت Lua
- (BOOL)executeScript:(NSString *)script
                error:(NSError **)error;

// API لتنفيذ ملف
- (BOOL)executeFile:(NSString *)path
              error:(NSError **)error;

@end
