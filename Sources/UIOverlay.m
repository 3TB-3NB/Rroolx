// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+
// *نسخة نهائية — panel مركزي + بدون معلومات تشخيصية*

#import "UIOverlay.h"
#import "Executor.h"
#import "LuaHook.h"
#import <os/log.h>

static os_log_t g_log;
static const NSTimeInterval kCheckInterval = 2.0;

@interface PassThroughView : UIView
@end

@implementation PassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (sub.hidden || sub.alpha == 0 || !sub.userInteractionEnabled) continue;
        CGPoint subPoint = [sub convertPoint:point fromView:self];
        if ([sub pointInside:subPoint withEvent:event]) return YES;
    }
    return NO;
}
@end

@interface UIOverlay () <UITextViewDelegate>

@property (nonatomic, strong) PassThroughView *container;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, assign) BOOL uiBuilt;

@end

@implementation UIOverlay

#pragma mark - Start / Stop

- (void)startSilentMode {
    g_log = os_log_create("com.alpha.executor", "ui");
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uiBuilt = NO;
        [self startMonitoring];
        os_log_info(g_log, "silent mode started");
    });
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.monitorTimer invalidate];
        self.monitorTimer = nil;
        [self.container removeFromSuperview];
        self.container = nil;
    });
}

#pragma mark - Monitoring

- (void)startMonitoring {
    [self attemptBuild];
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:kCheckInterval
                                                         target:self
                                                       selector:@selector(attemptBuild)
                                                       userInfo:nil
                                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.monitorTimer forMode:NSRunLoopCommonModes];
}

- (void)attemptBuild {
    if (self.uiBuilt && self.container && self.container.superview) {
        // إذا تغيّر حجم الشاشة (دوران/دخول لعبة)، أعد ترتيب الـ UI
        CGSize hostSize = self.container.superview.bounds.size;
        if (!CGSizeEqualToSize(self.container.bounds.size, hostSize)) {
            [self relayoutForSize:hostSize];
        }
        return;
    }
    
    UIWindow *host = [self findRobloxKeyWindow];
    if (!host) return;
    
    [self buildUI:host];
}

- (UIWindow *)findRobloxKeyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow && !w.hidden) {
                if ([w viewWithTag:99999]) continue;
                return w;
            }
        }
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden && ![w viewWithTag:99999]) return w;
    }
    return nil;
}

#pragma mark - Build UI

- (void)buildUI:(UIWindow *)host {
    UIView *rootView = host.rootViewController.view;
    if (!rootView) return;
    
    PassThroughView *container = [[PassThroughView alloc] initWithFrame:rootView.bounds];
    container.backgroundColor = [UIColor clearColor];
    container.tag = 99999;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = YES;
    
    [rootView addSubview:container];
    self.container = container;
    
    [self buildFloatButton:container];
    [self buildPanel:container];
    
    self.floatButton.hidden = NO;
    self.panel.hidden = YES;
    
    self.uiBuilt = YES;
    os_log_info(g_log, "UI built successfully");
}

- (void)buildFloatButton:(UIView *)container {
    CGFloat size = 55;
    CGFloat margin = 20;
    CGSize s = container.bounds.size;
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(s.width - size - margin, s.height / 2 - size / 2, size, size);
    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:0.95];
    btn.layer.cornerRadius = size / 2;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.6;
    btn.layer.shadowRadius = 5;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.borderWidth = 2;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [btn setTitle:@"a" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    
    [container addSubview:btn];
    self.floatButton = btn;
}

- (void)buildPanel:(UIView *)container {
    // حجم أصغر نسبياً: 80% عرض × 55% ارتفاع
    CGSize s = container.bounds.size;
    CGFloat panelW = s.width * 0.8;
    CGFloat panelH = s.height * 0.55;
    CGFloat panelX = (s.width - panelW) / 2;
    CGFloat panelY = (s.height - panelH) / 2;
    
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.97];
    panel.layer.cornerRadius = 16;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.8;
    panel.layer.shadowRadius = 12;
    panel.userInteractionEnabled = YES;
    panel.hidden = YES;
    // ⚠️ خلّي الـ panel يتحرك مع resize
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panelW - 60, 30)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [panel addSubview:title];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, 8, 36, 36);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setTitle:@"x" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:28];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    // محرر السكربت — يستخدم كل المساحة
    CGFloat editorTop = 52;
    CGFloat editorBottom = 100;  // مساحة للـ status + زر Execute
    UITextView *editor = [[UITextView alloc] initWithFrame:
                          CGRectMake(16, editorTop, panelW - 32, panelH - editorTop - editorBottom)];
    editor.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    editor.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
    editor.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
    editor.layer.cornerRadius = 8;
    editor.text = @"-- script here\nprint(\"hello\")";
    editor.delegate = self;
    editor.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    editor.spellCheckingType = UITextSpellCheckingTypeNo;
    editor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [panel addSubview:editor];
    self.scriptEditor = editor;
    
    UILabel *status = [[UILabel alloc] initWithFrame:
                       CGRectMake(16, panelH - 80, panelW - 32, 20)];
    status.text = @"Ready";
    status.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    status.font = [UIFont systemFontOfSize:12];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [panel addSubview:status];
    self.statusLabel = status;
    
    UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    execBtn.frame = CGRectMake(16, panelH - 52, panelW - 32, 40);
    execBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1.0];
    execBtn.layer.cornerRadius = 8;
    execBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [execBtn setTitle:@"Execute" forState:UIControlStateNormal];
    [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    execBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [execBtn addTarget:self action:@selector(executeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:execBtn];
    
    [container addSubview:panel];
    self.panel = panel;
}

#pragma mark - Relayout

- (void)relayoutForSize:(CGSize)newSize {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.container) return;
        self.container.frame = CGRectMake(0, 0, newSize.width, newSize.height);
        
        // زر — خلّه في مكانه النسبي
        if (self.floatButton) {
            CGFloat size = self.floatButton.bounds.size.width;
            CGFloat margin = 20;
            CGRect f = self.floatButton.frame;
            // إذا كان الزر برا الشاشة، رجّعه
            if (f.origin.x + f.size.width > newSize.width) {
                f.origin.x = newSize.width - size - margin;
            }
            if (f.origin.y + f.size.height > newSize.height) {
                f.origin.y = newSize.height / 2 - size / 2;
            }
            if (f.origin.x < 0) f.origin.x = margin;
            if (f.origin.y < 0) f.origin.y = margin;
            self.floatButton.frame = f;
        }
        
        // panel — أعد توسيطه وأعد حساب الحجم
        if (self.panel) {
            CGFloat panelW = newSize.width * 0.8;
            CGFloat panelH = newSize.height * 0.55;
            CGFloat panelX = (newSize.width - panelW) / 2;
            CGFloat panelY = (newSize.height - panelH) / 2;
            self.panel.frame = CGRectMake(panelX, panelY, panelW, panelH);
            
            // حدّث العناصر الداخلية
            UIView *p = self.panel;
            for (UIView *sub in p.subviews) {
                if ([sub isKindOfClass:[UITextView class]]) {
                    sub.frame = CGRectMake(16, 52, panelW - 32, panelH - 52 - 100);
                } else if ([sub isKindOfClass:[UILabel class]]) {
                    UILabel *lbl = (UILabel *)sub;
                    if (lbl == self.statusLabel) {
                        lbl.frame = CGRectMake(16, panelH - 80, panelW - 32, 20);
                    } else {
                        // العنوان
                        sub.frame = CGRectMake(16, 12, panelW - 60, 30);
                    }
                } else if ([sub isKindOfClass:[UIButton class]]) {
                    UIButton *b = (UIButton *)sub;
                    NSString *t = [b titleForState:UIControlStateNormal];
                    if ([t isEqualToString:@"x"]) {
                        b.frame = CGRectMake(panelW - 44, 8, 36, 36);
                    } else {
                        b.frame = CGRectMake(16, panelH - 52, panelW - 32, 40);
                    }
                }
            }
        }
    });
}

#pragma mark - Actions

- (void)togglePanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.panel.hidden = !self.panel.hidden;
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *host = self.container;
    if (!host) return;
    CGPoint translation = [pan translationInView:host];
    CGPoint newCenter = CGPointMake(self.floatButton.center.x + translation.x,
                                    self.floatButton.center.y + translation.y);
    CGFloat halfW = self.floatButton.bounds.size.width / 2;
    CGFloat halfH = self.floatButton.bounds.size.height / 2;
    newCenter.x = MAX(halfW, MIN(host.bounds.size.width - halfW, newCenter.x));
    newCenter.y = MAX(halfH, MIN(host.bounds.size.height - halfH, newCenter.y));
    self.floatButton.center = newCenter;
    [pan setTranslation:CGPointZero inView:host];
}

- (void)executeTapped {
    NSString *script = self.scriptEditor.text;
    self.statusLabel.text = @"Executing...";
    self.statusLabel.textColor = [UIColor yellowColor];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [[Executor sharedInstance] executeScript:script error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                self.statusLabel.text = @"OK Executed";
                self.statusLabel.textColor = [UIColor greenColor];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"ERR %@",
                                         error.localizedDescription];
                self.statusLabel.textColor = [UIColor redColor];
            }
        });
    });
}

@end
