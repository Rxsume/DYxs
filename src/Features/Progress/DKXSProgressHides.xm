//
//  DKXSProgressHides.xm
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//
//  上游来源：DYYY.xm 里与进度条隐藏相关的三处小 hook。
//  · AWEStoryProgressSlideView layoutSubviews（DYYYHideStoryProgressSlide）
//  · AWEStoryProgressContainerView isHidden / setHidden（DYYYHideDotsIndicator，
//    只取圆点隐藏部分；同 %hook 里的 setCenter 是全屏逻辑，属第 6 批，不搬）
//  · AWEAwemeModel chapterList（DYYYHideChapterProgress）
//  改名：设置键 DYYY* → DKXS*。
//  撞点：AWEStoryProgressContainerView 已有 DKStoryProgressHooks.xm，
//  但它只 hook layoutSubviews / didMoveToWindow，与本文件的
//  isHidden / setHidden 不重叠，走 Logos %orig 链共存。
//  AWEStoryProgressSlideView 在 DouyinHeaders.h 里没有声明，
//  这里只给最小 @interface（第 2、4 批同款做法）。
//

#import "DouyinHeaders.h"
#import <objc/runtime.h>

@interface AWEStoryProgressSlideView : UIView
@end

static BOOL DKXSGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

%hook AWEStoryProgressSlideView

- (void)layoutSubviews {
    %orig;
    if (!DKXSGetBool(@"DKXSHideStoryProgressSlide")) return;
    // 上游原样：找第一个 UISlider 或高度 < 5 的子视图，把它的父视图藏起来；
    // 用 ASSIGN 缓存（上游同款写法：目标是 self 层级内的视图，随层级共存亡）。
    static char kDKXSStoryProgressCacheKey;
    UIView *targetView = objc_getAssociatedObject(self, &kDKXSStoryProgressCacheKey);
    if (!targetView) {
        for (UIView *obj in self.subviews) {
            if ([obj isKindOfClass:NSClassFromString(@"UISlider")] || obj.frame.size.height < 5) {
                targetView = obj.superview;
                break;
            }
        }
        if (targetView) objc_setAssociatedObject(self, &kDKXSStoryProgressCacheKey, targetView, OBJC_ASSOCIATION_ASSIGN);
    }
    if (targetView) targetView.hidden = YES;
}

%end

%hook AWEStoryProgressContainerView

- (BOOL)isHidden {
    BOOL originalValue = %orig;
    BOOL customHide = DKXSGetBool(@"DKXSHideDotsIndicator");
    return originalValue || customHide;
}

- (void)setHidden:(BOOL)hidden {
    BOOL forceHide = DKXSGetBool(@"DKXSHideDotsIndicator");
    %orig(forceHide ? YES : hidden);
}

%end

%hook AWEAwemeModel

// 屏蔽章节要点数据：开关开时章节列表恒为空，章节进度条无数据可画。
- (NSArray *)chapterList {
    if (DKXSGetBool(@"DKXSHideChapterProgress")) return @[];
    return %orig;
}

%end
