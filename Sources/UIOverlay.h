// language: Objective-C, file: UIOverlay.h, runtime: iOS 15+
// *واجهة صامتة → تظهر بس في اللعبة المحددة*

#import <UIKit/UIKit.h>

@interface UIOverlay : NSObject

- (void)startSilentMode;   // يبدأ المراقبة (بدون UI مرئي)
- (void)stop;

@end
