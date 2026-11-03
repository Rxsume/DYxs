//
//  DKXSSheetBlurHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm「为 AWEUserActionSheetView 添加毛玻璃效果」
//  （layoutSubviews + %new applyBlurEffectAndWhiteText），以及它调用的
//  DYYYUtils 三个通用方法（本文件内静态移植，不动 DYxs 现有 DKXSUtils）。
//  键：DKXSEnableSheetBlur（开关）、DKXSSheetBlurTransparent（0-1 小数，
//  非法值时上游默认 0.9，原样保留）。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders，只给最小类声明。
//  冲突核查：DYxs src 里没有任何文件 hook AWEUserActionSheetView，零冲突。
//  注意：本文件与第 4 批的评论毛玻璃协调器（DKXSCommentBlur*）不是同一物：
//  那边是评论面板的毛玻璃跟随协调器，这边是保存/操作面板的毛玻璃。
//

#import <UIKit/UIKit.h>
#import "DKXSUtils.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

@interface AWEUserActionSheetView : UIView
@property (nonatomic, strong) UIView *containerView;
- (void)applyBlurEffectAndWhiteText;
@end

static void DKXSApplyBlurEffectToView(UIView *view, float userTransparency, NSInteger tag) {
    if (!view) {
        return;
    }
    view.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *existingBlurView = nil;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == tag) {
            existingBlurView = (UIVisualEffectView *)subview;
            break;
        }
    }

    BOOL isDarkMode = [DKXSUtils isDarkMode];
    UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;

    UIView *overlayView = nil;

    if (!existingBlurView) {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurEffectView.frame = view.bounds;
        blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurEffectView.alpha = userTransparency;
        blurEffectView.tag = tag;

        overlayView = [[UIView alloc] initWithFrame:view.bounds];
        overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [blurEffectView.contentView addSubview:overlayView];

        [view insertSubview:blurEffectView atIndex:0];
    } else {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        [existingBlurView setEffect:blurEffect];
        existingBlurView.alpha = userTransparency;

        for (UIView *subview in existingBlurView.contentView.subviews) {
            if ([subview isKindOfClass:[UIView class]]) {
                overlayView = subview;
                break;
            }
        }
        if (!overlayView) {
            overlayView = [[UIView alloc] initWithFrame:existingBlurView.bounds];
            overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [existingBlurView.contentView addSubview:overlayView];
        }
    }
    if (overlayView) {
        CGFloat alpha = isDarkMode ? 0.2 : 0.1;
        overlayView.backgroundColor = [UIColor colorWithWhite:(isDarkMode ? 0 : 1) alpha:alpha];
    }
}

static void DKXSClearBackgroundRecursivelyInView(UIView *view) {
    if (!view) {
        return;
    }
    BOOL shouldClear = YES;
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        shouldClear = NO;
    } else if (view.superview && [view.superview isKindOfClass:[UIVisualEffectView class]]) {
        shouldClear = NO;
    }
    if (shouldClear) {
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
    }
    for (UIView *subview in view.subviews) {
        DKXSClearBackgroundRecursivelyInView(subview);
    }
}

static void DKXSApplyTextColorRecursively(UIColor *color, UIView *view, BOOL (^excludeBlock)(UIView *subview)) {
    if (!view || !color) {
        return;
    }
    BOOL shouldExclude = NO;
    if (excludeBlock) {
        shouldExclude = excludeBlock(view);
    }
    if (!shouldExclude) {
        if ([view isKindOfClass:[UILabel class]]) {
            ((UILabel *)view).textColor = color;
        } else if ([view isKindOfClass:[UIButton class]]) {
            [(UIButton *)view setTitleColor:color forState:UIControlStateNormal];
        }
    }
    for (UIView *subview in view.subviews) {
        DKXSApplyTextColorRecursively(color, subview, excludeBlock);
    }
}

%hook AWEUserActionSheetView

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSEnableSheetBlur")) {
        [self applyBlurEffectAndWhiteText];
    }
}

%new
- (void)applyBlurEffectAndWhiteText {
    if (self.containerView) {
        self.containerView.backgroundColor = [UIColor clearColor];

        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSSheetBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.9;
        }

        DKXSApplyBlurEffectToView(self.containerView, userTransparency, 9999);
        DKXSClearBackgroundRecursivelyInView(self.containerView);
        DKXSApplyTextColorRecursively([UIColor whiteColor], self.containerView, nil);
    }
}

%end

%ctor {
    %init;
}
