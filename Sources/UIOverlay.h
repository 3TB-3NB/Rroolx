// language: Objective-C, file: UIOverlay.h, runtime: iOS 15+

#ifndef UIOverlay_h
#define UIOverlay_h

#import <UIKit/UIKit.h>

@interface UIOverlay : NSObject

- (void)startSilentMode;
- (void)stop;
- (void)setDiagnostics:(NSString *)diag;
- (void)appendConsoleLine:(NSString *)line;

@end

#endif
