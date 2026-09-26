// language: Objective-C, file: Executor.h, runtime: iOS 15+

#import <Foundation/Foundation.h>

@interface Executor : NSObject

+ (instancetype)sharedInstance;

+ (NSArray<NSNumber *> *)allowedPlaceIds;

- (void)start;
- (void)stop;
- (BOOL)executeScript:(NSString *)script error:(NSError **)error;
- (BOOL)executeFile:(NSString *)path error:(NSError **)error;

@end
