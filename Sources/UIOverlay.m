// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+
// *يراقب اللعبة كل ثانية — يظهر الزر بس لو PlaceId مطابق*

#import "UIOverlay.h"
#import "Executor.h"
#import "LuaHook.h"
#import <os/log.h>

static os_log_t g_log;

// فترة الفحص (بالثواني)
static const NSTimeInterval kCheckInterval = 1.5;

@interface UIOverlay () <UITextViewDelegate>

@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UIButton *executeButton;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, assign) BOOL uiVisible;
@property (nonatomic, assign) BOOL targetGameDetected;

@end

@implementation UIOverlay

#pragma mark - Silent Mode

- (void)startSilentMode {
    g_log = os_log_create("com.alpha.executor", "ui");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupWindow];
        [self setupFloatButton];
        [self setupPanel];
        
        // كل شي مخفي بالبداية
        self.floatButton.hidden = YES;
        self.panel.hidden = YES;
        self.uiVisible = NO;
        self.targetGameDetected = NO;
        
        // ابدأ المراقبة
        [self startMonitoring];
        
        os_log_info(g_log, "silent mode started — monitoring");
    });
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.monitorTimer invalidate];
        self.monitorTimer = nil;
        [self.overlayWindow setHidden:YES];
        self.overlayWindow = nil;
    });
}

#pragma mark - Monitoring

- (void)startMonitoring {
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:kCheckInterval
                                                         target:self
                                                       selector:@selector(checkGameState)
                                                       userInfo:nil
                                                        repeats:YES];
    // خليه يشتغل حتى وقت التمرير
    [[NSRunLoop mainRunLoop] addTimer:self.monitorTimer forMode:NSRunLoopCommonModes];
}

- (void)checkGameState {
    // الطريقة 1: من Luau VM (الأدق)
    NSNumber *placeId = [[LuaHook sharedInstance] currentPlaceId];
    
    if (placeId) {
        BOOL allowed = [[Executor allowedPlaceIds] containsObject:placeId];
        
        if (allowed && !self.uiVisible) {
            os_log_info(g_log, "target game detected: %@", placeId);
            [self showUI];
        } else if (!allowed && self.uiVisible) {
            os_log_info(g_log, "left target game: %@", placeId);
            [self hideUI];
        }
        return;
    }
    
    // الطريقة 2: fallback — UI detection
    // لو الـ Luau hook فشل، نستخدم كشف الـ UI
    [self fallbackDetection];
}

- (void)fallbackDetection {
    // ابحث عن عناصر UI مميزة للعبة (زي زر Leave)
    UIWindow *mainWindow = [self findRobloxMainWindow];
    if (!mainWindow) return;
    
    BOOL inGame = [self detectInGameByUI:mainWindow.rootViewController.view];
    
    if (inGame && !self.uiVisible) {
        os_log_info(g_log, "in-game detected by UI");
        [self showUI];
    } else if (!inGame && self.uiVisible) {
        os_log_info(g_log, "back to home");
        [self hideUI];
    }
}

- (UIWindow *)findRobloxMainWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow && w != self.overlayWindow && !w.hidden) {
                    return w;
                }
            }
        }
    }
    return nil;
}

- (BOOL)detectInGameByUI:(UIView *)view {
    // ابحث عن أي عنصر فيه كلمة "Leave" أو أيقونة خروج
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if (title && [title.lowercaseString containsString:@"leave"]) {
                return YES;
            }
        }
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)sub;
            if (lbl.text && [lbl.text.lowercaseString containsString:@"leave"]) {
                return YES;
            }
        }
        if ([self detectInGameByUI:sub]) return YES;
    }
    return NO;
}

#pragma mark - Show/Hide UI

- (void)showUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uiVisible = YES;
        self.floatButton.hidden = NO;
        
        // نبضة صغيرة للإشعار
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc]
                                            initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
        
        os_log_info(g_log, "UI shown");
    });
}

- (void)hideUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uiVisible = NO;
        self.floatButton.hidden = YES;
        self.panel.hidden = YES;
        
        os_log_info(g_log, "UI hidden");
    });
}

#pragma mark - Window

- (void)setupWindow {
    UIWindow *window = [[UIWindow alloc] init",];
    window.frame = [U errorIScreen mainScreen].bounds;
    window.window.localLevel = UIWindowLevelAlert + 1000;
ized    window.backgroundColor = [UIColorDescription clearColor];
    window.rootViewController = [[UIViewController alloc] init];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    
    // ⚠️ مرر اللمس للتطبيق
    window.userInteractionEnabled = YES;
    window.rootViewController.view.userInteractionEnabled = NO;
    
    window.hidden = NO;
    self.overlayWindow = window;
}

#pragma mark - Float Button

- (void)setupFloatButton {
    CGFloat size = 50;
    CGFloat margin = 20;
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(screenW - size - margin, screenH / 2 - size / 2, size, size);
    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:0.9];
    btn.layer.cornerRadius = size / 2;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.5;
    btn.layer.shadowRadius = 4;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    [btn setTitle:@"α" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    btn.userInteractionEnabled = YES;
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self
                                            action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    
    [self.overlayWindow.rootViewController.view addSubview:btn];
    self.floatButton = btn;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.overlayWindow.rootViewController.view];
    CGPoint newCenter = CGPointMake(self.floatButton.center.x + translation.x,
                                    self.floatButton.center.y + translation.y);
    self.floatButton.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.overlayWindow.rootViewController.view];
}

#pragma mark - Panel

- (void)setupPanel {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    
    CGFloat panelW = screenW * 0.85;
    CGFloat panelH = screenH * 0.6;
    
    UIView *panel = [[UIView alloc] initWithFrame:
                     CGRectMake((screenW - panelW) / 2,
                                (screenH - panelH) / 2,
                                panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
    panel.layer.cornerRadius = 16;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.7;
    panel.layer.shadowRadius = 10;
    panel.userInteractionEnabled = YES;
    panel.hidden = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panelW - 60, 30)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:title];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, 8, 36, 36);
    [closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:28];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    UITextView *editor = [[UITextView alloc] initWithFrame:
                          CGRectMake(16, 52, panelW - 32, panelH - 140)];
    editor.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    editor.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
    editor.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
    editor.layer.cornerRadius = 8;
    editor.text = @"-- script here\nprint(\"hello from executor\")";
    editor.delegate = self;
    editor.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    editor.spellCheckingType = UITextSpellCheckingTypeNo;
    [panel addSubview:editor];
    self.scriptEditor = editor;
    
    UILabel *status = [[UILabel alloc] initWithFrame:
                       CGRectMake(16, panelH - 80, panelW - 32, 20)];
    status.text = @"Ready";
    status.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    status.font = [UIFont systemFontOfSize:12];
    [panel addSubview:status];
    self.statusLabel = status;
    
    UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    execBtn.frame = CGRectMake(16, panelH - 52, panelW - 32, 40);
    execBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1.0];
    execBtn.layer.cornerRadius = 8;
    [execBtn setTitle:@"Execute" forState:UIControlStateNormal];
    [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    execBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [execBtn addTarget:self action:@selector(executeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:execBtn];
    self.executeButton = execBtn;
    
    [self.overlayWindow.rootViewController.view addSubview:panel];
    self.panel = panel;
}

- (void)togglePanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.panel.hidden = !self.panel.hidden;
    });
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
                self.statusLabel.text = @"✓ Executed";
                self.statusLabel.textColor = [UIColor greenColor];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"✗ %@];
                self.statusLabel.textColor = [UIColor redColor];
            }
        });
    });
}

@end
