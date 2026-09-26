// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+
// *واجهة بسيطة — زر عائم + panel مع نص الإدخال + زر تنفيذ*

#import "UIOverlay.h"
#import "Executor.h"
#import <os/log.h>

static os_log_t g_log;

@interface UIOverlay () <UITextViewDelegate>
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UIButton *executeButton;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation UIOverlay

- (void)show {
    g_log = os_log_create("com.alpha.executor", "ui");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupWindow];
        [self setupFloatButton];
        [self setupPanel];
        
        os_log_info(g_log, "overlay shown");
    });
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.overlayWindow setHidden:YES];
        self.overlayWindow = nil;
        self.floatButton = nil;
        self.panel = nil;
        self.scriptEditor = nil;
        self.executeButton = nil;
        self.statusLabel = nil;
    });
}

- (void)setupWindow {
    // نحاول نستخدم نفس الـ scene عشان يبان فوق Roblox
    UIWindow *window = [[UIWindow alloc] init];
    window.frame = [UIScreen mainScreen].bounds;
    window.windowLevel = UIWindowLevelAlert + 1000;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = [[UIViewController alloc] init];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    window.hidden = NO;
    
    self.overlayWindow = window;
}

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
    
    // اجعله قابل للسحب
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    
    [self.overlayWindow.rootViewController.view addSubview:btn];
    self.floatButton = btn;
}

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
    panel.hidden = YES;
    
    // Header
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, panelW - 60, 30)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:title];
    
    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, 8, 36, 36);
    [closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:28];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    // Script editor
    UITextView *editor = [[UITextView alloc] initWithFrame:
                          CGRectMake(16, 52, panelW - 32, panelH - 140)];
    editor.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    editor.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
    editor.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
    editor.layer.cornerRadius = 8;
    editor.text = @"-- اكتب السكربت هنا\nprint(\"hello from executor\")";
    editor.delegate = self;
    editor.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    editor.spellCheckingType = UITextSpellCheckingTypeNo;
    [panel addSubview:editor];
    self.scriptEditor = editor;
    
    // Status label
    UILabel *status = [[UILabel alloc] initWithFrame:
                       CGRectMake(16, panelH - 80, panelW - 32, 20)];
    status.text = @"Ready";
    status.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    status.font = [UIFont systemFontOfSize:12];
    [panel addSubview:status];
    self.statusLabel = status;
    
    // Execute button
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

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.overlayWindow.rootViewController.view];
    CGPoint newCenter = CGPointMake(self.floatButton.center.x + translation.x,
                                    self.floatButton.center.y + translation.y);
    self.floatButton.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.overlayWindow.rootViewController.view];
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
                self.statusLabel.text = [NSString stringWithFormat:@"✗ %@", error.localizedDescription];
                self.statusLabel.textColor = [UIColor redColor];
            }
        });
    });
}

@end
