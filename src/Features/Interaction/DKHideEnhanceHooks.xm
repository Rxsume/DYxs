//
//  DKHideEnhanceHooks.xm
//  DYxs
//
//  从 DYads-（DYYY）简单移植的第一批隐藏设置与增强设置的 hook 实现。
//  原逻辑见 DYads- 的 DYYY.xm，设置键由 DYYY* 改为 DKXS*，其余逻辑不变。
//  本文件不 import DKXSAwemeHeaders，只 import DouyinHeaders（已声明
//  AWEFeedVideoButton、AWEMusicCoverButton、AWEPlayInteractionListenFeedView），
//  另两个类在 DouyinHeaders 中没有声明，这里给出最小接口声明以便编译。
//  DYxs 现有代码没有 hook 下面这五个类的方法，不会与 DYKiller 原有 hook 冲突。
//

#import "DouyinHeaders.h"
#import <objc/runtime.h>

@interface AWELiveGuideElement : NSObject
- (BOOL)enableAutoEnterRoom;
- (BOOL)enableNewAutoEnter;
@end

@interface AWEFeedLiveTabTopSelectionView : UIView
- (void)setHideTimer:(id)timer;
@end

%hook AWEFeedVideoButton

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    BOOL hideBtn = NO;
    BOOL hideLabel = NO;

    if ([accessibilityLabel isEqualToString:@"点赞"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideLikeButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideLikeLabel"];
    } else if ([accessibilityLabel isEqualToString:@"评论"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideCommentButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideCommentLabel"];
    } else if ([accessibilityLabel isEqualToString:@"分享"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideShareButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideShareLabel"];
    } else if ([accessibilityLabel isEqualToString:@"收藏"]) {
        hideBtn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideCollectButton"];
        hideLabel = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideCollectLabel"];
    }

    if (!hideBtn && !hideLabel) {
        return;
    }

    if (hideBtn) {
        [self removeFromSuperview];
        return;
    }

    static char kDKXSLabelCacheKey;
    NSArray *cachedLabels = objc_getAssociatedObject(self, &kDKXSLabelCacheKey);
    if (!cachedLabels) {
        NSMutableArray *labels = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                [labels addObject:subview];
            }
        }
        cachedLabels = [labels copy];
        objc_setAssociatedObject(self, &kDKXSLabelCacheKey, cachedLabels, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UILabel *label in cachedLabels) {
        label.hidden = hideLabel;
    }
}

%end

%hook AWEMusicCoverButton

- (void)layoutSubviews {
    %orig;
    NSString *accessibilityLabel = self.accessibilityLabel;
    if ([accessibilityLabel isEqualToString:@"音乐详情"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideMusicButton"]) {
            UIView *parent = self.superview;
            if (parent) {
                [parent removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEPlayInteractionListenFeedView

- (void)layoutSubviews {
    %orig;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideMusicButton"]) {
        [self removeFromSuperview];
        return;
    }
}

%end

// 禁用自动进入直播间
%hook AWELiveGuideElement

- (BOOL)enableAutoEnterRoom {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSDisableAutoEnterLive"]) {
        return NO;
    }
    return %orig;
}

- (BOOL)enableNewAutoEnter {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSDisableAutoEnterLive"]) {
        return NO;
    }
    return %orig;
}

%end

%hook AWEFeedLiveTabTopSelectionView

- (void)setHideTimer:(id)timer {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSDisableAutoHideLive"]) {
        timer = nil;
    }
    %orig(timer);
}

%end

%ctor {
    %init;
}
