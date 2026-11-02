//
//  DKXSFloatSpeedButton.m
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatSpeedButton.m；改名 + toast 改用 DYxs 已有的 DKXSUtils showToast，不 import 上游 AwemeHeaders。
//
#import "DKXSFloatSpeedButton.h"
#import "DKXSUtils.h"
#import <UIKit/UIKit.h>
#import <float.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

DKXSFloatSpeedButton *dkxsSpeedButton = nil;
BOOL dkxsShowSpeedX = NO;
CGFloat dkxsSpeedButtonSize = 32.0;
BOOL dkxsFloatSpeedButtonEnabled = NO;
static NSString *const kDKXSDefaultSpeedSettingsString = @"0.75,1.0,1.25,1.5,2.0,2.5,3.0";

static NSString *DKXSFormatSpeedOption(double speed) {
    NSString *speedString = [NSString stringWithFormat:@"%.2f", speed];
    while ([speedString containsString:@"."] && [speedString hasSuffix:@"0"]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    if ([speedString hasSuffix:@"."]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    return speedString;
}

static BOOL DKXSSpeedValuesMatch(double lhs, double rhs) {
    return fabs(lhs - rhs) <= 0.001;
}

NSString *DKXSDefaultSpeedSettingsString(void) {
    return kDKXSDefaultSpeedSettingsString;
}

static NSString *DKXSSpeedSettingsStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

static NSArray<NSString *> *DKXSParsedSpeedOptionsFromString(NSString *speedConfig) {
    NSMutableArray<NSString *> *validSpeeds = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *component in [speedConfig componentsSeparatedByString:@","]) {
        NSString *trimmedValue = [component stringByTrimmingCharactersInSet:whitespace];
        if (trimmedValue.length == 0) {
            continue;
        }

        NSScanner *scanner = [NSScanner scannerWithString:trimmedValue];
        double speed = 0.0;
        if ([scanner scanDouble:&speed] && scanner.isAtEnd && isfinite(speed) && speed > 0.0) {
            [validSpeeds addObject:DKXSFormatSpeedOption(speed)];
        }
    }
    return validSpeeds;
}

static double DKXSSpeedPreferenceValue(NSString *key, double fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    double speed = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    if (!isfinite(speed) || speed <= 0.0) {
        return fallback;
    }
    return speed;
}

static BOOL DKXSSpeedOptionsContainSpeed(NSArray<NSString *> *speedOptions, double speed) {
    if (!isfinite(speed) || speed <= 0.0) {
        return YES;
    }

    for (NSString *speedString in speedOptions) {
        if (DKXSSpeedValuesMatch([speedString doubleValue], speed)) {
            return YES;
        }
    }
    return NO;
}

static BOOL DKXSSpeedOptionsCoverRequiredPlaybackSpeeds(NSArray<NSString *> *speedOptions) {
    double defaultSpeed = DKXSSpeedPreferenceValue(@"DKXSDefaultSpeed", 1.0);
    double longPressSpeed = DKXSSpeedPreferenceValue(@"DKXSLongPressSpeed", 2.0);
    return DKXSSpeedOptionsContainSpeed(speedOptions, defaultSpeed) &&
           DKXSSpeedOptionsContainSpeed(speedOptions, longPressSpeed);
}

BOOL DKXSNormalizeSpeedSettingsForRequiredSpeeds(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *speedConfig = DKXSSpeedSettingsStringFromValue([defaults objectForKey:@"DKXSSpeedSettings"]);
    NSArray<NSString *> *validSpeeds = DKXSParsedSpeedOptionsFromString(speedConfig ?: @"");
    BOOL shouldUseDefaultSettings = speedConfig.length == 0 ||
                                    validSpeeds.count == 0 ||
                                    !DKXSSpeedOptionsCoverRequiredPlaybackSpeeds(validSpeeds);

    if (!shouldUseDefaultSettings) {
        return NO;
    }

    if (![speedConfig isEqualToString:kDKXSDefaultSpeedSettingsString]) {
        [defaults setObject:kDKXSDefaultSpeedSettingsString forKey:@"DKXSSpeedSettings"];
        return YES;
    }
    return NO;
}

NSArray *DKXSGetSpeedOptions() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    DKXSNormalizeSpeedSettingsForRequiredSpeeds();

    NSString *speedConfig = DKXSSpeedSettingsStringFromValue([defaults objectForKey:@"DKXSSpeedSettings"]) ?: kDKXSDefaultSpeedSettingsString;
    NSArray<NSString *> *validSpeeds = DKXSParsedSpeedOptionsFromString(speedConfig);
    if (validSpeeds.count == 0) {
        [defaults setObject:kDKXSDefaultSpeedSettingsString forKey:@"DKXSSpeedSettings"];
        validSpeeds = DKXSParsedSpeedOptionsFromString(kDKXSDefaultSpeedSettingsString);
    }

    return validSpeeds;
}

NSInteger DKXSGetCurrentSpeedIndex() {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"DKXSCurrentSpeedIndex"];
    NSArray *speeds = DKXSGetSpeedOptions();

    if (index >= speeds.count || index < 0) {
        index = 0;
        [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DKXSCurrentSpeedIndex"];
    }

    return index;
}

float DKXSGetCurrentSpeed() {
    NSArray *speeds = DKXSGetSpeedOptions();
    NSInteger index = DKXSGetCurrentSpeedIndex();

    if (speeds.count == 0)
        return 1.0;
    float speed = [speeds[index] floatValue];
    return speed > 0 ? speed : 1.0;
}

void DKXSSetCurrentSpeedIndex(NSInteger index) {
    NSArray *speeds = DKXSGetSpeedOptions();

    if (speeds.count == 0)
        return;
    index = index % speeds.count;
    if (index < 0) {
        index += speeds.count;
    }

    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DKXSCurrentSpeedIndex"];
}

BOOL DKXSSetCurrentSpeedValue(float speed) {
    if (!isfinite(speed) || speed <= 0.0f) {
        return NO;
    }

    NSArray *speeds = DKXSGetSpeedOptions();
    for (NSInteger index = 0; index < speeds.count; index++) {
        if (DKXSSpeedValuesMatch([speeds[index] floatValue], speed)) {
            DKXSSetCurrentSpeedIndex(index);
            return YES;
        }
    }
    return NO;
}

void DKXSUpdateSpeedButtonUI() {
    if (!dkxsSpeedButton)
        return;

    float currentSpeed = DKXSGetCurrentSpeed();

    NSString *formattedSpeed;
    if (fmodf(currentSpeed, 1.0) == 0) {
        // 整数值 (1.0, 2.0) -> "1", "2"
        formattedSpeed = [NSString stringWithFormat:@"%.0f", currentSpeed];
    } else if (fmodf(currentSpeed * 10, 1.0) == 0) {
        // 一位小数 (1.5) -> "1.5"
        formattedSpeed = [NSString stringWithFormat:@"%.1f", currentSpeed];
    } else {
        // 两位小数 (1.25) -> "1.25"
        formattedSpeed = [NSString stringWithFormat:@"%.2f", currentSpeed];
    }

    if (dkxsShowSpeedX) {
        formattedSpeed = [formattedSpeed stringByAppendingString:@"x"];
    }

    if ([NSThread isMainThread]) {
        [dkxsSpeedButton setTitle:formattedSpeed forState:UIControlStateNormal];
    } else {
        __weak DKXSFloatSpeedButton *weakButton = dkxsSpeedButton;
        dispatch_async(dispatch_get_main_queue(), ^{
          DKXSFloatSpeedButton *strongButton = weakButton;
          if (!strongButton) {
              return;
          }
          [strongButton setTitle:formattedSpeed forState:UIControlStateNormal];
        });
    }
}

DKXSFloatSpeedButton *DKXSGetSpeedButton(void) { return dkxsSpeedButton; }

NSArray *DKXSFindViewControllersInHierarchy(UIViewController *rootViewController) {
    if (!rootViewController) {
        return @[];
    }

    NSMutableArray *viewControllers = [NSMutableArray array];
    [viewControllers addObject:rootViewController];

    for (UIViewController *childVC in rootViewController.childViewControllers) {
        [viewControllers addObjectsFromArray:DKXSFindViewControllersInHierarchy(childVC)];
    }

    return viewControllers;
}

static const CGFloat kDKXSSpeedButtonEdgeInset = 10.0;
static const CGFloat kDKXSSpeedButtonDefaultYFromBottomPercent = 0.65;
static const CGFloat kDKXSSpeedButtonPressedScale = 0.75;

typedef NS_ENUM(NSInteger, DKXSSpeedButtonEdge) {
    DKXSSpeedButtonEdgeLeft = 0,
    DKXSSpeedButtonEdgeRight,
    DKXSSpeedButtonEdgeTop,
    DKXSSpeedButtonEdgeBottom,
};

static BOOL DKXSSpeedButtonStickToEdgeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSSpeedButtonStickToEdge"];
}

static BOOL DKXSAutoHideSpeedButtonEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSAutoHideSpeedButton"] && DKXSSpeedButtonStickToEdgeEnabled();
}

static NSTimeInterval DKXSAutoHideSpeedButtonInterval(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"DKXSAutoHideSpeedButtonTime"] == nil) {
        return 30.0;
    }
    double interval = [defaults doubleForKey:@"DKXSAutoHideSpeedButtonTime"];
    return interval > 0.0 ? interval : 30.0;
}


static const CGFloat kDKXSSpeedButtonEdgeSwitchHysteresis = 12.0;

@interface DKXSFloatSpeedButton ()
@property(nonatomic, assign) DKXSSpeedButtonEdge dkxsActiveDragEdge;
@property(nonatomic, assign) BOOL dkxsHasCenterBeforeEdgeHidden;
@property(nonatomic, assign) CGPoint dkxsCenterBeforeEdgeHidden;
@end

@implementation DKXSFloatSpeedButton

+ (void)reloadConfiguration {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadConfiguration]; });
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL enabled = [defaults boolForKey:@"DKXSEnableFloatSpeedButton"];
    BOOL showX = [defaults boolForKey:@"DKXSSpeedButtonShowX"];
    CGFloat configuredSize = [defaults floatForKey:@"DKXSSpeedButtonSize"];
    CGFloat size = MIN(MAX(configuredSize > 0 ? configuredSize : 32.0, 20.0), 60.0);
    BOOL changed = enabled != dkxsFloatSpeedButtonEnabled || showX != dkxsShowSpeedX || fabs(size - dkxsSpeedButtonSize) > FLT_EPSILON;
    dkxsFloatSpeedButtonEnabled = enabled;
    dkxsShowSpeedX = showX;
    dkxsSpeedButtonSize = size;
    if (dkxsSpeedButton) {
        if (dkxsSpeedButton.isEdgeHidden && !DKXSAutoHideSpeedButtonEnabled()) [dkxsSpeedButton dkxs_restoreFromEdgeHidden];
        [dkxsSpeedButton loadSavedPosition];
        [dkxsSpeedButton resetFadeTimer];
    }
    if (!changed) return;
    if (dkxsSpeedButton && fabs(dkxsSpeedButton.bounds.size.width - size) > FLT_EPSILON) {
        dkxsSpeedButton.bounds = CGRectMake(0, 0, size, size);
        dkxsSpeedButton.layer.cornerRadius = size / 2.0;
        [dkxsSpeedButton loadSavedPosition];
    }
    DKXSUpdateSpeedButtonUI();
}

+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller {
    if (!dkxsSpeedButton) {
        CGFloat size = dkxsSpeedButtonSize;
        CGRect frame = CGRectMake((window.bounds.size.width - size) / 2.0, (window.bounds.size.height - size) / 2.0, size, size);
        dkxsSpeedButton = [[self alloc] initWithFrame:frame];
        // 新控件先隐藏，是否显示由协调器决定。
        dkxsSpeedButton.hidden = YES;
        DKXSUpdateSpeedButtonUI();
    }
    if (dkxsSpeedButton.interactionController != controller) {
        dkxsSpeedButton.interactionController = controller;
        [dkxsSpeedButton resetButtonState];
    }
    if (dkxsSpeedButton.window != window) {
        [window addSubview:dkxsSpeedButton];
        [dkxsSpeedButton loadSavedPosition];
        [dkxsSpeedButton resetFadeTimer];
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityLabel = @"DKXSSpeedSwitchButton";
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.1];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;

        [self setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.3] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.2;

        self.userInteractionEnabled = YES;
        self.isResponding = YES;

        self.originalAlpha = 1.0;
        self.alpha = 0.5;

        [self resetFadeTimer];
        [self ensureStatusCheckTimerRunning];

        [self setupGestureRecognizers];

        [self loadSavedPosition];

        self.justToggledLock = NO;
    }
    return self;
}
- (void)setupGestureRecognizers {
    for (UIGestureRecognizer *recognizer in [self.gestureRecognizers copy]) {
        [self removeGestureRecognizer:recognizer];
    }
    [self removeTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self removeTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self removeTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGesture.minimumPressDuration = 0.5;
    [self addGestureRecognizer:longPressGesture];

    [self addTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    panGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    longPressGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (void)handleTouchDown:(UIButton *)sender {
    if (self.isEdgeHidden) { [self dkxs_restoreFromEdgeHidden]; self.dkxsJustRestoredFromEdgeHidden = YES; return; }
    self.isResponding = YES;
    [self resetFadeTimer];
}

- (void)handleTouchUpInside:(UIButton *)sender {
    if (self.dkxsJustRestoredFromEdgeHidden) { self.dkxsJustRestoredFromEdgeHidden = NO; return; }
    if (self.justToggledLock) {
        self.justToggledLock = NO;
        return;
    }

    [self resetFadeTimer];

    [UIView animateWithDuration:0.08
        animations:^{
          self.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:0.08
                           animations:^{
                             self.transform = CGAffineTransformIdentity;
                           }];
        }];

    id currentController = DKXSCurrentSpeedInteractionController();
    if (currentController) {
        self.interactionController = currentController;
    }

    if (self.interactionController) {
        @try {
            // 上游原调用就是 speedButtonTapped:（接线文件里 %new 在互动控制器上加的方法），
            // 移植时误改名为 dkxsSpeedButtonTapped: 导致两边对不上（build #48）。
            // 互动控制器是 id 类型、方法未在任何头文件声明，用 DYxs 已有的
            // objc_msgSend 转型写法动态调用，不产生声明错误。
            ((void (*)(id, SEL, id))objc_msgSend)(self.interactionController, @selector(speedButtonTapped:), self);
        } @catch (NSException *exception) {
            self.isResponding = NO;
        }
    } else {
        self.isResponding = NO;
    }
}

- (void)handleTouchUpOutside:(UIButton *)sender {
    self.justToggledLock = NO;
    [self resetFadeTimer];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    self.isResponding = YES;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];

        self.originalLockState = self.isLocked;

        [self toggleLockState];
    }
}

- (void)toggleLockState {
    self.isLocked = !self.isLocked;
    self.justToggledLock = YES;

    NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
    [DKXSUtils showToast:toastMessage];

    if (self.isLocked) {
        [self saveButtonPosition];
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetToggleLockFlag {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetButtonState {
    BOOL preserveEdgeHidden = self.isEdgeHidden &&
                              (DKXSAutoHideSpeedButtonEnabled() || self.dkxsEdgeHiddenByClearMode);
    self.justToggledLock = NO;
    self.dkxsJustRestoredFromEdgeHidden = NO;
    self.isResponding = YES;
    self.userInteractionEnabled = YES;
    self.transform = CGAffineTransformIdentity;

    if (preserveEdgeHidden) {
        self.isEdgeHidden = YES;
        self.alpha = 0.02;
        [self dkxs_showEdgeIndicator];
    } else {
        self.isEdgeHidden = NO;
        [self dkxs_hideEdgeIndicator];
        self.alpha = self.originalAlpha;
        [self dkxs_schedulePresentationTimersIfNeeded];
    }

    [self setupGestureRecognizers];
}

- (void)resetFadeTimer {
    [self dkxs_cancelAutoHideTimer];
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    if (self.isEdgeHidden) {
        return;
    }

    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
    }

    __weak __typeof(self) weakSelf = self;
    if (!DKXSAutoHideSpeedButtonEnabled()) {
        NSTimer *fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                             repeats:NO
                                                               block:^(NSTimer *timer) {
                                                                 __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf || strongSelf.isEdgeHidden) {
                                                                     return;
                                                                 }
                                                                 [UIView animateWithDuration:0.3
                                                                                  animations:^{
                                                                                    strongSelf.alpha = 0.5;
                                                                                  }];
                                                                 strongSelf.fadeTimer = nil;
                                                               }];
        self.fadeTimer = fadeTimer;
        [[NSRunLoop mainRunLoop] addTimer:fadeTimer forMode:NSRunLoopCommonModes];
        return;
    }

    NSTimeInterval interval = DKXSAutoHideSpeedButtonInterval();
    NSTimer *autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                             repeats:NO
                                                               block:^(NSTimer *timer) {
                                                                 __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf) {
                                                                     return;
                                                                 }
                                                                 [strongSelf dkxs_applyEdgeHiddenState];
                                                                 strongSelf.autoHideTimer = nil;
                                                               }];
    self.autoHideTimer = autoHideTimer;
    [[NSRunLoop mainRunLoop] addTimer:autoHideTimer forMode:NSRunLoopCommonModes];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.isLocked)
        return;

    self.justToggledLock = NO;
    self.dkxsJustRestoredFromEdgeHidden = NO;
    if (self.isEdgeHidden) [self dkxs_restoreFromEdgeHidden];
    [self resetFadeTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.transform = CGAffineTransformIdentity;
        if (DKXSSpeedButtonStickToEdgeEnabled()) {
            self.dkxsActiveDragEdge = [self dkxsEdgeForCenter:self.center];
            self.center = [self dkxsCenterOnEdge:self.dkxsActiveDragEdge forPoint:self.center];
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint touchPoint = [pan locationInView:self.superview];
        if (DKXSSpeedButtonStickToEdgeEnabled()) {
            DKXSSpeedButtonEdge nearestEdge = [self dkxsNearestEdgeForPoint:touchPoint];
            if (nearestEdge != self.dkxsActiveDragEdge) {
                CGFloat currentDist = [self dkxsDistanceFromPoint:touchPoint toEdge:self.dkxsActiveDragEdge];
                CGFloat nearestDist = [self dkxsDistanceFromPoint:touchPoint toEdge:nearestEdge];
                if (nearestDist + kDKXSSpeedButtonEdgeSwitchHysteresis < currentDist) {
                    self.dkxsActiveDragEdge = nearestEdge;
                }
            }
            self.center = [self dkxsCenterOnEdge:self.dkxsActiveDragEdge forPoint:touchPoint];
        } else {
            self.center = [self dkxsClampedCenterForProposedCenter:touchPoint];
        }
        self.alpha = self.originalAlpha;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.center = [self dkxsConstrainedCenterForProposedCenter:self.center];
        self.alpha = self.originalAlpha;
        [self saveButtonPosition];
        if (self.isEdgeHidden) {
            [self dkxs_showEdgeIndicator];
        }
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setFloat:self.center.x / self.superview.bounds.size.width forKey:@"DKXSSpeedButtonCenterXPercent"];
        [defaults setFloat:self.center.y / self.superview.bounds.size.height forKey:@"DKXSSpeedButtonCenterYPercent"];
        [defaults setBool:self.isLocked forKey:@"DKXSSpeedButtonLocked"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.isLocked = [defaults boolForKey:@"DKXSSpeedButtonLocked"];

    CGPoint targetCenter;
    if ([self dkxsHasSavedPosition]) {
        float centerXPercent = [defaults floatForKey:@"DKXSSpeedButtonCenterXPercent"];
        float centerYPercent = [defaults floatForKey:@"DKXSSpeedButtonCenterYPercent"];
        targetCenter = CGPointMake(centerXPercent * self.superview.bounds.size.width,
                                   centerYPercent * self.superview.bounds.size.height);
    } else {
        targetCenter = [self dkxsDefaultCenter];
    }

    self.center = [self dkxsConstrainedCenterForProposedCenter:targetCenter];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        [self dkxs_hideEdgeIndicator];
        return;
    }
    [self ensureStatusCheckTimerRunning];
    [self resetFadeTimer];
}

- (void)ensureStatusCheckTimerRunning {
    if (self.statusCheckTimer && [self.statusCheckTimer isValid]) {
        return;
    }
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(checkAndRecoverButtonStatus) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.statusCheckTimer = timer;
}

- (void)stopTimers {
    [self dkxs_cancelAutoHideTimer];
    if (self.statusCheckTimer) {
        [self.statusCheckTimer invalidate];
        self.statusCheckTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)checkAndRecoverButtonStatus {
    if (!self.isResponding) {
        [self resetButtonState];
        self.isResponding = YES;
    }

    if (!self.interactionController) {
        self.interactionController = DKXSCurrentSpeedInteractionController();
    }
}

- (void)dealloc {
    [self.edgeIndicatorView removeFromSuperview];
    [self stopTimers];
}
- (void)resetToDefaultPosition {
    if (!self.superview) {
        return;
    }

    self.dkxsHasCenterBeforeEdgeHidden = NO;
    if (self.isEdgeHidden && !self.dkxsEdgeHiddenByClearMode) {
        [self dkxs_restoreFromEdgeHidden];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"DKXSSpeedButtonCenterXPercent"];
    [defaults removeObjectForKey:@"DKXSSpeedButtonCenterYPercent"];
    self.center = [self dkxsDefaultCenter];
    [self resetFadeTimer];
}

- (void)dkxs_cancelAutoHideTimer {
    if (self.autoHideTimer) {
        [self.autoHideTimer invalidate];
        self.autoHideTimer = nil;
    }
}

- (void)dkxs_rememberCenterBeforeEdgeHidden {
    if (self.dkxsHasCenterBeforeEdgeHidden) {
        return;
    }
    self.dkxsCenterBeforeEdgeHidden = self.center;
    self.dkxsHasCenterBeforeEdgeHidden = YES;
}

- (void)dkxs_moveToNearestEdgeForHiddenState {
    [self dkxs_rememberCenterBeforeEdgeHidden];
    self.center = [self dkxsSnappedCenterForProposedCenter:self.center];
}

- (void)dkxs_restoreCenterBeforeEdgeHiddenIfNeeded {
    if (!self.dkxsHasCenterBeforeEdgeHidden) {
        return;
    }
    self.center = [self dkxsConstrainedCenterForProposedCenter:self.dkxsCenterBeforeEdgeHidden];
    self.dkxsHasCenterBeforeEdgeHidden = NO;
}

- (void)dkxs_applyEdgeHiddenState {
    // 位置锁定只限制拖动，不能阻止自动隐藏计时器收边。
    if (self.hidden || !self.window || self.isEdgeHidden || self.dkxsEdgeHiddenByClearMode || !DKXSAutoHideSpeedButtonEnabled()) {
        return;
    }

    [self dkxs_cancelAutoHideTimer];
    [self dkxs_moveToNearestEdgeForHiddenState];
    self.dkxsEdgeHiddenByClearMode = NO;
    self.isEdgeHidden = YES;
    self.alpha = 0.02;
    [self dkxs_showEdgeIndicator];
}

- (void)dkxs_restoreFromEdgeHidden {
    if (!self.isEdgeHidden || self.dkxsEdgeHiddenByClearMode) {
        return;
    }

    self.isEdgeHidden = NO;
    [self dkxs_restoreCenterBeforeEdgeHiddenIfNeeded];
    self.alpha = self.originalAlpha;
    [self dkxs_hideEdgeIndicator];
    [self resetFadeTimer];
}

- (void)dkxs_schedulePresentationTimersIfNeeded {
    if (self.isEdgeHidden || self.dkxsEdgeHiddenByClearMode) {
        self.alpha = 0.02;
        [self dkxs_showEdgeIndicator];
        return;
    }

    if (DKXSAutoHideSpeedButtonEnabled() && self.autoHideTimer && [self.autoHideTimer isValid]) {
        return;
    }

    [self resetFadeTimer];
}

- (void)dkxs_showEdgeIndicator {
    if (!self.superview || !self.isEdgeHidden) {
        return;
    }

    // 自动隐藏产生的边缘条只能依附于当前播放页；清屏边缘态由清屏流程单独管理。
    if (!self.dkxsEdgeHiddenByClearMode && self.hidden) {
        [self dkxs_hideEdgeIndicator];
        return;
    }

    DKXSSpeedButtonEdge edge = [self dkxsEdgeForCenter:self.center];
    CGFloat indicatorThickness = 2.0;
    CGSize superSize = self.superview.bounds.size;
    CGFloat centerX = self.center.x;
    CGFloat centerY = self.center.y;

    if (!self.edgeIndicatorView) {
        self.edgeIndicatorView = [[UIView alloc] init];
        self.edgeIndicatorView.backgroundColor = [UIColor systemGrayColor];
        self.edgeIndicatorView.userInteractionEnabled = NO;
        self.edgeIndicatorView.layer.masksToBounds = YES;
    }

    CGRect frame = CGRectZero;
    CACornerMask maskedCorners = 0;
    switch (edge) {
        case DKXSSpeedButtonEdgeLeft:
            frame = CGRectMake(0.0,
                               centerY - CGRectGetHeight(self.bounds) * 0.5,
                               indicatorThickness,
                               CGRectGetHeight(self.bounds));
            maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
            break;
        case DKXSSpeedButtonEdgeRight:
            frame = CGRectMake(superSize.width - indicatorThickness,
                               centerY - CGRectGetHeight(self.bounds) * 0.5,
                               indicatorThickness,
                               CGRectGetHeight(self.bounds));
            maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
            break;
        case DKXSSpeedButtonEdgeTop:
            frame = CGRectMake(centerX - CGRectGetWidth(self.bounds) * 0.5,
                               0.0,
                               CGRectGetWidth(self.bounds),
                               indicatorThickness);
            maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case DKXSSpeedButtonEdgeBottom:
            frame = CGRectMake(centerX - CGRectGetWidth(self.bounds) * 0.5,
                               superSize.height - indicatorThickness,
                               CGRectGetWidth(self.bounds),
                               indicatorThickness);
            maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            break;
    }

    self.edgeIndicatorView.frame = frame;
    self.edgeIndicatorView.layer.cornerRadius = indicatorThickness;
    self.edgeIndicatorView.layer.maskedCorners = maskedCorners;
    self.edgeIndicatorView.alpha = 1.0;
    self.edgeIndicatorView.hidden = NO;

    if (![self.edgeIndicatorView isDescendantOfView:self.superview]) {
        [self.superview addSubview:self.edgeIndicatorView];
    }
    [self.superview bringSubviewToFront:self.edgeIndicatorView];
}

- (void)dkxs_hideEdgeIndicator {
    if (self.edgeIndicatorView) {
        self.edgeIndicatorView.hidden = YES;
    }
}

- (void)dkxsEdgeGeometryForSuperviewSize:(CGSize)size
                               halfWidth:(CGFloat)hw
                              halfHeight:(CGFloat)hh
                             leftCenterX:(CGFloat *)leftCenterX
                            rightCenterX:(CGFloat *)rightCenterX
                               topCenterY:(CGFloat *)topCenterY
                            bottomCenterY:(CGFloat *)bottomCenterY
                          minAlongEdgeX:(CGFloat *)minAlongEdgeX
                          maxAlongEdgeX:(CGFloat *)maxAlongEdgeX
                          minAlongEdgeY:(CGFloat *)minAlongEdgeY
                          maxAlongEdgeY:(CGFloat *)maxAlongEdgeY {
    CGFloat inset = kDKXSSpeedButtonEdgeInset;
    *leftCenterX = hw + inset;
    *rightCenterX = size.width - hw - inset;
    *topCenterY = hh + inset;
    *bottomCenterY = size.height - hh - inset;
    *minAlongEdgeX = hw + inset;
    *maxAlongEdgeX = size.width - hw - inset;
    *minAlongEdgeY = hh + inset;
    *maxAlongEdgeY = size.height - hh - inset;
}

- (BOOL)dkxsEdgeMetricsWithLeftX:(CGFloat *)leftX
                          rightX:(CGFloat *)rightX
                            topY:(CGFloat *)topY
                         bottomY:(CGFloat *)bottomY
                            minX:(CGFloat *)minX
                            maxX:(CGFloat *)maxX
                            minY:(CGFloat *)minY
                            maxY:(CGFloat *)maxY {
    if (!self.superview) {
        return NO;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    [self dkxsEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:leftX
                              rightCenterX:rightX
                                 topCenterY:topY
                              bottomCenterY:bottomY
                            minAlongEdgeX:minX
                            maxAlongEdgeX:maxX
                            minAlongEdgeY:minY
                            maxAlongEdgeY:maxY];
    return YES;
}

- (CGFloat)dkxsDistanceFromPoint:(CGPoint)point toEdge:(DKXSSpeedButtonEdge)edge {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dkxsEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return CGFLOAT_MAX;
    }

    switch (edge) {
        case DKXSSpeedButtonEdgeLeft:
            return fabs(point.x - leftX);
        case DKXSSpeedButtonEdgeRight:
            return fabs(point.x - rightX);
        case DKXSSpeedButtonEdgeTop:
            return fabs(point.y - topY);
        case DKXSSpeedButtonEdgeBottom:
            return fabs(point.y - bottomY);
    }
}

- (DKXSSpeedButtonEdge)dkxsNearestEdgeForPoint:(CGPoint)point {
    DKXSSpeedButtonEdge edge = DKXSSpeedButtonEdgeLeft;
    CGFloat minDist = [self dkxsDistanceFromPoint:point toEdge:edge];

    for (DKXSSpeedButtonEdge candidate = DKXSSpeedButtonEdgeRight; candidate <= DKXSSpeedButtonEdgeBottom; candidate++) {
        CGFloat dist = [self dkxsDistanceFromPoint:point toEdge:candidate];
        if (dist < minDist) {
            minDist = dist;
            edge = candidate;
        }
    }
    return edge;
}

- (DKXSSpeedButtonEdge)dkxsEdgeForCenter:(CGPoint)center {
    return [self dkxsNearestEdgeForPoint:center];
}

- (CGPoint)dkxsCenterOnEdge:(DKXSSpeedButtonEdge)edge forPoint:(CGPoint)point {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dkxsEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return point;
    }

    switch (edge) {
        case DKXSSpeedButtonEdgeLeft:
            return CGPointMake(leftX, MIN(MAX(point.y, minY), maxY));
        case DKXSSpeedButtonEdgeRight:
            return CGPointMake(rightX, MIN(MAX(point.y, minY), maxY));
        case DKXSSpeedButtonEdgeTop:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), topY);
        case DKXSSpeedButtonEdgeBottom:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), bottomY);
    }
}

- (CGPoint)dkxsSnappedCenterForProposedCenter:(CGPoint)proposed {
    DKXSSpeedButtonEdge edge = [self dkxsNearestEdgeForPoint:proposed];
    return [self dkxsCenterOnEdge:edge forPoint:proposed];
}

- (CGPoint)dkxsClampedCenterForProposedCenter:(CGPoint)proposed {
    CGFloat minX, maxX, minY, maxY;
    CGFloat unusedLeft, unusedRight, unusedTop, unusedBottom;
    if (![self dkxsEdgeMetricsWithLeftX:&unusedLeft rightX:&unusedRight topY:&unusedTop bottomY:&unusedBottom minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return proposed;
    }
    return CGPointMake(MIN(MAX(proposed.x, minX), maxX), MIN(MAX(proposed.y, minY), maxY));
}

- (CGPoint)dkxsConstrainedCenterForProposedCenter:(CGPoint)proposed {
    if (DKXSSpeedButtonStickToEdgeEnabled()) {
        return [self dkxsSnappedCenterForProposedCenter:proposed];
    }
    return [self dkxsClampedCenterForProposedCenter:proposed];
}

- (CGPoint)dkxsDefaultCenter {
    if (!self.superview) {
        return self.center;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    [self dkxsEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:&leftX
                              rightCenterX:&rightX
                                 topCenterY:&topY
                              bottomCenterY:&bottomY
                            minAlongEdgeX:&minX
                            maxAlongEdgeX:&maxX
                            minAlongEdgeY:&minY
                            maxAlongEdgeY:&maxY];

    CGFloat defaultY = size.height * (1.0 - kDKXSSpeedButtonDefaultYFromBottomPercent);
    defaultY = MIN(MAX(defaultY, minY), maxY);
    return CGPointMake(rightX, defaultY);
}

- (BOOL)dkxsHasSavedPosition {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"DKXSSpeedButtonCenterXPercent"] != nil &&
           [defaults objectForKey:@"DKXSSpeedButtonCenterYPercent"] != nil;
}

@end
