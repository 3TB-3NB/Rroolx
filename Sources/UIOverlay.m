// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+
// *حقن مباشر في نافذة Roblox — بدون UIWindow منفصل*

#import "UIOverlay.h"
#import "Executor.h"
#import "LuaHook.h"
#import <os/log.h>

static os_log_t g_log;

static const NSTimeInterval kCheckInterval = 1.5;

@interface UIOverlay () <UITextViewDelegate>

@property (nonatomic, strong) UIView *container;      // الحاوية في نافذة Roblox
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UIButton *executeButton;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, assign) BOOL uiVisible;
@property (nonatomic, assign) BOOL uiBuilt;

@end

@implementation UIOverlay

#pragma mark - Silent Mode

- (void)startSilentMode {
    g_log = os_log_create("com.alpha.executor", "ui");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uiVisible = NO;
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
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:kCheckInterval
                                                         target:self
                                                       selector:@selector(checkGameState)
                                                       userInfo:nil
                                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.monitorTimer forMode:NSRunLoopCommonModes];
}

- (void)checkGameState {
    NSNumber *placeId = [[LuaHook sharedInstance] currentPlaceId];
    
    if (placeId) {
        BOOL allowed = [[Executor allowedPlaceIds] containsObject:placeId];
        
        if (allowed && !self.uiVisible) {
            os_log_info(g_log, "target game detected: %@", placeId);
            [self showUI];
        } else if (!allowed && self.uiVisible) {
            os_log_info(g_log, "left target game");
            [self hideUI];
        }
        return;
    }
    
    [self fallbackDetection];
}

- (void)fallbackDetection {
    // لو الـ Luau hook فشل، ما نعرض أي شي
    // (الـ UI detection السابق كان هش ويسبب مشاكل)
    return;
}

#pragma mark - Find Roblox's key window

- (UIWindow *)findRobloxKeyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow && !w.hidden) {
                // تجنب النافذة اللي حقنّاها سابقاً
                if (w.rootViewController &&
                    [w.rootViewController.view viewWithTag:99999]) {
                    continue;
                }
                return w;
            }
        }
    }
    // fallback: أول نافذة
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden) return w;
    }
    return nil;
}

#pragma mark - Build UI inside Roblox's window

- (void)buildUIIfNeeded:(UIView *)host {
    if (self.uiBuilt && self.container && self.container.superview == host) return;
    
    // إذا فيه حاوية قديمة في نافذة ثانية، انقلها
    [self.container removeFromSuperview];
    
    // حاوية شفافة — تملأ الشاشة بس ما تاكل اللمس
    UIView *container = [[UIView alloc] initWithFrame:host.bounds];
    container.backgroundColor = [UIColor clearColor];
    container.tag = 99999;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // ⚠️ مهم: نافذة الحاوية نفسها ما تستقبل لمس
    // فقط العناصر الفرعية تستقبل
    container.userInteractionEnabled = YES;
    
    // إضافة الحاوية
    [host addSubview:container];
    self.container = container;
    
    // ابنِ الزر والـ panel
    [self buildFloatButtonIn:container host:host];
    [self buildPanelIn:container host:host];
    
    // كل شي مخفي بالبداية
    self.floatButton.hidden = YES;
    self.panel.hidden = YES;
    
    self.uiBuilt = YES;
    os_log_info(g_log, "UI built inside Roblox window");
}

- (void)buildFloatButtonIn:(UIView *)container host:(UIView *)host {
    CGFloat size = 50;
    CGFloat margin = 20;
    CGFloat screenW = host.bounds.size.width;
    CGFloat screenH = host.bounds.size.height;
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(screenW - size - margin, screenH / 2 - size / 2, size, size);
    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:0.9];
    btn.layer.cornerRadius = size / 2;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.5;
    btn.layer.shadowRadius = 4;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    [btn setTitle:@"a" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self
                                            action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    
    [container addSubview:btn];
    self.floatButton = btn;
}

- (void)buildPanelIn:(UIView *)container host:(UIView *)host {
    CGFloat screenW = host.bounds.size.width;
    CGFloat screenH = host.bounds.size.height;
    
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
    panel.hidden = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panelW - 60, 30)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:title];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, 8, 36, 36);
    [closeBtn setTitle:@"x" forState:UIControlStateNormal];
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
    editor.text = @"-- script here";
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
    
    [container addSubview:panel];
    self.panel = panel;
}

#pragma mark - Show/Hide

- (void)showUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *host = [self findRobloxKeyWindow];
        if (!host) {
            os_log_error(g_log, "no host window found");
            return;
        }
        
        [self buildUIIfNeeded:host.rootViewController.view];
        
        self.uiVisible = YES;
        self.floatButton.hidden = NO;
        
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

#pragma mark - Actions

- (void)togglePanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        // تأكد إن الـ UI مبني قبل ما نعرضه
        if (!self.uiBuilt) {
            UIWindow *host = [self findRobloxKeyWindow];
            if (host) [self buildUIIfNeeded:host.rootViewController.view];
        }
        self.panel.hidden = !self.panel.hidden;
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *host = self.container;
    if (!host) return;
    
    CGPoint translation = [pan translationInView:host];
    CGPoint newCenter = CGPointMake(self.floatButton.center.x + translation.x,
                                    self.floatButton.center.y + translation.y);
    
    // خلّه داخل الحدود
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
