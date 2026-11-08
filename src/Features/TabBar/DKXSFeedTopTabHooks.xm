// 顶栏选中提亮接线：上游 Si-yi/DYads- b97c05e 在 DYYY.xm 里 hook AWEHPTopTabItemTextContentView
// 的 5 个方法调 DYYYFeedTopTabStyle applyToTextView:；DYxs 不整并 DYYY.xm，改由本文件独立接线。
// DKXSTitleHooks.xm 已 hook 同类的 layoutSubviews，Logos %orig 链串联（DKGlassTabBar、
// DKTabBarAppearance 同类 layoutSubviews 同方法已有此先例），不吞现有标题映射效果。
// 须先 import UIKit：下方的最小接口声明以 UIView 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSFeedTopTabStyle.h"

// 最小接口声明（沿用第 8 批写法，不 import 大头文件）：以下方法均不在 DKXSAwemeHeaders
//（39.5 导出）里；setContentText: 已在该头文件声明，此处不重复。
@interface AWEHPTopTabItemTextContentView : UIView
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, assign, readonly) double selectedProgress;
@property (nonatomic, assign, readonly) BOOL isLightTheme;
- (void)setSelectedProgress:(double)progress;
- (void)updateTextColor:(UIColor *)color;
- (void)updateTitleLabelShadowWithProgress:(double)progress;
@end

%hook AWEHPTopTabItemTextContentView

- (void)didMoveToWindow {
    %orig;
    [DKXSFeedTopTabStyle applyToTextView:self];
}

- (void)setSelectedProgress:(double)progress {
    %orig(progress);
    [DKXSFeedTopTabStyle applyToTextView:self];
}

- (void)updateTextColor:(UIColor *)color {
    %orig(color);
    [DKXSFeedTopTabStyle applyToTextView:self];
}

- (void)updateTitleLabelShadowWithProgress:(double)progress {
    %orig(progress);
    [DKXSFeedTopTabStyle applyToTextView:self];
}

- (void)layoutSubviews {
    %orig;
    [DKXSFeedTopTabStyle applyToTextView:self];
}

%end

%ctor { [DKXSFeedTopTabStyle preparePreferences]; }
