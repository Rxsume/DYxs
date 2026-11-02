//
//  DKXSBatch3aTabBar.xm
//  DYxs — 第 3 批 staging（尚未并入 DYxs 源码）
//  移植自上游 Wtrwx/DYYY（head 49867e1，2026-10-25）DYYY.xm，类/函数前缀 DYYY -> DKXS，
//  设置键 DYYY* -> DKXS*。抖音类名、ivar 名、accessibilityLabel 文案保持原样。
//  本文件不 import 上游 AwemeHeaders.h；只用 UIKit + objc/runtime + 最小前置声明。
//  详见同目录 REPORT.md（冲突核查、删减说明、布局建议）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

%hook AWENormalModeTabBarPlusButton

- (void)setHidden:(BOOL)hidden {
    BOOL hidePlus = DKXSGetBool(@"DKXSHidePlusButton");
    %orig(hidePlus ? YES : hidden);

    if (hidePlus) {
        self.userInteractionEnabled = NO;
    }
}

- (void)didMoveToWindow {
    %orig;

    if (self.window && DKXSGetBool(@"DKXSHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

- (void)layoutSubviews {
    %orig;

    if (DKXSGetBool(@"DKXSHidePlusButton")) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    }
}

%end

%hook AWETabBarElementContainerView

- (void)setHidden:(BOOL)hidden {
    if (DKXSGetBool(@"DKXSHidePadTabBarElements")) {
        %orig(YES);
        return;
    }

    %orig(hidden);
}

%end

%hook AWENormalModeTabBarFeedView

- (void)layoutSubviews {
    @try {
        %orig;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideDoubleColumnEntry"]) {
            return;
        }

        static char kDKXSDoubleColumnCacheKey;
        static char kDKXSDoubleColumnCountKey;
        NSArray *cachedViews = objc_getAssociatedObject(self, &kDKXSDoubleColumnCacheKey);
        NSNumber *cachedCount = objc_getAssociatedObject(self, &kDKXSDoubleColumnCountKey);
        if (!cachedViews || cachedCount.unsignedIntegerValue != self.subviews.count) {
            NSMutableArray *views = [NSMutableArray array];
            for (UIView *subview in self.subviews) {
                if (![subview isKindOfClass:[UILabel class]]) {
                    [views addObject:subview];
                }
            }
            cachedViews = [views copy];
            objc_setAssociatedObject(self, &kDKXSDoubleColumnCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, &kDKXSDoubleColumnCountKey, @(self.subviews.count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIView *v in cachedViews) {
            v.hidden = YES;
        }
    } @catch (NSException *exception) {
        return;
    }
}
%end

%hook AWEHotSearchInnerBottomView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideHotSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

// 隐藏全屏观看 / 移除全屏观看（上游 AWELandscapeFeedEntryView layoutSubviews 中的两支；
// 全局透明与昵称缩放已删，见 REPORT.md）。
%hook AWELandscapeFeedEntryView

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSRemoveEntry")) {
        [self removeFromSuperview];
        return;
    }
    if (DKXSGetBool(@"DKXSHideEntry")) {
        for (UIView *subview in self.subviews) {
            subview.hidden = YES;
        }
        return;
    }
}

%end

%ctor {
    %init;
}
