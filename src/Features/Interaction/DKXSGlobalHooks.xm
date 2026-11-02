//
//  DKXSGlobalHooks.xm
//  DYxs（第 6 批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 中真正的全局类 hook（只取本批范围）：
//  - UILabel / UIButton 的评论毛玻璃转发：补齐第 4 批毛玻璃（第 4 批的
//    DKXSCommentBlurCoordinator 已提供同名 API，但第 4 批接线未含这几处；
//    开关关闭时协调器内部 stateForContentView 返回 nil，原样放行，无影响）。
//  - UILabel 布局里的隐藏右侧标签 / 章节要点、UIButton 布局里的隐藏返回 /
//    扫一扫、UIImageView 布局里的隐藏评论发现图标：第 3 批键表里没有这 5 键，
//    是隐藏剩余的尾巴，随本批全局 hook 一起补。
//  - UITextField / UITextView 的键盘外观跟随深色模式：上游无开关的全局行为，
//    用 DYxs 已有的 DKXSUtils isDarkMode 实现，原样移植。
//  不搬的部分（见 REPORT.md）：CALayer/CAShapeLayer 的头像 chrome（第 3 批已另做）、
//  HDR 全套（第 5c 批）、UIWindow 双指手势（依赖未移植的设置主界面）、
//  UIMenu 表情保存（依赖 DYYYManager）、UIViewController 全局刷新（第 2 批
//  已在目标控制器上做）、UIView 的头像/清屏/全局透明度（第 2、3、5d 批）。
//  本文件不 import DouyinHeaders、不 import 上游 AwemeHeaders；
//  抖音类只用 NSClassFromString 判定，不补声明。
//
#import <UIKit/UIKit.h>
#import "DKXSCommentBlurCoordinator.h"
#import "DKXSUtils.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

%hook UILabel

- (void)setBackgroundColor:(UIColor *)color {
    %orig([DKXSCommentBlurCoordinator backgroundColorForTextView:(UIView *)self proposed:color]);
}

- (void)setOpaque:(BOOL)opaque {
    %orig([DKXSCommentBlurCoordinator opaqueForTextView:(UIView *)self proposed:opaque]);
}

- (void)didMoveToWindow {
    %orig;
    [DKXSCommentBlurCoordinator layoutTextView:(UIView *)self];
}

- (void)layoutSubviews {
    %orig;
    [DKXSCommentBlurCoordinator layoutTextView:(UIView *)self];
    BOOL hideRightLabel = DKXSGetBool(@"DKXSHideRightLabel");
    BOOL hideChapterPoints = DKXSGetBool(@"DKXSHideChapterPoints");
    if (!hideRightLabel && !hideChapterPoints) return;
    NSString *accessibilityLabel = self.accessibilityLabel;
    if (!accessibilityLabel || accessibilityLabel.length == 0) return;
    UIView *parentView = self.superview;
    if (!parentView) return;
    // 上游用 +load 初始化该表；hook +load 不可靠，本批改为懒初始化
    // （nil 表时 containsObject 恒为 NO、addObject 为空操作，逻辑仍正确）。
    static NSHashTable *processedParentViews = nil;
    if (!processedParentViews) processedParentViews = [NSHashTable weakObjectsHashTable];
    @synchronized(processedParentViews) {
        if ([processedParentViews containsObject:parentView]) return;
    }
    NSString *trimmedLabel = [accessibilityLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL shouldRemove = NO;
    // 独立开关：只隐藏昵称旁边的章节要点。
    if (hideChapterPoints && [trimmedLabel isEqualToString:@"章节要点"]) {
        shouldRemove = YES;
    }
    if (!shouldRemove && hideRightLabel) {
        if ([trimmedLabel hasSuffix:@"人共创"] && trimmedLabel.length > 3) {
            NSString *prefix = [trimmedLabel substringToIndex:trimmedLabel.length - 3];
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            shouldRemove = ([prefix rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
        }
        if (!shouldRemove) {
            shouldRemove = [trimmedLabel isEqualToString:@"章节要点"] || [trimmedLabel isEqualToString:@"图集"] || [trimmedLabel isEqualToString:@"下一章"];
        }
    }
    if (shouldRemove) {
        @synchronized(processedParentViews) {
            [processedParentViews addObject:parentView];
        }
        UIView *grandparentView = parentView.superview;
        if (grandparentView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([grandparentView isKindOfClass:[UIStackView class]]) {
                    UIStackView *stackView = (UIStackView *)grandparentView;
                    [stackView removeArrangedSubview:parentView];
                }
                [parentView removeFromSuperview];
                [grandparentView setNeedsLayout];
                [grandparentView layoutIfNeeded];
            });
        }
    }
}

%end

%hook UIButton

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSEnableCommentBlur") && (self.currentTitle.length > 0 || self.currentAttributedTitle.length > 0)) {
        [DKXSCommentBlurCoordinator layoutTextView:self.titleLabel];
    }
    NSString *accessibilityLabel = self.accessibilityLabel;
    if ([accessibilityLabel isEqualToString:@"拍照搜同款"] || [accessibilityLabel isEqualToString:@"扫一扫"]) {
        if (DKXSGetBool(@"DKXSHideScancode")) {
            [self removeFromSuperview];
        }
    }
    if ([accessibilityLabel isEqualToString:@"返回"]) {
        if (DKXSGetBool(@"DKXSHideBack")) {
            UIView *parent = self.superview;
            // 父视图是 AWEBaseElementView（排除用户主页返回按钮），按钮类不是
            // AWENoxusHighlightButton（排除横屏返回按钮），上游原样。
            if ([parent isKindOfClass:NSClassFromString(@"AWEBaseElementView")] &&
                ![self isKindOfClass:NSClassFromString(@"AWENoxusHighlightButton")]) {
                [self removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook UIImageView

- (void)layoutSubviews {
    %orig;
    // setImage 系列的 SDR 动态范围处理属 HDR 全套，归第 5c 批，本批只搬隐藏项。
    if (DKXSGetBool(@"DKXSHideCommentDiscover")) {
        if (!self.accessibilityLabel) {
            UIView *parentView = self.superview;
            if (parentView && [parentView class] == [UIView class] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            } else if (parentView && [NSStringFromClass([parentView class]) isEqualToString:@"AWESearchEntryHalfScreenElement"] && [parentView.accessibilityLabel isEqualToString:@"搜索"]) {
                self.hidden = YES;
            }
        }
    }
}

%end

%hook UITextField

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (newWindow) {
        BOOL isDarkMode = [DKXSUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DKXSUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook UITextView

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;
    if (newWindow) {
        BOOL isDarkMode = [DKXSUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DKXSUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%ctor {
    %init;
}
