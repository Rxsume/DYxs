// 移植来源：Wtrwx/DYYY 的 DYYYFeatureHooks.xm（原名见 REPORT.md）。
// 本文件不 import 上游 AwemeHeaders；目标类只给最小接口声明（取自上游
// AwemeHeaders.h 中已有的声明；其中 AWEPlayInteractionMusicAiRefactorListenFeedController
// 与 AWEFeedMeetMusicView 在上游也没有 @interface，本移植按其 hook 方法补最小声明，
// 父类为推断值，见 REPORT.md 未确定点）。
#import <UIKit/UIKit.h>
#import "DKXSFeatureUI.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

// 最小接口声明（仅本文件 hook 用到的方法；Logos 会对 %hook 类再生成前置声明）。
@interface AWEPlayInteractionMusicAiRefactorListenFeedController : UIViewController
- (BOOL)shouldShowAddFeedMusicView;
- (void)showFeedMusicViewIfNeeded;
- (void)setAddFeedMusicView:(UIView *)view;
- (void)updateAddFeedMusicViewLayoutWithShowSpeedControl:(BOOL)showSpeedControl;
@end

@interface AWEPlayInteractionDiversionBar : UIView
@end

@interface AWEPlayInteractionNewDiversionBarBottomElement : NSObject
@property(nonatomic, strong) AWEPlayInteractionDiversionBar *diversionBarView;
@end

@interface AWEDouYinSelectUGBottomBarController : NSObject
- (BOOL)canShowBottomBarForAweme:(id)aweme;
- (void)updateBottomBarWithAweme:(id)aweme updateTiming:(BOOL)updateTiming;
- (void)bottomBarAddedToContainer:(id)container;
@property(nonatomic, strong) UIView *appGuideView;
@property(nonatomic, strong) UIView *appGuideContainer;
@end

@interface AWEFeedMeetMusicView : UIView
@end

@interface IESLiveFlowGuidanceAdView : UIView
@end

@interface IESLiveFlowGuidanceFragment : NSObject
+ (BOOL)componentShouldActive:(id)attacher;
@end

// 隐藏文案下推荐应用下载横幅
static void DKXSRemoveRecommendAppDownloadView(id viewObject) {
    if (![viewObject isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *view = (UIView *)viewObject;
    view.hidden = YES;
    [view removeFromSuperview];
}

static void DKXSHideRecommendAppDownloadViewForOwner(id owner) {
    id addFeedMusicView = [DKXSFeatureUI value:owner key:@"addFeedMusicView"];
    DKXSRemoveRecommendAppDownloadView(addFeedMusicView);
    [DKXSFeatureUI setValue:nil object:owner key:@"addFeedMusicView"];
}

%hook AWEPlayInteractionMusicAiRefactorListenFeedController

- (BOOL)shouldShowAddFeedMusicView {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        return NO;
    }
    return %orig;
}

- (void)showFeedMusicViewIfNeeded {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSHideRecommendAppDownloadViewForOwner(self);
        return;
    }
    %orig;
}

- (void)setAddFeedMusicView:(UIView *)view {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        if ([view isKindOfClass:[UIView class]]) {
            view.hidden = YES;
            [view removeFromSuperview];
        }
        %orig(nil);
        return;
    }
    %orig;
}

- (void)updateAddFeedMusicViewLayoutWithShowSpeedControl:(BOOL)showSpeedControl {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSHideRecommendAppDownloadViewForOwner(self);
        return;
    }
    %orig;
}

%end

// 39.3.0 的应用推荐已改走通用 Diversion Bar。该视图只承载
// pkgInfo/appMarket/downloadIntermediatePage 类应用引流，隐藏它不会删除作品文案或普通音乐信息。
%hook AWEPlayInteractionDiversionBar

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView(self);
        return;
    }
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView(self);
    }
}

%end

%hook AWEPlayInteractionNewDiversionBarBottomElement

- (void)setDiversionBarView:(AWEPlayInteractionDiversionBar *)view {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

- (void)layoutElementView {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView([DKXSFeatureUI ivar:self name:"_diversionBarView"]);
        return;
    }
    %orig;
}

%end

// 抖音精选的应用推荐使用独立 Lynx 底栏。只在其自身的
// canShow/update/add 入口阻断，不移除 feed 容器。
static void DKXSHideDouYinSelectAppGuideViews(id owner) {
    DKXSRemoveRecommendAppDownloadView([DKXSFeatureUI ivar:owner name:"_appGuideView"]);
    DKXSRemoveRecommendAppDownloadView([DKXSFeatureUI ivar:owner name:"_appGuideContainer"]);
}

%hook AWEDouYinSelectUGBottomBarController

- (BOOL)canShowBottomBarForAweme:(id)aweme {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        return NO;
    }
    return %orig;
}

- (void)updateBottomBarWithAweme:(id)aweme updateTiming:(BOOL)updateTiming {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSHideDouYinSelectAppGuideViews(self);
        return;
    }
    %orig;
}

- (void)bottomBarAddedToContainer:(id)container {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSHideDouYinSelectAppGuideViews(self);
        return;
    }
    %orig;
}

- (void)setAppGuideView:(UIView *)view {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

- (void)setAppGuideContainer:(UIView *)view {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        DKXSRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

%end

%hook AWEFeedMeetMusicView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        UIView *view = (UIView *)self;
        view.hidden = YES;
        [view removeFromSuperview];
        return;
    }
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    if (DKXSGetBool(@"DKXSHideRecommendAppDownload")) {
        UIView *view = (UIView *)self;
        view.hidden = YES;
        [view removeFromSuperview];
    }
}

%end


%hook IESLiveFlowGuidanceFragment

+ (BOOL)componentShouldActive:(id)attacher {
    if (DKXSGetBool(@"DKXSHideLiveRoomShareCompanion")) {
        return NO;
    }
    return %orig;
}

%end


%hook IESLiveFlowGuidanceAdView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideLiveRoomShareCompanion")) {
        self.hidden = YES;
        [self removeFromSuperview];
        return;
    }
    %orig;
}

- (void)didMoveToSuperview {
    if (DKXSGetBool(@"DKXSHideLiveRoomShareCompanion")) {
        if (self.superview) {
            self.hidden = YES;
            [self removeFromSuperview];
        }
        return;
    }
    %orig;
}

%end

%ctor {
    %init;
}
