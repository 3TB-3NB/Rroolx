// language: Objective-C, file: Stealth.h, runtime: iOS 15+
// *طبقة التخفي — تخفي الـ dylib من الفحوصات الأساسية*

#import <Foundation/Foundation.h>

@interface Stealth : NSObject

+ (void)initializeStealth;

// تخفي الـ dylib من قائمة الـ loaded images
+ (void)hideFromDyldList;

// تنظيف متغيرات البيئة المشبوهة
+ (void)cleanEnvironment;

// fake signature info
+ (void)spoofSignature;

@end
