// language: Objective-C, file: Executor.h, runtime: iOS 15+
// *الـ API الأساسي + PlaceId المسموح*

#import <Foundation/Foundation.h>

@interface Executor : NSObject

+ (instancetype)sharedInstance;

// 🔧 غيّر من هنا — PlaceId اللعبة اللي يشتغل فيها الـ dylib
// Brookhaven RP = 4924922222 (افتراضي)
// Adopt Me = 920587237
// Blox Fruits = 2753915549
// Pet Simulator X = 8737899170
// غيّرها لأي PlaceId تبيه
+ (NSArray<NSNumber *> *)allowedPlaceIds;

- (void)start;
- (void)stop;
- (BOOL)executeScript:(NSString *)script error:(NSError **)error;
- (BOOL)executeFile:(NSString *)path error:(NSError **)error;

@end
