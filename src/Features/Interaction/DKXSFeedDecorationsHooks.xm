// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>
#import "DKXSFeedTagGlass.h"
#import "DKXSAvatarRing.h"
#import "DKXSSameStyleVisibility.h"

//  最小接口声明（只声明本文件 hook 到的方法，不 import 上游 AwemeHeaders / DouyinHeaders）。
@interface AWEPlayInteractionTagsStackView : UIStackView
@end
@interface AWEPlayInteractionGeneralTagView : UIView
@end
@interface AWEPlayInteractionTagsContainerLabelView : UIView
@end
@interface AFDColorRingView : UIView
- (void)updateDisplayConfig:(id)config;
- (void)startAnimationWithType:(NSInteger)type;
- (void)stopAnimation;
- (void)addAttachmentView;
- (void)prepareForReuse;
@end
@interface AWEPlayInteractionSingleSongMusicStyleView : UIView
- (void)setAwemeModel:(id)model;
- (void)updatePlayInteractionTitle:(id)title;
- (void)updatePlayInteractionDecorationHidden:(BOOL)hidden;
- (void)updatePlayInteractionLayout:(double)layout;
@end
@interface AWEPlayInteractionStyleOneMusicView : UIView
- (void)setAwemeModel:(id)model;
- (void)updatePlayInteractionTitle:(id)title;
- (void)updatePlayInteractionDecorationHidden:(BOOL)hidden;
- (void)updatePlayInteractionLayout:(double)layout;
@end

%group DKXSTagStackGlassHooks
%hook AWEPlayInteractionTagsStackView
- (void)layoutSubviews {
    %orig;
    [DKXSFeedTagGlass decorateStack:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSFeedTagGlass decorateStack:(UIView *)self];
}
%end
%end

%group DKXSGeneralTagGlassHooks
%hook AWEPlayInteractionGeneralTagView
- (void)layoutSubviews {
    %orig;
    [DKXSFeedTagGlass decorateTag:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSFeedTagGlass decorateTag:(UIView *)self];
}
%end
%end

%group DKXSContainerTagGlassHooks
%hook AWEPlayInteractionTagsContainerLabelView
- (void)layoutSubviews {
    %orig;
    [DKXSFeedTagGlass decorateTag:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSFeedTagGlass decorateTag:(UIView *)self];
}
%end
%end

%group DKXSAvatarRingHooks
%hook AFDColorRingView
- (void)layoutSubviews {
    %orig;
    [DKXSAvatarRing applyToRing:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSAvatarRing applyToRing:(UIView *)self];
}
- (void)updateDisplayConfig:(id)config {
    [DKXSAvatarRing beginNativeUpdate:(UIView *)self];
    %orig(config);
    [DKXSAvatarRing endNativeUpdate:(UIView *)self];
}
- (void)startAnimationWithType:(NSInteger)type {
    [DKXSAvatarRing beginNativeUpdate:(UIView *)self];
    %orig(type);
    [DKXSAvatarRing endNativeUpdate:(UIView *)self];
}
- (void)stopAnimation {
    [DKXSAvatarRing beginNativeUpdate:(UIView *)self];
    %orig;
    [DKXSAvatarRing endNativeUpdate:(UIView *)self];
}
- (void)addAttachmentView {
    [DKXSAvatarRing beginNativeUpdate:(UIView *)self];
    %orig;
    [DKXSAvatarRing endNativeUpdate:(UIView *)self];
}
- (void)prepareForReuse {
    [DKXSAvatarRing restoreRing:(UIView *)self];
    %orig;
    [DKXSAvatarRing restoreRing:(UIView *)self];
}
%end
%end

%group DKXSSameStyleVisibilityHooks
%hook AWEPlayInteractionSingleSongMusicStyleView
- (void)layoutSubviews {
    %orig;
    [DKXSSameStyleVisibility applyToView:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSSameStyleVisibility applyToView:(UIView *)self];
}
- (void)setAwemeModel:(id)model {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(model);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionTitle:(id)title {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(title);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionDecorationHidden:(BOOL)hidden {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(hidden);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionLayout:(double)layout {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(layout);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
%end
%end

%group DKXSStyleOneMusicVisibilityHooks
%hook AWEPlayInteractionStyleOneMusicView
- (void)layoutSubviews {
    %orig;
    [DKXSSameStyleVisibility applyToView:(UIView *)self];
}
- (void)didMoveToWindow {
    %orig;
    [DKXSSameStyleVisibility applyToView:(UIView *)self];
}
- (void)setAwemeModel:(id)model {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(model);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionTitle:(id)title {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(title);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionDecorationHidden:(BOOL)hidden {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(hidden);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
- (void)updatePlayInteractionLayout:(double)layout {
    [DKXSSameStyleVisibility beginNativeUpdate:(UIView *)self];
    %orig(layout);
    [DKXSSameStyleVisibility endNativeUpdate:(UIView *)self];
}
%end
%end

@implementation DKXSFeedTagGlass (DecorationHooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return;
    }
    static BOOL stackInstalled, generalInstalled, containerInstalled, ringInstalled, musicInstalled, styleOneMusicInstalled;
    // 均位于 AwemeCore，按实际存在的类分别安装，不依赖未出现的标签种类。
    if (!stackInstalled && NSClassFromString(@"AWEPlayInteractionTagsStackView")) {
        %init(DKXSTagStackGlassHooks);
        stackInstalled = YES;
    }
    if (!generalInstalled && NSClassFromString(@"AWEPlayInteractionGeneralTagView")) {
        %init(DKXSGeneralTagGlassHooks);
        generalInstalled = YES;
    }
    if (!containerInstalled && NSClassFromString(@"AWEPlayInteractionTagsContainerLabelView")) {
        %init(DKXSContainerTagGlassHooks);
        containerInstalled = YES;
    }
    if (!ringInstalled && NSClassFromString(@"AFDColorRingView")) {
        %init(DKXSAvatarRingHooks);
        ringInstalled = YES;
    }
    if (!musicInstalled && NSClassFromString(@"AWEPlayInteractionSingleSongMusicStyleView")) {
        %init(DKXSSameStyleVisibilityHooks);
        musicInstalled = YES;
    }
    if (!styleOneMusicInstalled && NSClassFromString(@"AWEPlayInteractionStyleOneMusicView")) {
        %init(DKXSStyleOneMusicVisibilityHooks);
        styleOneMusicInstalled = YES;
    }
}
@end

%ctor {
    [DKXSFeedTagGlass installHooks];
    dispatch_async(dispatch_get_main_queue(), ^{ [DKXSFeedTagGlass installHooks]; });
}
