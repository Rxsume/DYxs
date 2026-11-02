//
//  DKXSBatch5dOffsets.xm
//  DYxs 全量合并第 5 批剩余部分（5d）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 3843-3970 行（文案下移）与第 3971 行起
//  （昵称下移），符号一律 DYYY* -> DKXS*。DYxs 现有代码未 hook 这三个类，
//  无方法撞点（仅在清屏按钮的隐藏类名表里出现类名字符串，不算 hook）。
//
//  与上游的差异（主 agent 复核必读）：
//  上游 AWEPlayInteractionDescriptionLabel 与 AWEUserNameLabel 的
//  layoutSubviews 末尾都调 [DYYYFullscreenCoordinator layoutInformationLabel:self]，
//  那是第 6 批全屏协调器的调用点，本文件刻意不搬，等第 6 批落盘时由
//  第 6 批文件补上；只搬位移本身，否则两批会在同一方法里各写一次调用。
//  上游 DescriptionLabel 里另有“长按文案复制文案”（DYYYLongPressCopyTextEnabled
//  的 didMoveToWindow 手势）未搬，那不属于 5d 外观，留给杂项小批。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 最小接口声明：以下被 hook 的类在本文件内读写 UIView/NSObject 成员（hidden、alpha、superview、subviews、tag、window 等）或调用同文件 %new 方法，
// 原先只有 Logos 前置声明，编译器找不到这些成员；基类按视图身份声明为 UIView（模型类为 NSObject），不 import DouyinHeaders。
@interface AWEPlayInteractionDescriptionLabel : UIView
@end
@interface AWEPlayInteractionDescriptionScrollView : UIView
@end
@interface AWEUserNameLabel : UIView
@end

%hook AWEPlayInteractionDescriptionScrollView
- (void)layoutSubviews {
    %orig;
    self.transform = CGAffineTransformIdentity;
    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }
    UIView *parentView = self.superview;
    UIView *grandParentView = nil;
    if (parentView) {
        grandParentView = parentView.superview;
    }
    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}
%end

%hook AWEPlayInteractionDescriptionLabel
- (void)layoutSubviews {
    %orig;
    self.transform = CGAffineTransformIdentity;
    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSDescriptionVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (descriptionOffsetValue.length > 0) {
        verticalOffset = [descriptionOffsetValue floatValue];
    }
    UIView *parentView = self.superview;
    UIView *grandParentView = nil;
    if (parentView) {
        grandParentView = parentView.superview;
    }
    if (grandParentView && verticalOffset != 0) {
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}
%end

%hook AWEUserNameLabel
- (void)layoutSubviews {
    %orig;
    self.transform = CGAffineTransformIdentity;
    NSString *verticalOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSNicknameVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (verticalOffsetValue.length > 0) {
        verticalOffset = [verticalOffsetValue floatValue];
    }
    UIView *parentView = self.superview;
    UIView *grandParentView = nil;
    if (parentView) {
        grandParentView = parentView.superview;
    }
    // 上游原样：只在祖父视图的父视图是 AWEBaseElementView 时平移，
    // 并把 X 方向拉回（-scaledFrame.origin.x），避免缩放后昵称偏右。
    if (grandParentView && [grandParentView.superview isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
        CGRect scaledFrame = grandParentView.frame;
        CGFloat translationX = -scaledFrame.origin.x;
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(translationX, verticalOffset);
        grandParentView.transform = translationTransform;
    }
}
%end
