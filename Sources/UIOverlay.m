// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+

#import "UIOverlay.h"
#import "Executor.h"
#import "LuaHook.h"
#import <os/log.h>

static os_log_t g_log;
static const NSTimeInterval kCheckInterval = 1.5;

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
        CGPoint p = [sub convertPoint:point fromView:self];
        if ([sub pointInside:p withEvent:event]) return YES;
    }
    return NO;
}
@end

@interface UIOverlay () <UITextViewDelegate>

@property (nonatomic, strong) PassThroughView *container;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UITextView *consoleView;   // ⭐ console
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *diagLabel;
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, assign) BOOL uiBuilt;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLines;

@end

@implementation UIOverlay

#pragma mark - Start/Stop

- (void)startSilentMode {
    g_log = os_log_create("com.alpha.executor", "ui");
    self.consoleLines = [NSMutableArray array];
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

#pragma mark - Diagnostics

- (void)setDiagnostics:(NSString *)diag {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.diagLabel) self.diagLabel.text = diag;
    });
}

#pragma mark - Console

- (void)appendConsoleLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!line) return;
        [self.consoleLines addObject:line];
        // احتفظ بآخر 50 سطر
        if (self.consoleLines.count > 50) {
            [self.consoleLines removeObjectAtIndex:0];
        }
        NSString *all = [self.consoleLines componentsJoinedByString:@"\n"];
        if (self.consoleView) {
            self.consoleView.text = all;
            // scroll للأخير
            NSRange r = NSMakeRange(self.consoleView.text.length - 1, 1);
            [self.consoleView scrollRangeToVisible:r];
        }
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
    if (self.uiBuilt && self.container && self.container.superview) return;
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
    os_log_info(g_log, "UI built");
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
    btn.layer.borderWidth = 2;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
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
    CGSize s = container.bounds.size;
    CGFloat panelW = s.width * 0.9;
    CGFloat panelH = s.height * 0.75;
    
    UIView *panel = [[UIView alloc] initWithFrame:
                     CGRectMake((s.width - panelW) / 2,
                                (s.height - panelH) / 2,
                                panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.98];
    panel.layer.cornerRadius = 14;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.8;
    panel.layer.shadowRadius = 12;
    panel.userInteractionEnabled = YES;
    panel.hidden = YES;
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight |
                             UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                             UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, panelW - 60, 26)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [panel addSubview:title];
    
    // Close
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, 6, 36, 36);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:28];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    // Diagnostics line
    UILabel *diag = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, panelW - 32, 30)];
    diag.text = @"initializing...";
    diag.textColor = [UIColor yellowColor];
    diag.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    diag.numberOfLines = 0;
    diag.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [panel addSubview:diag];
    self.diagLabel = diag;
    
    // ⭐ Script editor (أعلى)
    CGFloat editorY = 70;
    CGFloat editorH = (panelH - editorY - 200) / 2;
    UITextView *editor = [[UITextView alloc] initWithFrame:
                          CGRectMake(16, editorY, panelW - 32, editorH)];
    editor.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    editor.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
    editor.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    editor.layer.cornerRadius = 8;
    editor.text = @"print(\"hellow world\")";
    editor.delegate = self;
    editor.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    editor.spellCheckingType = UITextSpellCheckingTypeNo;
    editor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [panel addSubview:editor];
    self.scriptEditor = editor;
    
    // ⭐ Console (أسفل المحرر)
    CGFloat consoleY = editorY + editorH + 8;
    CGFloat consoleH = editorH;
    UITextView *console = [[UITextView alloc] initWithFrame:
                           CGRectMake(16, consoleY, panelW - 32, consoleH)];
    console.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    console.textColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    console.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    console.layer.cornerRadius = 8;
    console.text = @"> Console ready";
    console.editable = NO;
    console.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [panel addSubview:console];
    self.consoleView = console;
    
    // Status
    UILabel *status = [[UILabel alloc] initWithFrame:
                       CGRectMake(16, panelH - 60, panelW - 32, 20)];
    status.text = @"Ready";
    status.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    status.font = [UIFont systemFontOfSize:11];
    status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [panel addSubview:status];
    self.statusLabel = status;
    
    // Execute button
    UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    execBtn.frame = CGRectMake(16, panelH - 44, panelW - 32, 38);
    execBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1.0];
    execBtn.layer.cornerRadius = 8;
    execBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [execBtn setTitle:@"Execute" forState:UIControlStateNormal];
    [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    execBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [execBtn addTarget:self action:@selector(executeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:execBtn];
    
    [container addSubview:panel];
    self.panel = panel;
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
    CGPoint t = [pan translationInView:host];
    CGPoint c = CGPointMake(self.floatButton.center.x + t.x,
                            self.floatButton.center.y + t.y);
    CGFloat hw = self.floatButton.bounds.size.width / 2;
    CGFloat hh = self.floatButton.bounds.size.height / 2;
    c.x = MAX(hw, MIN(host.bounds.size.width - hw, c.x));
    c.y = MAX(hh, MIN(host.bounds.size.height - hh, c.y));
    self.floatButton.center = c;
    [pan setTranslation:CGPointZero inView:host];
}

- (void)executeTapped {
    NSString *script = self.scriptEditor.text;
    self.statusLabel.text = @"Executing...";
    self.statusLabel.textColor = [UIColor yellowColor];
    [self appendConsoleLine:@"> executing..."];
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [[Executor sharedInstance] executeScript:script error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                self.statusLabel.text = @"OK";
                self.statusLabel.textColor = [UIColor greenColor];
                [self appendConsoleLine:@"> execution completed"];
            } else {
                self.statusLabel.text = @"ERR";
                self.statusLabel.textColor = [UIColor redColor];
                [self appendConsoleLine:[NSString stringWithFormat:@"> ERR: %@",
                                          error.localizedDescription]];
            }
        });
    });
}

@end
