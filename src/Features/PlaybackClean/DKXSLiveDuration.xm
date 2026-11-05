//
//  DKXSLiveDuration.xm
//  DYxs 全量合并第 5 批剩余部分（5b）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 6379-7100 行（开播时长子系统：可拖动时长
//  悬浮窗 + 1 秒 ticker + 位置持久化 + 三处安装点），符号一律 DYYY* -> DKXS*。
//  与上游的差异：DYYYUtils 的 toast / 取 VC 两个调用改走 DYxs 已有的 DKXSUtils
//  同名方法；位置存取键改为 DKXSShowLiveDuration* 系（值键，不登记开关）。
//  DYxs 现有代码未 hook 本文件涉及的三个类，无方法撞点。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import "DKXSUtils.h"
#import "DY778LiveInfo.h"


static const void *kDKXSLiveDurationViewKey = &kDKXSLiveDurationViewKey;
static const void *kDKXSLiveDurationTimerKey = &kDKXSLiveDurationTimerKey;
static const void *kDKXSLiveDurationRoomKey = &kDKXSLiveDurationRoomKey;
// DY778 1.0-3（LiveClock）网络兜底的状态：联网取到的开播时间及取数节流。
static const void *kDKXSLiveDurationFetchedStartKey = &kDKXSLiveDurationFetchedStartKey;
static const void *kDKXSLiveDurationFetchedRoomIDKey = &kDKXSLiveDurationFetchedRoomIDKey;
static const void *kDKXSLiveDurationRoomIDKey = &kDKXSLiveDurationRoomIDKey;
static const void *kDKXSLiveDurationFetchActiveKey = &kDKXSLiveDurationFetchActiveKey;
static const void *kDKXSLiveDurationFetchAttemptsKey = &kDKXSLiveDurationFetchAttemptsKey;
static const void *kDKXSLiveDurationFetchLastKey = &kDKXSLiveDurationFetchLastKey;
static NSString *const kDKXSLiveDurationCenterXPercentKey = @"DKXSLiveDurationCenterXPercent";
static NSString *const kDKXSLiveDurationCenterYPercentKey = @"DKXSLiveDurationCenterYPercent";
static NSString *const kDKXSLiveDurationPositionLockedKey = @"DKXSLiveDurationPositionLocked";

static UIEdgeInsets DKXSLiveDurationSafeInsets(UIView *root) {
    return [root respondsToSelector:@selector(safeAreaInsets)] ? root.safeAreaInsets : UIEdgeInsetsZero;
}

static CGPoint DKXSLiveDurationClampedCenter(CGPoint center, CGSize viewSize, UIView *root) {
    if (!root) {
        return center;
    }

    UIEdgeInsets safeInsets = DKXSLiveDurationSafeInsets(root);
    CGFloat halfWidth = viewSize.width / 2.0;
    CGFloat halfHeight = viewSize.height / 2.0;
    CGFloat minX = safeInsets.left + halfWidth + 4.0;
    CGFloat maxX = fmax(minX, CGRectGetWidth(root.bounds) - safeInsets.right - halfWidth - 4.0);
    CGFloat minY = safeInsets.top + halfHeight + 4.0;
    CGFloat maxY = fmax(minY, CGRectGetHeight(root.bounds) - safeInsets.bottom - halfHeight - 4.0);
    return CGPointMake(fmin(fmax(center.x, minX), maxX), fmin(fmax(center.y, minY), maxY));
}

@interface DKXSLiveDurationWeakViewBox : NSObject
@property(nonatomic, weak) UIView *view;
@end

@implementation DKXSLiveDurationWeakViewBox
@end

@interface DKXSLiveDurationView : UIView
@property(nonatomic, strong) UILabel *durationLabel;
@property(nonatomic, assign, getter=isDragging) BOOL dragging;
@property(nonatomic, assign, getter=isMovementLocked) BOOL movementLocked;
- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root;
@end

@implementation DKXSLiveDurationView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.42];
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
        self.layer.borderWidth = 0.5;
        self.accessibilityIdentifier = @"dyyy_live_duration_view";

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        _durationLabel.adjustsFontSizeToFitWidth = YES;
        _durationLabel.minimumScaleFactor = 0.75;
        _durationLabel.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        _durationLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_durationLabel];

        _movementLocked = [[NSUserDefaults standardUserDefaults] boolForKey:kDKXSLiveDurationPositionLockedKey];

        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];

        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [panGesture requireGestureRecognizerToFail:longPressGesture];
        [self addGestureRecognizer:panGesture];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.durationLabel.frame = CGRectInset(self.bounds, 7.0, 2.0);
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *root = self.superview;
    if (self.isMovementLocked || !root) {
        return;
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.alpha = 0.8;
    }

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:root];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        self.center = DKXSLiveDurationClampedCenter(newCenter, self.bounds.size, root);
        [gesture setTranslation:CGPointZero inView:root];
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.alpha = 1.0;
        [self savePosition];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    self.movementLocked = !self.isMovementLocked;
    [[NSUserDefaults standardUserDefaults] setBool:self.isMovementLocked forKey:kDKXSLiveDurationPositionLockedKey];
    if (self.isMovementLocked) {
        [self savePosition];
    }

    [DKXSUtils showToast:self.isMovementLocked ? @"开播时长位置已锁定" : @"开播时长位置已解锁"];
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }
}

- (void)savePosition {
    UIView *root = self.superview;
    if (!root) {
        return;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:self.center.x / rootWidth forKey:kDKXSLiveDurationCenterXPercentKey];
    [defaults setDouble:self.center.y / rootHeight forKey:kDKXSLiveDurationCenterYPercentKey];
}

- (CGRect)frameByApplyingSavedPositionToFrame:(CGRect)frame inRoot:(UIView *)root {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kDKXSLiveDurationCenterXPercentKey] || ![defaults objectForKey:kDKXSLiveDurationCenterYPercentKey]) {
        return frame;
    }

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth <= 0.0 || rootHeight <= 0.0) {
        return frame;
    }

    CGFloat centerXPercent = fmin(fmax([defaults doubleForKey:kDKXSLiveDurationCenterXPercentKey], 0.0), 1.0);
    CGFloat centerYPercent = fmin(fmax([defaults doubleForKey:kDKXSLiveDurationCenterYPercentKey], 0.0), 1.0);
    CGPoint center = CGPointMake(centerXPercent * rootWidth, centerYPercent * rootHeight);
    center = DKXSLiveDurationClampedCenter(center, frame.size, root);
    return CGRectIntegral(CGRectMake(center.x - frame.size.width / 2.0, center.y - frame.size.height / 2.0, frame.size.width, frame.size.height));
}

@end

static id DKXSLiveDurationSafeValue(id obj, NSString *key) {
    if (!obj || key.length == 0) {
        return nil;
    }

    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static long long DKXSLiveDurationLongValue(id obj, NSString *key) {
    id value = DKXSLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

static BOOL DKXSLiveDurationBoolValue(id obj, NSString *key) {
    id value = DKXSLiveDurationSafeValue(obj, key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSTimeInterval DKXSLiveDurationNowSeconds(void) {
    return [[NSDate date] timeIntervalSince1970];
}

static NSTimeInterval DKXSLiveDurationNormalizeTimestamp(long long timestamp) {
    if (timestamp <= 0) {
        return 0.0;
    }
    return timestamp > 20000000000LL ? ((NSTimeInterval)timestamp / 1000.0) : (NSTimeInterval)timestamp;
}

static long long DKXSLiveDurationFirstPositiveValue(id obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        long long value = DKXSLiveDurationLongValue(obj, key);
        if (value > 0) {
            return value;
        }
    }
    return 0;
}

static BOOL DKXSLiveDurationLooksLikeRoomObject(id obj) {
    if (!obj) {
        return NO;
    }

    NSString *className = NSStringFromClass([obj class]);
    NSArray<NSString *> *excludedParts = @[ @"Cell", @"Item", @"Aisle", @"Context", @"Config", @"Controller", @"View", @"Factory" ];
    for (NSString *part in excludedParts) {
        if ([className rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return NO;
        }
    }

    if ([className rangeOfString:@"LiveRoom" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"RoomModel" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [className rangeOfString:@"WebcastRoom" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return DKXSLiveDurationSafeValue(obj, @"roomID") || DKXSLiveDurationSafeValue(obj, @"idStr");
}

static NSTimeInterval DKXSLiveDurationElapsedSeconds(id roomModel) {
    if (!DKXSLiveDurationLooksLikeRoomObject(roomModel)) {
        return -1.0;
    }

    id rawRoom = DKXSLiveDurationSafeValue(roomModel, @"rawRoom") ?: roomModel;
    NSArray<NSString *> *startKeys = @[ @"startTime", @"createTime", @"liveStartTime", @"start_time", @"create_time" ];
    long long startTime = DKXSLiveDurationFirstPositiveValue(rawRoom, startKeys);
    if (startTime <= 0) {
        startTime = DKXSLiveDurationFirstPositiveValue(roomModel, startKeys);
    }

    NSTimeInterval timestamp = DKXSLiveDurationNormalizeTimestamp(startTime);
    NSTimeInterval now = DKXSLiveDurationNowSeconds();
    if (timestamp > 1000000000.0 && timestamp <= now + 3600.0) {
        return fmax(0.0, now - timestamp);
    }

    NSArray<NSString *> *durationKeys = @[ @"liveDuration", @"liveTime", @"duration", @"totalDuration" ];
    long long duration = DKXSLiveDurationFirstPositiveValue(rawRoom, durationKeys);
    if (duration <= 0) {
        duration = DKXSLiveDurationFirstPositiveValue(roomModel, durationKeys);
    }
    if (duration > 0 && duration < 365LL * 24LL * 3600LL) {
        return (NSTimeInterval)duration;
    }

    return -1.0;
}

static BOOL DKXSLiveDurationHasValidLiveTime(id obj) {
    return DKXSLiveDurationElapsedSeconds(obj) >= 0.0;
}

static id DKXSLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth);

static id DKXSLiveDurationRoomFromKnownKeys(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    NSArray<NSString *> *keys = @[
        @"rawHTSLiveRoomModel", @"rawDataRoomModel", @"roomModel", @"rawRoom", @"liveRoom", @"room", @"currentRoom",
        @"containerContext", @"roomDI", @"roomConfig", @"roomAisle"
    ];
    for (NSString *key in keys) {
        id value = DKXSLiveDurationSafeValue(obj, key);
        if (DKXSLiveDurationHasValidLiveTime(value)) {
            return value;
        }

        id nestedRawRoom = DKXSLiveDurationSafeValue(value, @"rawRoom");
        if (DKXSLiveDurationHasValidLiveTime(nestedRawRoom)) {
            return value;
        }

        id nestedRoom = DKXSLiveDurationRoomFromCarrierDepth(value, depth + 1);
        if (nestedRoom) {
            return nestedRoom;
        }
    }
    return nil;
}

static id DKXSLiveDurationRoomFromCarrierDepth(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    if (DKXSLiveDurationHasValidLiveTime(obj)) {
        return obj;
    }

    id room = DKXSLiveDurationRoomFromKnownKeys(obj, depth + 1);
    if (room) {
        return room;
    }

    if ([obj respondsToSelector:@selector(liveRoomModel)]) {
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(liveRoomModel));
            if (DKXSLiveDurationHasValidLiveTime(value)) {
                return value;
            }
        } @catch (__unused NSException *exception) {
        }
    }

    NSArray<NSString *> *carrierKeys = @[ @"itemModel", @"awemeModel", @"aweme", @"model", @"item" ];
    for (NSString *key in carrierKeys) {
        id carrier = DKXSLiveDurationSafeValue(obj, key);
        room = DKXSLiveDurationRoomFromCarrierDepth(carrier, depth + 1);
        if (room) {
            return room;
        }
    }

    return nil;
}

static id DKXSLiveDurationRoomFromCarrier(id obj) {
    return DKXSLiveDurationRoomFromCarrierDepth(obj, 0);
}

static NSString *DKXSLiveDurationFormatElapsed(NSTimeInterval seconds) {
    long long totalSeconds = (long long)fmax(0.0, floor(seconds));
    long long days = totalSeconds / 86400;
    long long hours = (totalSeconds % 86400) / 3600;
    long long minutes = (totalSeconds % 3600) / 60;
    long long secs = totalSeconds % 60;

    if (days > 0) {
        return [NSString stringWithFormat:@"已开播 %lld天%02lld:%02lld:%02lld", days, hours, minutes, secs];
    }
    return [NSString stringWithFormat:@"已开播 %02lld:%02lld:%02lld", hours, minutes, secs];
}

static DKXSLiveDurationView *DKXSLiveDurationEnsureView(UIView *root) {
    DKXSLiveDurationView *durationView = objc_getAssociatedObject(root, kDKXSLiveDurationViewKey);
    if (durationView && durationView.superview == root) {
        return durationView;
    }

    durationView = [[DKXSLiveDurationView alloc] initWithFrame:CGRectZero];
    objc_setAssociatedObject(root, kDKXSLiveDurationViewKey, durationView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [root addSubview:durationView];
    return durationView;
}

static CGRect DKXSLiveDurationFrameForRoot(UIView *root, id roomModel, NSString *text) {
    UIEdgeInsets safeInsets = DKXSLiveDurationSafeInsets(root);

    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    BOOL isLandscape = rootWidth > rootHeight || DKXSLiveDurationBoolValue(roomModel, @"isLandscape");
    if (!isLandscape) {
        long long orientation = DKXSLiveDurationLongValue(roomModel, @"orientation");
        isLandscape = orientation == 2 || orientation == 90 || orientation == 270;
    }

    UIFont *font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    CGSize textSize = [text ?: @"已开播 00:00:00" sizeWithAttributes:@{NSFontAttributeName : font}];
    CGFloat width = fmin(ceil(fmax(textSize.width + 18.0, 118.0)), isLandscape ? 190.0 : 170.0);
    CGFloat height = 26.0;

    CGFloat minX = safeInsets.left + 4.0;
    CGFloat maxX = fmax(minX, rootWidth - safeInsets.right - width - 4.0);
    CGFloat minY = safeInsets.top + 4.0;
    CGFloat maxY = fmax(minY, rootHeight - safeInsets.bottom - height - 4.0);

    CGFloat x = fmin(fmax(safeInsets.left + 12.0, minX), maxX);
    CGFloat y = fmin(fmax(safeInsets.top + (isLandscape ? 12.0 : 86.0), minY), maxY);
    return CGRectIntegral(CGRectMake(x, y, width, height));
}

static void DKXSLiveDurationRemoveFromView(UIView *root) {
    if (!root) {
        return;
    }

    NSTimer *timer = objc_getAssociatedObject(root, kDKXSLiveDurationTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(root, kDKXSLiveDurationTimerKey, nil, OBJC_ASSOCIATION_ASSIGN);

    UIView *durationView = objc_getAssociatedObject(root, kDKXSLiveDurationViewKey);
    [durationView removeFromSuperview];
    objc_setAssociatedObject(root, kDKXSLiveDurationViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationRoomKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchedStartKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchedRoomIDKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationRoomIDKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchActiveKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchAttemptsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchLastKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DKXSLiveDurationFetchStart(UIView *root, id roomModel);

static void DKXSLiveDurationUpdateView(UIView *root) {
    if (!root) {
        return;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSShowLiveDuration"]) {
        DKXSLiveDurationRemoveFromView(root);
        return;
    }

    id roomModel = objc_getAssociatedObject(root, kDKXSLiveDurationRoomKey);
    NSTimeInterval elapsed = DKXSLiveDurationElapsedSeconds(roomModel);
    if (elapsed < 0.0) {
        // DY778 1.0-3（LiveClock）网络兜底：本地模型无开播时间时，用上次联网
        // 取到的开播时间；没有则发起一次联网取数（见 DKXSLiveDurationFetchStart）。
        NSString *roomID = DY778LiveRoomIdentifier(roomModel);
        NSNumber *fetchedStart = objc_getAssociatedObject(root, kDKXSLiveDurationFetchedStartKey);
        NSString *fetchedRoomID = objc_getAssociatedObject(root, kDKXSLiveDurationFetchedRoomIDKey);
        if (roomID.length && fetchedStart && [fetchedRoomID isEqualToString:roomID]) {
            elapsed = fmax(0.0, DKXSLiveDurationNowSeconds() - fetchedStart.doubleValue);
        }
    }
    DKXSLiveDurationView *durationView = objc_getAssociatedObject(root, kDKXSLiveDurationViewKey);
    if (elapsed < 0.0) {
        durationView.hidden = YES;
        DKXSLiveDurationFetchStart(root, roomModel);
        return;
    }

    NSString *text = DKXSLiveDurationFormatElapsed(elapsed);
    durationView = DKXSLiveDurationEnsureView(root);
    durationView.durationLabel.text = text;
    if (!durationView.isDragging) {
        CGRect defaultFrame = DKXSLiveDurationFrameForRoot(root, roomModel, text);
        durationView.frame = [durationView frameByApplyingSavedPositionToFrame:defaultFrame inRoot:root];
        durationView.alpha = 1.0;
    }
    durationView.hidden = NO;
    [root bringSubviewToFront:durationView];
}

// DY778 1.0-3（LiveClock）网络兜底：本地房间模型取不到开播时间时，用
// HTSLiveRoomAPI 联网取一次（最多 3 次、间隔 ≥10 秒、8 秒超时），
// 用 DY778LiveRoomStart 从返回里解析开播时间。接口可用性先按
// DY778LiveRoomAPIAvailable 做签名校验，39.6.0 上不存在时直接跳过。
static void DKXSLiveDurationFetchStart(UIView *root, id roomModel) {
    if (!root || !roomModel) {
        return;
    }

    NSString *roomID = DY778LiveRoomIdentifier(roomModel);
    if (!roomID.length) {
        return;
    }
    if ([objc_getAssociatedObject(root, kDKXSLiveDurationFetchActiveKey) boolValue]) {
        return;
    }
    NSUInteger attempts = [objc_getAssociatedObject(root, kDKXSLiveDurationFetchAttemptsKey) unsignedIntegerValue];
    if (attempts >= 3) {
        return;
    }
    NSNumber *lastRequest = objc_getAssociatedObject(root, kDKXSLiveDurationFetchLastKey);
    if (lastRequest && CACurrentMediaTime() - lastRequest.doubleValue < 10.0) {
        return;
    }

    Class apiClass = NSClassFromString(@"HTSLiveRoomAPI");
    if (!DY778LiveRoomAPIAvailable(apiClass)) {
        return;
    }
    NSNumber *roomNumber = @(roomID.longLongValue);
    if (roomNumber.longLongValue <= 0) {
        return;
    }
    id api = ((id (*)(id, SEL))objc_msgSend)((id)apiClass, @selector(alloc));
    api = ((id (*)(id, SEL, id))objc_msgSend)(api, @selector(initWithRoomID:), roomNumber);
    if (!api) {
        return;
    }

    objc_setAssociatedObject(root, kDKXSLiveDurationFetchActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchAttemptsKey, @(attempts + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(root, kDKXSLiveDurationFetchLastKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak UIView *weakRoot = root;
    void (^completion)(id, id) = ^(id first, id second) {
      dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongRoot = weakRoot;
        if (!strongRoot) {
            return;
        }
        objc_setAssociatedObject(strongRoot, kDKXSLiveDurationFetchActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *currentRoomID = objc_getAssociatedObject(strongRoot, kDKXSLiveDurationRoomIDKey);
        if (![currentRoomID isEqualToString:roomID]) {
            return;
        }
        double start = DY778LiveRoomStart(first, roomID, 0);
        if (!start) {
            start = DY778LiveRoomStart(second, roomID, 0);
        }
        if (start > 0.0) {
            objc_setAssociatedObject(strongRoot, kDKXSLiveDurationFetchedStartKey, @(start), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(strongRoot, kDKXSLiveDurationFetchedRoomIDKey, roomID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        DKXSLiveDurationUpdateView(strongRoot);
      });
    };
    ((void (*)(id, SEL, id, id))objc_msgSend)(api, @selector(fetchRoomInfoWithRoomID:completion:), roomNumber, (id)completion);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIView *strongRoot = weakRoot;
      if (!strongRoot) {
          return;
      }
      NSString *currentRoomID = objc_getAssociatedObject(strongRoot, kDKXSLiveDurationRoomIDKey);
      if ([currentRoomID isEqualToString:roomID] && [objc_getAssociatedObject(strongRoot, kDKXSLiveDurationFetchActiveKey) boolValue]) {
          objc_setAssociatedObject(strongRoot, kDKXSLiveDurationFetchActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          DKXSLiveDurationUpdateView(strongRoot);
      }
    });
}

// 与 DKXSLiveDurationRoomFromCarrier 相同的载体键走查，但只要求对象带房间 ID
// （不要求本地模型已有开播时间），供网络兜底取房间 ID。
static id DKXSLiveDurationRoomByIdentifierFromCarrierDepth(id obj, NSUInteger depth) {
    if (!obj || depth > 3) {
        return nil;
    }

    if ([DY778LiveRoomIdentifier(obj) length]) {
        return obj;
    }

    NSArray<NSString *> *keys = @[
        @"rawHTSLiveRoomModel", @"rawDataRoomModel", @"roomModel", @"rawRoom", @"liveRoom", @"room", @"currentRoom",
        @"containerContext", @"roomDI", @"roomConfig", @"roomAisle"
    ];
    for (NSString *key in keys) {
        id value = DKXSLiveDurationSafeValue(obj, key);
        if (!value || value == obj) {
            continue;
        }
        id found = DKXSLiveDurationRoomByIdentifierFromCarrierDepth(value, depth + 1);
        if (found) {
            return found;
        }
    }

    NSArray<NSString *> *carrierKeys = @[ @"itemModel", @"awemeModel", @"aweme", @"model", @"item" ];
    for (NSString *key in carrierKeys) {
        id found = DKXSLiveDurationRoomByIdentifierFromCarrierDepth(DKXSLiveDurationSafeValue(obj, key), depth + 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

@interface DKXSLiveDurationTicker : NSObject
+ (instancetype)sharedTicker;
- (void)tick:(NSTimer *)timer;
@end

@implementation DKXSLiveDurationTicker

+ (instancetype)sharedTicker {
    static DKXSLiveDurationTicker *ticker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      ticker = [DKXSLiveDurationTicker new];
    });
    return ticker;
}

- (void)tick:(NSTimer *)timer {
    DKXSLiveDurationWeakViewBox *box = (DKXSLiveDurationWeakViewBox *)timer.userInfo;
    UIView *root = box.view;
    if (![root isKindOfClass:[UIView class]]) {
        [timer invalidate];
        return;
    }
    if (!root.window) {
        DKXSLiveDurationRemoveFromView(root);
        return;
    }
    DKXSLiveDurationUpdateView(root);
}

@end

static void DKXSLiveDurationEnsureTimer(UIView *root) {
    NSTimer *timer = objc_getAssociatedObject(root, kDKXSLiveDurationTimerKey);
    if (timer && timer.isValid) {
        return;
    }

    DKXSLiveDurationWeakViewBox *box = [DKXSLiveDurationWeakViewBox new];
    box.view = root;
    timer = [NSTimer timerWithTimeInterval:1.0 target:[DKXSLiveDurationTicker sharedTicker] selector:@selector(tick:) userInfo:box repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(root, kDKXSLiveDurationTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKXSLiveDurationInstallOnView(UIView *root, id carrier) {
    if (!root) {
        return;
    }

    void (^installBlock)(void) = ^{
      if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSShowLiveDuration"]) {
          DKXSLiveDurationRemoveFromView(root);
          return;
      }

      id room = DKXSLiveDurationRoomFromCarrier(carrier);
      if (!DKXSLiveDurationHasValidLiveTime(room)) {
          UIViewController *viewController = [DKXSUtils firstAvailableViewControllerFromView:root];
          room = DKXSLiveDurationRoomFromCarrier(viewController);
      }
      if (!DKXSLiveDurationHasValidLiveTime(room)) {
          // DY778 1.0-3 补件：本地模型没有开播时间时，退而取带房间 ID 的模型，
          // 走 HTSLiveRoomAPI 网络兜底（见 DKXSLiveDurationFetchStart）。
          id roomByID = DKXSLiveDurationRoomByIdentifierFromCarrierDepth(carrier, 0);
          if (!roomByID) {
              UIViewController *viewController = [DKXSUtils firstAvailableViewControllerFromView:root];
              roomByID = DKXSLiveDurationRoomByIdentifierFromCarrierDepth(viewController, 0);
          }
          if (roomByID) {
              room = roomByID;
          }
      }

      if (room) {
          NSString *previousRoomID = objc_getAssociatedObject(root, kDKXSLiveDurationRoomIDKey);
          NSString *roomID = DY778LiveRoomIdentifier(room);
          objc_setAssociatedObject(root, kDKXSLiveDurationRoomKey, room, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          if (roomID.length && ![roomID isEqualToString:previousRoomID]) {
              objc_setAssociatedObject(root, kDKXSLiveDurationRoomIDKey, roomID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              objc_setAssociatedObject(root, kDKXSLiveDurationFetchedStartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              objc_setAssociatedObject(root, kDKXSLiveDurationFetchedRoomIDKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              objc_setAssociatedObject(root, kDKXSLiveDurationFetchAttemptsKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              objc_setAssociatedObject(root, kDKXSLiveDurationFetchActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              objc_setAssociatedObject(root, kDKXSLiveDurationFetchLastKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
      }

      DKXSLiveDurationUpdateView(root);
      if (DKXSLiveDurationHasValidLiveTime(objc_getAssociatedObject(root, kDKXSLiveDurationRoomKey)) ||
          [DY778LiveRoomIdentifier(objc_getAssociatedObject(root, kDKXSLiveDurationRoomKey)) length]) {
          DKXSLiveDurationEnsureTimer(root);
      }
    };

    if ([NSThread isMainThread]) {
        installBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), installBlock);
    }
}

static UIViewController *DKXSLiveDurationContainerAudienceVC(id container) {
    UIViewController *viewController = DKXSLiveDurationSafeValue(container, @"audienceVC");
    if (![viewController isKindOfClass:[UIViewController class]] && [container respondsToSelector:@selector(audienceViewController)]) {
        @try {
            viewController = ((id (*)(id, SEL))objc_msgSend)(container, @selector(audienceViewController));
        } @catch (__unused NSException *exception) {
            viewController = nil;
        }
    }
    return [viewController isKindOfClass:[UIViewController class]] ? viewController : nil;
}

static void DKXSLiveDurationInstallFromContainer(id container) {
    UIViewController *viewController = DKXSLiveDurationContainerAudienceVC(container);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationInstallOnView(viewController.view, DKXSLiveDurationSafeValue(container, @"roomModel") ?: container);
    }
}

static void DKXSLiveDurationInstallFromAudienceWrapper(id wrapper) {
    UIViewController *viewController = DKXSLiveDurationSafeValue(wrapper, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationInstallOnView(viewController.view, DKXSLiveDurationSafeValue(wrapper, @"roomModel") ?: wrapper);
    }
}

static void DKXSLiveDurationInstallFromInnerFeedCell(id cell) {
    UIViewController *viewController = DKXSLiveDurationSafeValue(cell, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationInstallOnView(viewController.view, cell);
    }
}

%hook AWELiveAudienceContainerController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel config:(id)config {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (id)initWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakResult);
    });
    return result;
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DKXSLiveDurationInstallFromContainer(self);
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DKXSLiveDurationInstallFromContainer(self);
}

- (void)createAudienceViewController:(id)arg beginTime:(double)beginTime {
    %orig;
    __weak id weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakSelf);
    });
}

- (id)audienceControllerWithRoom:(id)room beginTime:(double)beginTime {
    id result = %orig;
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromContainer(weakSelf);
    });
    return result;
}

- (void)updateWithRoomModel:(id)roomModel config:(id)config {
    %orig;
    DKXSLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context {
    %orig;
    DKXSLiveDurationInstallFromContainer(self);
}

- (void)updateWithRoomModel:(id)roomModel context:(id)context player:(id)player {
    %orig;
    DKXSLiveDurationInstallFromContainer(self);
}

- (void)clearAudience {
    UIViewController *viewController = DKXSLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)prepareForReuse {
    UIViewController *viewController = DKXSLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DKXSLiveDurationContainerAudienceVC(self);
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook AWELiveAudienceViewController

- (id)initWithRoomModel:(id)roomModel {
    id result = %orig;
    __weak id weakResult = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      DKXSLiveDurationInstallFromAudienceWrapper(weakResult);
    });
    return result;
}

- (void)setRoomModel:(id)roomModel {
    %orig;
    DKXSLiveDurationInstallFromAudienceWrapper(self);
}

- (void)setAudienceViewController:(UIViewController *)audienceViewController {
    %orig;
    DKXSLiveDurationInstallFromAudienceWrapper(self);
}

- (void)attachAudienceViewControllerDelegate:(id)delegate {
    %orig;
    DKXSLiveDurationInstallFromAudienceWrapper(self);
}

- (void)exitLiveRoomWithType:(unsigned long long)type {
    UIViewController *viewController = DKXSLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

- (void)dealloc {
    UIViewController *viewController = DKXSLiveDurationSafeValue(self, @"audienceViewController");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end

%hook IESLiveInnerFeedLiveRoomCell

- (void)setItemModel:(id)itemModel {
    %orig;
    DKXSLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setRoomAisle:(id)roomAisle {
    %orig;
    DKXSLiveDurationInstallFromInnerFeedCell(self);
}

- (void)setAudienceVC:(UIViewController *)audienceVC {
    %orig;
    DKXSLiveDurationInstallFromInnerFeedCell(self);
}

- (void)updateWithItemModel:(id)itemModel {
    %orig;
    DKXSLiveDurationInstallFromInnerFeedCell(self);
}

- (void)prepareForReuse {
    UIViewController *viewController = DKXSLiveDurationSafeValue(self, @"audienceVC");
    if ([viewController isKindOfClass:[UIViewController class]]) {
        DKXSLiveDurationRemoveFromView(viewController.view);
    }
    %orig;
}

%end
