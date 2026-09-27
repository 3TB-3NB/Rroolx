// language: Objective-C, file: UIOverlay.m, runtime: iOS 15+

#import "UIOverlay.h"
#import "Executor.h"
#import "LuaHook.h"
#import <os/log.h>

static os_log_t g_log;
static const NSTimeInterval kCheckInterval = 1.5;

#pragma mark - PassThrough View

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

#pragma mark - UIOverlay

@interface UIOverlay () <UITextViewDelegate>

@property (nonatomic, strong) PassThroughView *container;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIView *panel;

@property (nonatomic, strong) UITextView *scriptEditor;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *diagLabel;

@property (nonatomic, strong) NSLayoutConstraint *panelBottomConstraint;
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, assign) BOOL uiBuilt;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLines;

@end

@implementation UIOverlay

#pragma mark - Start / Stop

- (void)startSilentMode {
    g_log = os_log_create("com.alpha.executor", "ui");
    self.consoleLines = [NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.uiBuilt = NO;
        [self startMonitoring];
        [self observeKeyboard];
        os_log_info(g_log, "silent mode started");
    });
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.monitorTimer invalidate];
        self.monitorTimer = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self.container removeFromSuperview];
        self.container = nil;
    });
}

#pragma mark - Keyboard Handling

- (void)observeKeyboard {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)keyboardWillShow:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect kbFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;
    CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // ارفع الـ panel
        [UIView animateWithDuration:duration animations:^{
            CGFloat panelH = self.panel.bounds.size.height;
            CGFloat screenH = self.container.bounds.size.height;
            CGFloat newY = screenH - panelH - kbHeight - 10;
            if (newY < 40) newY = 40;
            CGRect f = self.panel.frame;
            f.origin.y = newY;
            self.panel.frame = f;
        }];
    });
}

- (void)keyboardWillHide:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:duration animations:^{
            CGFloat screenH = self.container.bounds.size.height;
            CGFloat panelH = self.panel.bounds.size.height;
            CGRect f = self.panel.frame;
            f.origin.y = (screenH - panelH) / 2;
            self.panel.frame = f;
        }];
    });
}

- (void)hideKeyboard {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.scriptEditor resignFirstResponder];
    });
}

#pragma mark - Diagnostics & Console

- (void)setDiagnostics:(NSString *)diag {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.diagLabel) self.diagLabel.text = diag;
    });
}

- (void)appendConsoleLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!line) return;
        [self.consoleLines addObject:line];
        if (self.consoleLines.count > 100) {
            [self.consoleLines removeObjectAtIndex:0];
        }
        NSString *all = [self.consoleLines componentsJoinedByString:@"\n"];
        if (self.consoleView) {
            self.consoleView.text = all;
            NSRange r = NSMakeRange(self.consoleView.text.length, 0);
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
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    
    [container addSubview:btn];
    self.floatButton = btn;
}

- (void)buildPanel:(UIView *)container {
    CGSize s = container.bounds.size;
    CGFloat panelW = s.width * 0.92;
    CGFloat panelH = s.height * 0.75;
    
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((s.width - panelW)/2, (s.height - panelH)/2, panelW, panelH)];
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
    [container addSubview:panel];
    self.panel = panel;
    
    CGFloat pad = 12;
    CGFloat y = 8;
    
    // ==== Header ====
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, panelW - 130, 26)];
    title.text = @"Executor";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:title];
    
    // زر Hide Keyboard
    UIButton *kbBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    kbBtn.frame = CGRectMake(panelW - 128, y, 40, 30);
    [kbBtn setTitle:@"⌨" forState:UIControlStateNormal];
    [kbBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    kbBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:0.8];
    kbBtn.layer.cornerRadius = 6;
    kbBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [kbBtn addTarget:self action:@selector(hideKeyboard) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:kbBtn];
    
    // زر Close
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelW - 44, y, 36, 30);
    [closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:0.8];
    closeBtn.layer.cornerRadius = 6;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    y += 34;
    
    // ==== Diagnostics ====
    UILabel *diag = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, panelW - pad*2, 26)];
    diag.text = @"initializing...";
    diag.textColor = [UIColor yellowColor];
    diag.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    diag.numberOfLines = 0;
    [panel addSubview:diag];
    self.diagLabel = diag;
    
    y += 28;
    
    // ==== Editor Header ====
    UILabel *editLbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, 100, 16)];
    editLbl.text = @"SCRIPT";
    editLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    editLbl.font = [UIFont boldSystemFontOfSize:10];
    [panel addSubview:editLbl];
    y += 18;
    
    // ==== Script Editor (30%) ====
    CGFloat availableH = panelH - y - 130; // مساحة بعد الـ editor
    CGFloat editorH = availableH * 0.35;
    CGFloat consoleH = availableH * 0.65;
    
    UITextView *editor = [[UITextView alloc] initWithFrame:CGRectMake(pad, y, panelW - pad*2, editorH)];
    editor.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    editor.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
    editor.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    editor.layer.cornerRadius = 6;
    editor.text = @"print(\"hellow world\")";
    editor.delegate = self;
    editor.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    editor.spellCheckingType = UITextSpellCheckingTypeNo;
    // زر Done فوق الكيبورد
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, s.width, 44)];
    toolbar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *doneBtn = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                style:UIBarButtonItemStyleDone
                                                               target:self
                                                               action:@selector(hideKeyboard)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    toolbar.items = @[flex, doneBtn];
    editor.inputAccessoryView = toolbar;
    [panel addSubview:editor];
    self.scriptEditor = editor;
    
    y += editorH + 6;
    
    // ==== Console Header ====
    UILabel *consLbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, 100, 16)];
    consLbl.text = @"CONSOLE";
    consLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    consLbl.font = [UIFont boldSystemFontOfSize:10];
    [panel addSubview:consLbl];
    
    // زر Clear Console
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    clearBtn.frame = CGRectMake(panelW - 90, y - 2, 78, 20);
    [clearBtn setTitle:@"Clear" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    clearBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1.0];
    clearBtn.layer.cornerRadius = 4;
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:10];
    [clearBtn addTarget:self action:@selector(clearConsole) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:clearBtn];
    y += 18;
    
    // ==== Console (65%) ====
    UITextView *console = [[UITextView alloc] initWithFrame:CGRectMake(pad, y, panelW - pad*2, consoleH)];
    console.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    console.textColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    console.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    console.layer.cornerRadius = 6;
    console.text = @"> Console ready";
    console.editable = NO;
    [panel addSubview:console];
    self.consoleView = console;
    
    y += consoleH + 6;
    
    // ==== Status ====
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, panelW - pad*2, 16)];
    status.text = @"Ready";
    status.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    status.font = [UIFont systemFontOfSize:11];
    [panel addSubview:status];
    self.statusLabel = status;
    
    y += 18;
    
    // ==== Execute Button ====
    UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    execBtn.frame = CGRectMake(pad, y, panelW - pad*2, 40);
    execBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1.0];
    execBtn.layer.cornerRadius = 8;
    [execBtn setTitle:@"Execute" forState:UIControlStateNormal];
    [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    execBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [execBtn addTarget:self action:@selector(executeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:execBtn];
}

#pragma mark - Actions

- (void)togglePanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.panel.hidden = !self.panel.hidden;
        if (!self.panel.hidden) [self hideKeyboard];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *host = self.container;
    if (!host) return;
    CGPoint t = [pan translationInView:host];
    CGPoint c = CGPointMake(self.floatButton.center.x + t.x, self.floatButton.center.y + t.y);
    CGFloat hw = self.floatButton.bounds.size.width / 2;
    CGFloat hh = self.floatButton.bounds.size.height / 2;
    c.x = MAX(hw, MIN(host.bounds.size.width - hw, c.x));
    c.y = MAX(hh, MIN(host.bounds.size.height - hh, c.y));
    self.floatButton.center = c;
    [pan setTranslation:CGPointZero inView:host];
}

- (void)clearConsole {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.consoleLines removeAllObjects];
        self.consoleView.text = @"> Console cleared";
    });
}

- (void)executeTapped {
    [self hideKeyboard];
    NSString *script = self.scriptEditor.text;
    self.statusLabel.text = @"Executing...";
    self.statusLabel.textColor = [UIColor yellowColor];
    [self appendConsoleLine:@"> executing script..."];
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [[Executor sharedInstance] executeScript:script error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                self.statusLabel.text = @"✓ OK";
                self.statusLabel.textColor = [UIColor greenColor];
                [self appendConsoleLine:@"> ✓ execution successful"];
            } else {
                self.statusLabel.text = @"✗ ERR";
                self.statusLabel.textColor = [UIColor redColor];
                [self appendConsoleLine:[NSString stringWithFormat:@"> ✗ ERR: %@", error.localizedDescription]];
            }
        });
    });
}

@end
