// language: Objective-C, file: UIOverlay.h, runtime: iOS 15+

#import <UIKit/UIKit.h>

@interface UIOverlay : NSObject

- (void)startSilentMode;
- (void)stop;

- (void)setDiagnostics:(NSString *)diag;

// ⭐ Console output — تُستدعى من LuaHook عند كل print
- (void)appendConsoleLine:(NSString *)line;

@end
