// 移植来源：Wtrwx/DYYY 的 DYYYCommentPlaybackCoordinator.m（原名见 REPORT.md）。
// 本文件不 import 上游 AwemeHeaders 与 DYYYFloatingButtonCoordinator（后者是第 2 批）：
//  - Swift 评论视图模型与状态模型只给最小接口声明（取自上游 AwemeHeaders.h）。
//  - 当前播放控制器改为动态查找 DKXSFloatingButtonCoordinator（第 2 批移植后的名字）：
//    第 2 批未到时 current 为 nil，只按可见面积选暂停目标；第 2 批到了则自动恢复
//    上游“同作品模型加分”的逻辑。见 REPORT.md。
#import "DKXSCommentPlaybackCoordinator.h"
#import <UIKit/UIKit.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

// 最小接口声明（取自上游 AwemeHeaders.h；DouyinHeaders 里没有这些声明）。
@interface _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel : NSObject
- (instancetype)init;
- (void)setTabManager:(id)tabManager;
- (BOOL)isFeedVideoPlaying;
- (id)feedVideoPlayerController;
- (void)pauseVideoIfPlayingWithoutShowingPauseIcon;
- (void)recoverPlayIfPauseByComment;
@end

@interface _TtC33AWECommentPanelContainerSwiftImpl31CommentViewControllerStateModel : NSObject
- (BOOL)isSkipCommentPanelLifecycle;
- (BOOL)isCommentImageBrowsing;
@end

@interface AWECommentContainerViewController (DKXSBatch1)
- (id)state;
@end

// 最小接口声明（取自 DYxs DouyinHeaders.h 的 AWEAwemeModel 声明；本文件不
// import DouyinHeaders，避免把整套抖音类声明拖进本编译单元）。
@interface AWEAwemeModel : NSObject
@property (nonatomic, copy) NSString *itemID;
@end

@interface DKXSCommentPlaybackCoordinator ()
@property(nonatomic, strong) NSHashTable *viewModels;
@property(nonatomic, weak) UIViewController *commentController;
@property(nonatomic, weak) _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *pausedViewModel;
@end

@implementation DKXSCommentPlaybackCoordinator

+ (instancetype)shared {
    static DKXSCommentPlaybackCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [self new];
        coordinator.viewModels = [NSHashTable weakObjectsHashTable];
    });
    return coordinator;
}

#pragma mark - 原生评论暂停与恢复

+ (void)registerViewModel:(id)viewModel {
    if (!viewModel) return;
    if (!NSThread.isMainThread) {
        __weak id weakViewModel = viewModel;
        dispatch_async(dispatch_get_main_queue(), ^{ [self registerViewModel:weakViewModel]; });
        return;
    }
    [[self shared].viewModels addObject:viewModel];
    [self pauseIfNeeded];
}

+ (void)pauseIfNeeded {
    DKXSCommentPlaybackCoordinator *coordinator = [self shared];
    if (!coordinator.commentController || coordinator.pausedViewModel || !DKXSGetBool(@"DKXSCommentPausePlayback")) return;

    // 第 2 批未到时动态查找失败即为 nil，不影响可见面积评分；第 2 批到了则恢复上游逻辑。
    Class floatingButtonCoordinatorClass = NSClassFromString(@"DKXSFloatingButtonCoordinator");
    id current = nil;
    if ([floatingButtonCoordinatorClass respondsToSelector:@selector(currentInteractionController)]) {
        current = [floatingButtonCoordinatorClass currentInteractionController];
    }
    id bestViewModel = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (_TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *viewModel in coordinator.viewModels.allObjects) {
        @try {
            if (![viewModel respondsToSelector:@selector(isFeedVideoPlaying)] || ![viewModel isFeedVideoPlaying]) continue;
            if (![viewModel respondsToSelector:@selector(pauseVideoIfPlayingWithoutShowingPauseIcon)]) continue;
            id player = [viewModel respondsToSelector:@selector(feedVideoPlayerController)] ? [viewModel feedVideoPlayerController] : nil;
            CGFloat score = 0;
            if ([player isKindOfClass:UIViewController.class]) {
                UIView *view = ((UIViewController *)player).viewIfLoaded;
                if (view.window && !view.hidden) {
                    CGRect rect = [view convertRect:view.bounds toView:view.window];
                    CGRect visible = CGRectIntersection(rect, view.window.bounds);
                    if (!CGRectIsNull(visible)) score = visible.size.width * visible.size.height;
                }
            }
            if (current && [player respondsToSelector:@selector(model)] && [current respondsToSelector:@selector(model)]) {
                AWEAwemeModel *model = [player model];
                id currentModel = [current model];
                if (model == currentModel || (model.itemID.length && [model.itemID isEqualToString:[currentModel itemID]])) score += 1.0e12;
            }
            if (score > bestScore) { bestScore = score; bestViewModel = viewModel; }
        } @catch (__unused NSException *exception) {
        }
    }
    @try {
        // 使用 main 中的原生入口，保留宿主评论暂停状态和媒体预览的恢复约定。
        [bestViewModel pauseVideoIfPlayingWithoutShowingPauseIcon];
        coordinator.pausedViewModel = bestViewModel;
    } @catch (NSException *exception) {
        NSLog(@"[DKXS] 评论暂停失败：%@", exception.reason);
    }
}

+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (!NSThread.isMainThread) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ [self commentController:weakController visible:visible]; });
        return;
    }
    if (!controller) return;
    DKXSCommentPlaybackCoordinator *coordinator = [self shared];
    if (visible) {
        coordinator.commentController = controller;
        [self pauseIfNeeded];
        return;
    }
    if (coordinator.commentController != controller) return;
    if ([self shouldSkipLifecycle:controller]) return;
    id paused = coordinator.pausedViewModel;
    coordinator.commentController = nil;
    coordinator.pausedViewModel = nil;
    @try {
        if ([paused respondsToSelector:@selector(recoverPlayIfPauseByComment)]) [paused recoverPlayIfPauseByComment];
    } @catch (NSException *exception) {
        NSLog(@"[DKXS] 评论播放恢复失败：%@", exception.reason);
    }
}

+ (BOOL)ownsPlayback {
    return [self shared].pausedViewModel != nil;
}

+ (BOOL)shouldSkipLifecycle:(UIViewController *)controller {
    @try {
        if (![controller respondsToSelector:@selector(state)]) return NO;
        _TtC33AWECommentPanelContainerSwiftImpl31CommentViewControllerStateModel *state = [(AWECommentContainerViewController *)controller state];
        return [state respondsToSelector:@selector(isSkipCommentPanelLifecycle)] && state.isSkipCommentPanelLifecycle;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

@end
