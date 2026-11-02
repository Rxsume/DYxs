//
//  DKXSFloatClearButton.xm
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatClearButton.xm；类 / 函数 / 设置键一律 DYYY -> DKXS。
//  原文件头部的 1KeyHideDYUI 署名是上游引用旧项目的残留，与本移植无关，已去掉。
#import "DKXSFloatClearButton.h"
#import "DKXSUtils.h"
#import "DKXSFloatingButtonCoordinator.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <float.h>
#import <math.h>
#import <objc/runtime.h>
#import <signal.h>

static const CGFloat kDKXSClearButtonEdgeInset = 8.0;
static const CGFloat kDKXSClearButtonDefaultYFromBottomPercent = 0.75;

typedef NS_ENUM(NSInteger, DKXSClearButtonEdge) {
    DKXSClearButtonEdgeLeft = 0,
    DKXSClearButtonEdgeRight,
    DKXSClearButtonEdgeTop,
    DKXSClearButtonEdgeBottom,
};

@interface DKXSHideUIButton ()
@property(nonatomic, assign) DKXSClearButtonEdge dkxsActiveDragEdge;
@property(nonatomic, assign) BOOL manualClearActive;
- (void)updateClearState;
@property(nonatomic, strong) NSHashTable<UIView *> *progressViews;
@property(nonatomic, strong) NSMapTable<Class, NSNumber *> *classifications;
@property(nonatomic, strong) NSSet<NSString *> *targetNames;
@property(nonatomic, assign) BOOL needsDiscovery;
@property(nonatomic, assign) BOOL refreshScheduled;
- (void)invalidateTargetCache;
- (void)restoreCachedTargetViews;
@end


// 移植自上游 DYYYUtils getActiveWindow（仅窗口查找，无业务依赖）。
static UIWindow *DKXSActiveWindow(void) {
    UIWindow *fallbackWindow = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].delegate.window ?: [UIApplication sharedApplication].windows.firstObject;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *activeScene = nil, *inactiveScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UISceneActivationState state = scene.activationState;
                if (state == UISceneActivationStateForegroundActive) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                } else if (state == UISceneActivationStateForegroundInactive) {
                    if (inactiveScene == nil) {
                        inactiveScene = (UIWindowScene *)scene;
                    }
                }
            }
        }
        UIWindowScene *targetScene = activeScene ?: inactiveScene;
        if (targetScene) {
            if (@available(iOS 15.0, *)) {
                return targetScene.keyWindow ?: targetScene.windows.firstObject ?: fallbackWindow;
            } else {
                UIWindow *firstVisibleWindow = nil;
                for (UIWindow *window in targetScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    } else if (firstVisibleWindow == nil && !window.isHidden && window.rootViewController) {
                        firstVisibleWindow = window;
                    }
                }
                return firstVisibleWindow ?: targetScene.windows.firstObject ?: fallbackWindow;
            }
        }
    }
    return fallbackWindow;
}

BOOL dkxsIsPerformingFloatClearOperation = NO;

static NSInteger dkxsClearButtonMutationDepth = 0;

static inline void DKXSBeginClearButtonMutation(void) {
    dkxsClearButtonMutationDepth++;
    dkxsIsPerformingFloatClearOperation = YES;
}

static inline void DKXSEndClearButtonMutation(void) {
    if (dkxsClearButtonMutationDepth > 0) {
        dkxsClearButtonMutationDepth--;
    }
    dkxsIsPerformingFloatClearOperation = dkxsClearButtonMutationDepth > 0;
}

static void DKXSPerformClearButtonMutation(dispatch_block_t block) {
    if (!block) {
        return;
    }
    DKXSBeginClearButtonMutation();
    @try {
        block();
    } @finally {
        DKXSEndClearButtonMutation();
    }
}


DKXSHideUIButton *dkxsHideButton = nil;
NSArray *dkxsTargetClassNames;
static NSUInteger dkxsTargetClassConfiguration = NSUIntegerMax;

typedef NS_ENUM(NSInteger, DKXSClearProgressMode) {
    DKXSClearProgressModeNone = 0,
    DKXSClearProgressModeRemove,
    DKXSClearProgressModeHide,
};

// 清屏隐藏状态栏：遍历所有 window 的 VC 层级，触发系统重新评估状态栏显隐
static void DKXSRefreshStatusBarVisibility(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideStatusBarOnClear"] ||
        [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideStatusbar"]) {
        return;
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *rootVC = window.rootViewController;
        if (!rootVC) continue;
        [rootVC setNeedsStatusBarAppearanceUpdate];
        for (UIViewController *child in rootVC.childViewControllers) {
            [child setNeedsStatusBarAppearanceUpdate];
        }
    }
}

static char dkxsProgressModeKey;
static char dkxsProgressOriginalHiddenKey;
static char dkxsProgressOriginalInteractionKey;
static char dkxsProgressOriginalLayerOpacityKey;
char dkxsClearOriginalAlphaKey;
static char dkxsClearOriginalHiddenKey;
static char dkxsClearStateCapturedKey;

// AWEAwemePlayVideoPauseIcon 的 alpha 由抖音业务层动态控制（播放=0、暂停=1），
// 对这类视图使用 hidden 属性隐藏而非修改 alpha，避免与业务层 alpha 控制冲突。
BOOL DKXSIsDynamicAlphaView(UIView *view) {
    static Class pauseIconClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pauseIconClass = NSClassFromString(@"AWEAwemePlayVideoPauseIcon");
    });
    return pauseIconClass && [view isKindOfClass:pauseIconClass];
}

static BOOL DKXSHasCapturedClearTargetViewState(UIView *view) {
    return view && objc_getAssociatedObject(view, &dkxsClearStateCapturedKey) != nil;
}

static void DKXSCaptureClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || DKXSHasCapturedClearTargetViewState(view)) {
        return;
    }

    objc_setAssociatedObject(view, &dkxsClearStateCapturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dkxsClearOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dkxsClearOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKXSApplyClearTargetViewHiddenState(UIView *view) {
    if (!view) {
        return;
    }

    DKXSCaptureClearTargetViewStateIfNeeded(view);
    if (DKXSIsDynamicAlphaView(view)) {
        if (!view.hidden) view.hidden = YES;
    } else if (view.alpha != 0) {
        view.alpha = 0.0;
    }
}

void DKXSRestoreClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || !DKXSHasCapturedClearTargetViewState(view)) {
        return;
    }

    NSNumber *originalHidden = objc_getAssociatedObject(view, &dkxsClearOriginalHiddenKey);
    NSNumber *originalAlpha = objc_getAssociatedObject(view, &dkxsClearOriginalAlphaKey);
    if (originalHidden) {
        view.hidden = originalHidden.boolValue;
    }
    if (originalAlpha) {
        view.alpha = originalAlpha.floatValue;
    }

    objc_setAssociatedObject(view, &dkxsClearOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dkxsClearOriginalAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dkxsClearStateCapturedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static DKXSClearProgressMode DKXSCurrentClearProgressMode(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"DKXSRemoveTimeProgress"]) {
        return DKXSClearProgressModeRemove;
    }
    if ([defaults boolForKey:@"DKXSHideTimeProgress"]) {
        return DKXSClearProgressModeHide;
    }
    return DKXSClearProgressModeNone;
}

static BOOL DKXSIsClearProgressView(UIView *view) {
    static NSArray<NSString *> *classNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      classNames = @[
          @"AWEPlayInteractionProgressContainerView",
          @"AWEDPlayerProgressContainerView",
          @"AWEFeedProgressSlider",
          @"AWEFeedProgressSliderForLongPress",
          @"AWEFakeProgressSliderView",
          @"AWEProgressContainerView",
          @"AWEProgressPlayBackSlider",
      ];
    });

    for (NSString *className in classNames) {
        Class progressClass = NSClassFromString(className);
        if (progressClass && [view isKindOfClass:progressClass]) {
            return YES;
        }
    }
    return NO;
}

static void DKXSRestoreClearProgressViewState(UIView *view) {
    NSNumber *appliedMode = objc_getAssociatedObject(view, &dkxsProgressModeKey);
    if (!appliedMode) {
        return;
    }

    NSNumber *originalLayerOpacity = objc_getAssociatedObject(view, &dkxsProgressOriginalLayerOpacityKey);
    if (originalLayerOpacity) {
        view.layer.opacity = originalLayerOpacity.floatValue;
    }

    if (appliedMode.integerValue == DKXSClearProgressModeRemove) {
        NSNumber *originalHidden = objc_getAssociatedObject(view, &dkxsProgressOriginalHiddenKey);
        NSNumber *originalInteraction = objc_getAssociatedObject(view, &dkxsProgressOriginalInteractionKey);
        if (originalHidden) {
            view.hidden = originalHidden.boolValue;
        }
        if (originalInteraction) {
            view.userInteractionEnabled = originalInteraction.boolValue;
        }
    }

    objc_setAssociatedObject(view, &dkxsProgressModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dkxsProgressOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dkxsProgressOriginalInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dkxsProgressOriginalLayerOpacityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKXSApplyClearProgressViewState(UIView *view, DKXSClearProgressMode mode) {
    NSNumber *appliedMode = objc_getAssociatedObject(view, &dkxsProgressModeKey);
    if (appliedMode && appliedMode.integerValue != mode) {
        DKXSRestoreClearProgressViewState(view);
        appliedMode = nil;
    }

    if (mode == DKXSClearProgressModeNone) {
        DKXSRestoreClearProgressViewState(view);
        return;
    }

    if (!appliedMode) {
        objc_setAssociatedObject(view, &dkxsProgressModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &dkxsProgressOriginalLayerOpacityKey, @(view.layer.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (mode == DKXSClearProgressModeRemove) {
            objc_setAssociatedObject(view, &dkxsProgressOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &dkxsProgressOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    view.layer.opacity = 0.0f;
    if (mode == DKXSClearProgressModeRemove) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    }
}

void DKXSApplyFloatClearProgressStateToView(UIView *view) {
    if (!view || !DKXSIsClearProgressView(view)) {
        return;
    }
    DKXSClearProgressMode mode = dkxsHideButton.isElementsHidden ? DKXSCurrentClearProgressMode() : DKXSClearProgressModeNone;
    DKXSApplyClearProgressViewState(view, mode);
}

UIWindow *DKXSGetKeyWindow(void) {
    UIWindow *activeWindow = DKXSActiveWindow();
    if (activeWindow) {
        return activeWindow;
    }

    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}

static void forceResetAllUIElements(void) {
    DKXSPerformClearButtonMutation(^{ [dkxsHideButton restoreCachedTargetViews]; });
}
static void reapplyHidingToAllElements(DKXSHideUIButton *button) {
    if (!button || !button.isElementsHidden)
        return;
    [button hideUIElements];
}
void DKXSInitTargetClassNames(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger configuration = 0;
    configuration |= [defaults boolForKey:@"DKXSHideTabBar"] ? (1U << 0) : 0;
    configuration |= [defaults boolForKey:@"DKXSHideDanmaku"] ? (1U << 1) : 0;
    configuration |= [defaults boolForKey:@"DKXSHideSlider"] ? (1U << 2) : 0;
    configuration |= [defaults boolForKey:@"DKXSHideChapter"] ? (1U << 3) : 0;
    configuration |= [defaults boolForKey:@"DKXSHidePauseVideoIcon"] ? (1U << 4) : 0;
    if (dkxsTargetClassNames && dkxsTargetClassConfiguration == configuration) {
        return;
    }

    NSMutableArray<NSString *> *list = [@[
        @"AWEHPTopBarCTAContainer", @"AWEHPDiscoverFeedEntranceView", @"AWELeftSideBarEntranceView", @"DUXBadge", @"AWEBaseElementView", @"AWEElementStackView", @"AWEPlayInteractionDescriptionLabel",
        @"AWEUserNameLabel", @"ACCEditTagStickerView", @"AWEFeedTemplateAnchorView", @"AWESearchFeedTagView", @"AWEPlayInteractionSearchAnchorView", @"AFDRecommendToFriendTagView",
        @"AWELandscapeFeedEntryView", @"AWEFeedAnchorContainerView", @"AFDAIbumFolioView", @"DUXPopover", @"AWEMixVideoPanelMoreView", @"AWEHotSearchInnerBottomView", @"AWEHPSegmentControlScrollView"
    ] mutableCopy];
    if (configuration & (1U << 0)) {
        [list addObject:@"AWENormalModeTabBar"];
    }
    if (configuration & (1U << 1)) {
        [list addObject:@"AWEVideoPlayDanmakuContainerView"];
        [list addObject:@"AWEDanmakuContainerView"];
    }
    if (configuration & (1U << 2)) {
        [list addObject:@"AWEStoryProgressSlideView"];
        [list addObject:@"AWEStoryProgressContainerView"];
    }
    if (configuration & (1U << 3)) {
        [list addObject:@"AWEDemaciaChapterProgressSlider"];
    }
    if (configuration & (1U << 4)) {
        // 视频中央的播放/暂停图标
        [list addObject:@"AWEAwemePlayVideoPauseIcon"];
    }

    dkxsTargetClassNames = [list copy];
    dkxsTargetClassConfiguration = configuration;
    [dkxsHideButton invalidateTargetCache];
}

void DKXSReloadClearButtonConfiguration(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DKXSReloadClearButtonConfiguration();
        });
        return;
    }

    DKXSInitTargetClassNames();

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isEnabled = [defaults boolForKey:@"DKXSEnableFloatClearButton"];
    BOOL purificationEnabled = [defaults boolForKey:@"DKXSEnablePure"];
    if (!isEnabled && !purificationEnabled) {
        if (dkxsHideButton) {
            if (dkxsHideButton.isElementsHidden) {
                [dkxsHideButton safeResetState];
            }
            [dkxsHideButton removeFromSuperview];
            dkxsHideButton = nil;
        }
        return;
    }

    UIWindow *activeWindow = DKXSActiveWindow();
    if (!activeWindow) {
        return;
    }

    CGFloat buttonSize = [defaults floatForKey:@"DKXSEnableFloatClearButtonSize"];
    if (buttonSize <= 0.0) {
        buttonSize = 40.0;
    }
    buttonSize = MIN(MAX(buttonSize, 20.0), 60.0);

    if (!dkxsHideButton) {
        dkxsHideButton = [[DKXSHideUIButton alloc] initWithFrame:CGRectMake(0, 0, buttonSize, buttonSize)];
    } else if (fabs(dkxsHideButton.bounds.size.width - buttonSize) > FLT_EPSILON) {
        dkxsHideButton.bounds = CGRectMake(0, 0, buttonSize, buttonSize);
        dkxsHideButton.layer.cornerRadius = buttonSize / 2.0;
    }

    // 净化也复用同一清屏实例，按钮是否显示仍由协调器决定。
    if (!isEnabled && dkxsHideButton.manualClearActive) {
        dkxsHideButton.manualClearActive = NO;
        [dkxsHideButton updateClearState];
    }
    if (dkxsHideButton.superview) [dkxsHideButton loadSavedPosition];
    if (![dkxsHideButton isDescendantOfView:activeWindow]) {
        [activeWindow addSubview:dkxsHideButton];
        [dkxsHideButton loadSavedPosition];
    }

    [activeWindow bringSubviewToFront:dkxsHideButton];
    if (dkxsHideButton.isElementsHidden) {
        [dkxsHideButton hideUIElements];
    }
}
@implementation DKXSHideUIButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityLabel = @"DKXSClearScreenButton";
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.isElementsHidden = NO;
        self.hiddenViewsList = [NSHashTable weakObjectsHashTable];
        self.progressViews = [NSHashTable weakObjectsHashTable];
        self.classifications = [NSMapTable strongToStrongObjectsMapTable];
        self.targetNames = [NSSet setWithArray:dkxsTargetClassNames ?: @[]];
        self.needsDiscovery = YES;

        self.originalAlpha = 1.0;
        self.alpha = 0.5;
        
        [self loadLockState];
        [self loadIcons];
        [self setImage:self.showIcon forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:panGesture];
        
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(handleTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchUpOutside) forControlEvents:UIControlEventTouchUpOutside];
        
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPressGesture];
        
        [self startPeriodicCheck];
        [self resetFadeTimer];

        // 新控件先隐藏，是否显示由协调器决定
        self.hidden = YES;
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) {
        [self loadSavedPosition];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        return;
    }
    [self startPeriodicCheck];
    [self resetFadeTimer];
}

- (void)startPeriodicCheck {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                    repeats:YES
                                                      block:^(NSTimer *timer) {
                                                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                        if (!strongSelf) {
                                                            return;
                                                        }
                                                        if (strongSelf.isElementsHidden) {
                                                            [strongSelf hideUIElements];
                                                        }
                                                      }];
    self.checkTimer = timer;
}

- (void)resetFadeTimer {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         repeats:NO
                                                           block:^(NSTimer *timer) {
                                                             __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                             if (!strongSelf) {
                                                                 return;
                                                             }
                                                             [UIView animateWithDuration:0.3
                                                                              animations:^{
                                                                                strongSelf.alpha = 0.5;
                                                                              }];
                                                             strongSelf.fadeTimer = nil;
                                                           }];
    self.fadeTimer = fadeTimer;
    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
    }
}

- (void)stopTimers {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        CGFloat centerXPercent = self.center.x / self.superview.bounds.size.width;
        CGFloat centerYPercent = self.center.y / self.superview.bounds.size.height;

        [defaults setFloat:centerXPercent forKey:@"DKXSHideButtonCenterXPercent"];
        [defaults setFloat:centerYPercent forKey:@"DKXSHideButtonCenterYPercent"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGPoint targetCenter;
    if ([self dkxsHasSavedPosition]) {
        targetCenter = CGPointMake([defaults floatForKey:@"DKXSHideButtonCenterXPercent"] * self.superview.bounds.size.width,
                                   [defaults floatForKey:@"DKXSHideButtonCenterYPercent"] * self.superview.bounds.size.height);
    } else {
        targetCenter = [self dkxsDefaultCenter];
    }
    self.center = [self dkxsConstrainedCenterForProposedCenter:targetCenter];
}

- (void)saveLockState {
    [[NSUserDefaults standardUserDefaults] setBool:self.isLocked forKey:@"DKXSDKXSHideUIButtonLockState"];
}

- (void)loadLockState {
    self.isLocked = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSDKXSHideUIButtonLockState"];
}

- (void)loadIcons {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *iconPath = [documentsPath stringByAppendingPathComponent:@"DYxs/qingping.gif"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        iconPath = [documentsPath stringByAppendingPathComponent:@"DYYY/qingping.gif"];
    }
    NSData *gifData = [NSData dataWithContentsOfFile:iconPath];

    NSArray<UIImage *> *frames = nil;
    CGFloat totalDuration = 0.0;
    // 上游用 YYImage 解码 Documents 下的 qingping.gif；DYxs 不引入 YYImage，
    // 这里直接走回退分支（文字按钮），见 REPORT。
    BOOL hasFrames = NO;

    if (hasFrames && frames.count > 0) {
        UIImageView *animatedImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        animatedImageView.animationImages = frames;
        animatedImageView.animationDuration = totalDuration;
        animatedImageView.animationRepeatCount = 0;
        [self addSubview:animatedImageView];

        animatedImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [animatedImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [animatedImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [animatedImageView.widthAnchor constraintEqualToAnchor:self.widthAnchor], [animatedImageView.heightAnchor constraintEqualToAnchor:self.heightAnchor]
        ]];

        [animatedImageView startAnimating];
        return;
    }

    [self setTitle:@"隐藏" forState:UIControlStateNormal];
    [self setTitle:@"显示" forState:UIControlStateSelected];
    self.titleLabel.font = [UIFont systemFontOfSize:10];
}

- (void)handleTouchDown {
    if ([self dkxs_isInSelfHiddenState]) {
        return;
    }
    [self resetFadeTimer];
}

- (void)handleTouchUpInside {
    if ([self dkxs_isInSelfHiddenState]) {
        return;
    }
    [self resetFadeTimer];
}

- (void)handleTouchUpOutside {
    if ([self dkxs_isInSelfHiddenState]) {
        return;
    }
    [self resetFadeTimer];
}

- (UIViewController *)findViewController:(UIView *)view {
    __weak UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
        if (!responder)
            break;
    }
    return nil;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.isLocked)
        return;

    [self resetFadeTimer];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([self dkxsStickToEdgeEnabled]) {
            self.dkxsActiveDragEdge = [self dkxsNearestEdgeForPoint:self.center];
            self.center = [self dkxsCenterOnEdge:self.dkxsActiveDragEdge forPoint:self.center];
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint touchPoint = [gesture locationInView:self.superview];
        if ([self dkxsStickToEdgeEnabled]) {
            DKXSClearButtonEdge nearestEdge = [self dkxsNearestEdgeForPoint:touchPoint];
            CGFloat currentDistance = [self dkxsDistanceFromPoint:touchPoint toEdge:self.dkxsActiveDragEdge];
            CGFloat nearestDistance = [self dkxsDistanceFromPoint:touchPoint toEdge:nearestEdge];
            if (nearestEdge != self.dkxsActiveDragEdge && nearestDistance + 12.0 < currentDistance) {
                self.dkxsActiveDragEdge = nearestEdge;
            }
            self.center = [self dkxsCenterOnEdge:self.dkxsActiveDragEdge forPoint:touchPoint];
        } else {
            self.center = [self dkxsClampedCenterForProposedCenter:touchPoint];
        }
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.center = [self dkxsConstrainedCenterForProposedCenter:self.center];
        [self saveButtonPosition];
        if ([self dkxs_isInSelfHiddenState]) {
            [self dkxs_showEdgeIndicator];
        }
    }
}

- (BOOL)dkxs_shouldSelfHideOnClear {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideClearButtonOnTap"];
}

- (BOOL)dkxs_isInSelfHiddenState {
    return self.isElementsHidden && [self dkxs_shouldSelfHideOnClear];
}

- (void)dkxs_applySelfHiddenAlpha {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    // alpha 必须 > 0.01 才能继续接收 hit-test，0.02 在动态背景下几乎不可见
    self.alpha = 0.02;
    [self dkxs_showEdgeIndicator];
}

- (void)dkxs_showEdgeIndicator {
    if (!self.superview) {
        return;
    }

    CGFloat indicatorHeight = self.bounds.size.height;
    CGFloat indicatorWidth = 2.0; // 2pt 宽度
    CGFloat screenWidth = self.superview.bounds.size.width;
    CGFloat centerY = self.center.y;

    if (!self.edgeIndicatorView) {
        self.edgeIndicatorView = [[UIView alloc] init];
        self.edgeIndicatorView.backgroundColor = [UIColor blackColor];
        // 左侧两角圆弧（右侧贴屏幕边缘无弧度），模拟扣在屏幕边缘的效果
        self.edgeIndicatorView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
        self.edgeIndicatorView.layer.cornerRadius = indicatorWidth;
        self.edgeIndicatorView.layer.masksToBounds = YES;
        self.edgeIndicatorView.userInteractionEnabled = NO;
    }

    self.edgeIndicatorView.frame = CGRectMake(screenWidth - indicatorWidth,
                                              centerY - indicatorHeight / 2.0,
                                              indicatorWidth,
                                              indicatorHeight);
    self.edgeIndicatorView.layer.cornerRadius = indicatorWidth;
    self.edgeIndicatorView.alpha = 1.0;
    self.edgeIndicatorView.hidden = NO;

    if (![self.edgeIndicatorView isDescendantOfView:self.superview]) {
        [self.superview addSubview:self.edgeIndicatorView];
    }
}

- (void)dkxs_hideEdgeIndicator {
    if (self.edgeIndicatorView) {
        self.edgeIndicatorView.hidden = YES;
    }
}

// 自动净化和手动清屏分别记录意图，共用隐藏、缓存和恢复流程。
- (void)setHomePurificationActive:(BOOL)active {
    if (!NSThread.isMainThread) {
        __weak DKXSHideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.homePurificationActive = active; });
        return;
    }
    if (_homePurificationActive == active) return;
    _homePurificationActive = active;
    [self updateClearState];
}

- (void)updateClearState {
    BOOL shouldHide = self.manualClearActive || self.homePurificationActive;
    if (self.isElementsHidden == shouldHide) return;
    if (shouldHide) {
        [self hideUIElements];
        self.selected = YES;
        if ([self dkxs_shouldSelfHideOnClear]) [self dkxs_applySelfHiddenAlpha];
        DKXSRefreshStatusBarVisibility();
    } else {
        [self safeResetState];
    }
}

- (void)handleTap {
    self.manualClearActive = !self.manualClearActive;
    if (!([self dkxs_shouldSelfHideOnClear] && self.manualClearActive)) [self resetFadeTimer];
    [self updateClearState];
    [DKXSFloatingButtonCoordinator refresh];
}

- (void)restoreAWEPlayInteractionProgressContainerView {
    DKXSPerformClearButtonMutation(^{
        for (UIView *view in self.progressViews.allObjects) DKXSRestoreClearProgressViewState(view);
        [self.progressViews removeAllObjects];
    });
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];
        self.isLocked = !self.isLocked;
        [self saveLockState];
        NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
        [DKXSUtils showToast:toastMessage];
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [generator prepare];
            [generator impactOccurred];
        }
    }
}
#pragma mark - 清屏实例缓存

- (void)invalidateTargetCache {
    [self restoreCachedTargetViews];
    [self restoreAWEPlayInteractionProgressContainerView];
    [self.classifications removeAllObjects];
    self.targetNames = [NSSet setWithArray:dkxsTargetClassNames ?: @[]];
    self.needsDiscovery = YES;
}

- (NSUInteger)classificationForView:(UIView *)view {
    Class type = view.class;
    NSNumber *cached = [self.classifications objectForKey:type];
    if (cached) return cached.unsignedIntegerValue;
    NSUInteger classification = DKXSIsClearProgressView(view) ? 2 : 0;
    for (Class ancestor = type; ancestor; ancestor = class_getSuperclass(ancestor)) {
        if ([self.targetNames containsObject:NSStringFromClass(ancestor)]) { classification |= 1; break; }
    }
    if (self.classifications.count >= 512) [self.classifications removeAllObjects];
    [self.classifications setObject:@(classification) forKey:type];
    return classification;
}

- (void)applyHiddenStateToView:(UIView *)view {
    static Class entranceClass, feedClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entranceClass = NSClassFromString(@"AWELeftSideBarEntranceView");
        feedClass = NSClassFromString(@"AWEFeedContainerViewController");
    });
    if ([view isKindOfClass:entranceClass] && ![[self findViewController:view] isKindOfClass:feedClass]) return;
    DKXSApplyClearTargetViewHiddenState(view);
}

- (void)registerViewForHiding:(UIView *)view {
    if (!NSThread.isMainThread) {
        __weak UIView *weakView = view;
        __weak DKXSHideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf registerViewForHiding:weakView]; });
        return;
    }
    if (!self.isElementsHidden || !view || view == self) return;
    NSUInteger classification = [self classificationForView:view];
    DKXSPerformClearButtonMutation(^{
        if (classification & 2) {
            [self.progressViews addObject:view];
            if (view.window) DKXSApplyClearProgressViewState(view, DKXSCurrentClearProgressMode());
        }
        if (!(classification & 1)) return;
        [self.hiddenViewsList addObject:view];
        // init 时先弱引用登记；预加载视图进入窗口后再应用，避免依赖子类是否调用 super。
        if (view.window) [self applyHiddenStateToView:view];
    });
}

- (void)restoreCachedTargetViews {
    DKXSPerformClearButtonMutation(^{
        for (UIView *view in self.hiddenViewsList.allObjects) {
            DKXSRestoreClearTargetViewStateIfNeeded(view);
        }
        [self.hiddenViewsList removeAllObjects];
        self.needsDiscovery = YES;
    });
}

- (void)applyCachedHiding {
    if (!self.isElementsHidden) return;
    DKXSPerformClearButtonMutation(^{
        for (UIView *view in self.hiddenViewsList.allObjects) if (view.window) [self applyHiddenStateToView:view];
        for (UIView *view in self.progressViews.allObjects) if (view.window) DKXSApplyClearProgressViewState(view, DKXSCurrentClearProgressMode());
        if (self.superview && self.superview.subviews.lastObject != self) [self.superview bringSubviewToFront:self];
    });
}

- (void)hideUIElements {
    if (!NSThread.isMainThread) {
        __weak DKXSHideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf hideUIElements]; });
        return;
    }
    DKXSInitTargetClassNames();
    BOOL entering = !self.isElementsHidden;
    self.isElementsHidden = YES;
    if (self.needsDiscovery) {
        self.needsDiscovery = NO;
        [self findAndHideViews:dkxsTargetClassNames];
    }
    if (entering) { [self applyCachedHiding]; return; }
    if (self.refreshScheduled) return;
    self.refreshScheduled = YES;
    __weak DKXSHideUIButton *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DKXSHideUIButton *button = weakSelf;
        button.refreshScheduled = NO;
        [button applyCachedHiding];
    });
}

- (void)findAndHideViews:(NSArray *)classNames {
    // 仅在进入清屏或配置改变后发现一次；后续刷新只访问弱引用实例缓存。
    NSMutableArray<UIView *> *pending = [UIApplication.sharedApplication.windows mutableCopy];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [self registerViewForHiding:view];
        [pending addObjectsFromArray:view.subviews];
    }
}

- (void)safeResetState {
    self.manualClearActive = NO;
    _homePurificationActive = NO;
    self.isElementsHidden = NO;
    forceResetAllUIElements();
    [self restoreAWEPlayInteractionProgressContainerView];
    [self.hiddenViewsList removeAllObjects];
    self.selected = NO;

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }

    // 切场景/重置状态时，确保按钮自隐藏 alpha 也被恢复，避免按钮一直处于近乎透明的状态
    if (self.alpha < 0.1) {
        self.alpha = self.originalAlpha;
        [self resetFadeTimer];
    }
    [self dkxs_hideEdgeIndicator];

    // 清屏隐藏状态栏：触发系统重新评估状态栏显隐
    DKXSRefreshStatusBarVisibility();
    [DKXSFloatingButtonCoordinator refresh];
}
- (void)dealloc {
    [self stopTimers];
    [self.edgeIndicatorView removeFromSuperview];
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
    CGFloat halfWidth = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat halfHeight = CGRectGetHeight(self.bounds) * 0.5;
    *leftX = halfWidth + kDKXSClearButtonEdgeInset;
    *rightX = size.width - halfWidth - kDKXSClearButtonEdgeInset;
    *topY = halfHeight + kDKXSClearButtonEdgeInset;
    *bottomY = size.height - halfHeight - kDKXSClearButtonEdgeInset;
    *minX = halfWidth + kDKXSClearButtonEdgeInset;
    *maxX = size.width - halfWidth - kDKXSClearButtonEdgeInset;
    *minY = halfHeight + kDKXSClearButtonEdgeInset;
    *maxY = size.height - halfHeight - kDKXSClearButtonEdgeInset;
    return YES;
}

- (CGFloat)dkxsDistanceFromPoint:(CGPoint)point toEdge:(DKXSClearButtonEdge)edge {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dkxsEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return CGFLOAT_MAX;
    }

    switch (edge) {
        case DKXSClearButtonEdgeLeft:
            return fabs(point.x - leftX);
        case DKXSClearButtonEdgeRight:
            return fabs(point.x - rightX);
        case DKXSClearButtonEdgeTop:
            return fabs(point.y - topY);
        case DKXSClearButtonEdgeBottom:
            return fabs(point.y - bottomY);
    }
}

- (DKXSClearButtonEdge)dkxsNearestEdgeForPoint:(CGPoint)point {
    DKXSClearButtonEdge edge = DKXSClearButtonEdgeLeft;
    CGFloat minDistance = [self dkxsDistanceFromPoint:point toEdge:edge];
    for (NSInteger rawEdge = DKXSClearButtonEdgeRight; rawEdge <= DKXSClearButtonEdgeBottom; rawEdge++) {
        DKXSClearButtonEdge candidate = (DKXSClearButtonEdge)rawEdge;
        CGFloat distance = [self dkxsDistanceFromPoint:point toEdge:candidate];
        if (distance < minDistance) {
            minDistance = distance;
            edge = candidate;
        }
    }
    return edge;
}

- (CGPoint)dkxsCenterOnEdge:(DKXSClearButtonEdge)edge forPoint:(CGPoint)point {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dkxsEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return point;
    }

    switch (edge) {
        case DKXSClearButtonEdgeLeft:
            return CGPointMake(leftX, MIN(MAX(point.y, minY), maxY));
        case DKXSClearButtonEdgeRight:
            return CGPointMake(rightX, MIN(MAX(point.y, minY), maxY));
        case DKXSClearButtonEdgeTop:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), topY);
        case DKXSClearButtonEdgeBottom:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), bottomY);
    }
}

- (CGPoint)dkxsSnappedCenterForProposedCenter:(CGPoint)center {
    return [self dkxsCenterOnEdge:[self dkxsNearestEdgeForPoint:center] forPoint:center];
}

- (CGPoint)dkxsClampedCenterForProposedCenter:(CGPoint)center {
    CGFloat minX, maxX, minY, maxY;
    CGFloat unusedLeft, unusedRight, unusedTop, unusedBottom;
    if (![self dkxsEdgeMetricsWithLeftX:&unusedLeft rightX:&unusedRight topY:&unusedTop bottomY:&unusedBottom minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return center;
    }
    return CGPointMake(MIN(MAX(center.x, minX), maxX), MIN(MAX(center.y, minY), maxY));
}

- (BOOL)dkxsStickToEdgeEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSClearButtonStickToEdge"];
}

- (CGPoint)dkxsConstrainedCenterForProposedCenter:(CGPoint)center {
    if ([self dkxsStickToEdgeEnabled]) {
        return [self dkxsSnappedCenterForProposedCenter:center];
    }
    return [self dkxsClampedCenterForProposedCenter:center];
}

- (BOOL)dkxsHasSavedPosition {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"DKXSHideButtonCenterXPercent"] != nil &&
           [defaults objectForKey:@"DKXSHideButtonCenterYPercent"] != nil;
}

- (CGPoint)dkxsDefaultCenter {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dkxsEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return self.center;
    }
    CGFloat defaultY = MIN(MAX(self.superview.bounds.size.height * (1.0 - kDKXSClearButtonDefaultYFromBottomPercent), minY), maxY);
    return CGPointMake(rightX, defaultY);
}

- (void)resetToDefaultPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"DKXSHideButtonCenterXPercent"];
    [defaults removeObjectForKey:@"DKXSHideButtonCenterYPercent"];
    self.center = [self dkxsDefaultCenter];
    [self resetFadeTimer];
}

@end
