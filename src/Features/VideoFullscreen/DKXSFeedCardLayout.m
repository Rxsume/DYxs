// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFeedCardLayout.m 的 POI 卡片部分）：改名一律 DYYY -> DKXS。
//
//  POI 卡片底部约束让位参考 DYKiller：
//  src/Features/PlaybackClean/DKFeedCardFit.m
//  src/Features/PlaybackClean/DKPlaybackCleanRules.m
//  https://github.com/HierarchThurs/DYKiller/tree/bb11ab1d9cba9733d6720f0e2746dec21d6c6fe4
//
//  与上游的差异（只改接线，不改让位算法）：
//  · 让位量不用上游 rememberFrame 存的表帧基线，改用 DYxs 已有的 DKFeedCardInset
//    （以 DKVideoFeedTable 存的撑高前原高为准），与 DKFeedCardFit 共用同一开关
//    （DYxsVideoFullscreen）与同一基线；
//  · 上游的聊天视频背景（DYYYChatVideoLayout syncPlayerBackdrop）不移植，DYxs 的
//    DKVideoPageChrome 已在同一入口（AWEPlayVideoViewController
//    setPlayerBackgroundView/viewDidLayoutSubviews）同步同一色源，再加一层会重复涂色。
#import "DKXSFeedCardLayout.h"
#import "DKXSFeedCardPolicy.h"
#import "DKFeedCardFit.h"
#import <objc/runtime.h>
#import <math.h>

static char kDKXSCardControllerKey;
static NSUInteger DKXSCardFits, DKXSCardMissingConstraints;
@interface DKXSCardFitState : NSObject
@property (nonatomic, weak) NSLayoutConstraint *constraint;
@property (nonatomic, assign) CGFloat nativeConstant;
@property (nonatomic, assign) CGFloat appliedConstant;
@property (nonatomic, weak) UIView *container;
@property (nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *children;
@end
@implementation DKXSCardFitState
@end
@implementation DKXSFeedCardLayout
+ (NSHashTable *)controllers {
    static NSHashTable *controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSHashTable weakObjectsHashTable]; });
    return controllers;
}
+ (void)restoreController:(UIViewController *)controller {
    if (!NSThread.isMainThread) return;
    DKXSCardFitState *state = objc_getAssociatedObject(controller, &kDKXSCardControllerKey);
    if (!state) return;
    if (state.constraint && fabs(state.constraint.constant - state.appliedConstant) <= 0.5) state.constraint.constant = state.nativeConstant;
    for (UIView *child in state.children) {
        NSDictionary *frames = [state.children objectForKey:child];
        if (child.superview == state.container && CGRectEqualToRect(child.frame, [frames[@"applied"] CGRectValue])) child.frame = [frames[@"native"] CGRectValue];
    }
    objc_setAssociatedObject(controller, &kDKXSCardControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
+ (void)layoutController:(UIViewController *)controller afterLayout:(BOOL)afterLayout {
    if (!NSThread.isMainThread || !controller.isViewLoaded) return;
    UIView *container = nil;
    Class cls = NSClassFromString(@"AWEDynamicCardContainer");
    for (UIView *view in controller.view.subviews) if (cls && [view isKindOfClass:cls]) { container = view; break; }
    CGFloat inset = container ? DKFeedCardInset(container.superview) : 0;
    DKXSCardFitState *state = objc_getAssociatedObject(controller, &kDKXSCardControllerKey);
    if (!container || inset <= 0 || (state && state.container != container)) {
        [self restoreController:controller];
        if (!container || inset <= 0) return;
        state = nil;
    }
    if (afterLayout) {
        if (!state.constraint.active) return;
        // 仅同步实际的内容根，最多 16 项；不遍历 Lynx 内部节点、不强制 layoutIfNeeded。
        NSUInteger count = 0;
        for (UIView *child in container.subviews) {
            if (++count > 16) break;
            CGRect target = container.bounds;
            if (!CGRectEqualToRect(child.frame, target)) {
                NSDictionary *saved = [state.children objectForKey:child];
                CGRect native = saved && CGRectEqualToRect(child.frame, [saved[@"applied"] CGRectValue]) ? [saved[@"native"] CGRectValue] : child.frame;
                [state.children setObject:@{@"native": [NSValue valueWithCGRect:native], @"applied": [NSValue valueWithCGRect:target]} forKey:child];
                child.frame = target;
            }
        }
        return;
    }
    NSLayoutConstraint *bottom = nil;
    BOOL reversed = NO;
    UIView *anchor = container.superview;
    for (NSUInteger depth = 0; anchor && depth < 8; depth++, anchor = anchor.superview) {
        for (NSLayoutConstraint *constraint in anchor.constraints) {
            if (!constraint.active || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1 || constraint.firstAttribute != NSLayoutAttributeBottom || constraint.secondAttribute != NSLayoutAttributeBottom) continue;
            if (constraint.firstItem == container && constraint.secondItem == anchor) { bottom = constraint; break; }
            if (constraint.firstItem == anchor && constraint.secondItem == container) { bottom = constraint; reversed = YES; break; }
        }
        if (bottom || [anchor isKindOfClass:UITableViewCell.class]) break;
    }
    if (!bottom) { DKXSCardMissingConstraints++; [self restoreController:controller]; return; }
    if (state && state.constraint != bottom) { [self restoreController:controller]; state = nil; }
    if (!state) {
        state = [DKXSCardFitState new]; state.constraint = bottom; state.nativeConstant = bottom.constant; state.appliedConstant = bottom.constant;
        state.container = container; state.children = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(controller, &kDKXSCardControllerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[self controllers] addObject:controller];
    }
    // 接受原生晚写的新常量，不能在每轮布局把自己的偏移再次扣除。
    if (fabs(bottom.constant - state.appliedConstant) > 0.5) state.nativeConstant = bottom.constant;
    state.appliedConstant = [DKXSFeedCardPolicy bottomConstant:state.nativeConstant inset:inset reversed:reversed];
    if (fabs(bottom.constant - state.appliedConstant) > 0.5) { bottom.constant = state.appliedConstant; DKXSCardFits++; }
}
+ (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    for (UIViewController *controller in [self controllers].allObjects) {
        [self restoreController:controller]; [controller.viewIfLoaded setNeedsLayout];
    }
}
+ (NSDictionary *)diagnostics {
    return @{@"poiClassAvailable": @(NSClassFromString(@"AWEFeedPOIDynamicCardCellViewController") != nil), @"fits": @(DKXSCardFits), @"missingBottomConstraint": @(DKXSCardMissingConstraints)};
}
@end
