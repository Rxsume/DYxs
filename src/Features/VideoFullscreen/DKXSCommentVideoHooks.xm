// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>
#import "DKXSCommentVideoLayout.h"

//  最小接口声明（只声明本文件 hook 到的方法，不 import 上游 AwemeHeaders / DouyinHeaders）。
@interface AWEDPlayerViewController_Merge : UIViewController
- (void)videoDidShrink;
- (void)videoDidMagnify;
- (void)willDisplay;
@end
@interface RichContentContainerViewController : UIViewController
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated;
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated animationDuration:(double)duration;
@end

%group DKXSCommentVideoPlayerHooks
%hook AWEDPlayerViewController_Merge
- (void)videoDidShrink {
    if ([DKXSCommentVideoLayout freezeController:self]) return;
    %orig;
}
- (void)videoDidMagnify {
    %orig;
    [DKXSCommentVideoLayout didMagnifyController:self];
}
- (void)willDisplay {
    %orig;
    [DKXSCommentVideoLayout synchronizeController:self];
}
- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSCommentVideoLayout synchronizeController:self];
}
%end
%end

%group DKXSCommentVideoRichHooks
%hook RichContentContainerViewController
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated {
    if (shrink && [DKXSCommentVideoLayout freezeController:self]) return;
    %orig;
}
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated animationDuration:(double)duration {
    if (shrink && [DKXSCommentVideoLayout freezeController:self]) return;
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSCommentVideoLayout synchronizeController:self];
}
%end
%end

@implementation DKXSCommentVideoLayout (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; });
        return;
    }
    static BOOL videoInstalled, richInstalled;
    Class video = NSClassFromString(@"AWEDPlayerViewController_Merge");
    if (!videoInstalled && [video instancesRespondToSelector:@selector(videoDidShrink)] &&
        [video instancesRespondToSelector:@selector(videoDidMagnify)] && [video instancesRespondToSelector:@selector(willDisplay)]) {
        %init(DKXSCommentVideoPlayerHooks);
        videoInstalled = YES;
    }
    Class rich = NSClassFromString(@"RichContentContainerViewController");
    if (!richInstalled && [rich instancesRespondToSelector:@selector(updateShrinkState:insets:animated:)] &&
        [rich instancesRespondToSelector:@selector(updateShrinkState:insets:animated:animationDuration:)]) {
        %init(DKXSCommentVideoRichHooks);
        richInstalled = YES;
    }
}
@end

%ctor {
    [DKXSCommentVideoLayout installHooks];
}
