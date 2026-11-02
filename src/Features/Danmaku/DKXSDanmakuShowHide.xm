//
//  DKXSDanmakuShowHide.xm
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//
//  上游来源：DYYY.xm 里弹幕显隐的三组 hook（不含弹幕改色，见下）。
//  · XIGDanmakuPlayerView / DDanmakuPlayerView setAlpha（DYYYCommentShowDanmaku）
//  · IESLiveDanmakuVariousView / IESLiveDanmakuSupremeView layoutSubviews（DYYYHideLiveDanmaku）
//  · AWEPlayDanmakuInputContainView layoutSubviews（DYYYHideDanmuButton）
//  改名：设置键 DYYY* → DKXS*。
//
//  刻意不移植弹幕改色（DYYYEnableDanmuColor / DYYYDanmuColor /
//  DYYYDanmuRainbowRotating）：DYxs 已有 DKDanmakuColor 全套
//  （DKDanmakuColorHook.xm 已 hook AWEDanmakuContentLabel 的
//  setTextColor / setStrokeWidth / setStrokeColor 三处，即计划所说的
//  Danmaku 3 处撞点），且功能是上游的超集：固定颜色、随机纯色、
//  随机渐变、固定彩虹、自定义渐变、旋转彩虹。把上游的改色再叠一层，
//  两套着色会在同一条 Label 上互相覆盖。映射关系见 REPORT：
//  上游“自定弹幕颜色填 random”→ DYxs 随机纯色模式；
//  上游“旋转彩虹”→ DYxs 旋转彩虹模式；上游十六进制 → DYxs 固定颜色 /
//  十六进制入口。三个上游键不登记，避免死键。
//
//  与 DKCommentDanmaku.xm 的关系（DDanmakuPlayerView setAlpha 走
//  Logos %orig 链共存）：DKCommentDanmaku 在评论半屏开着时把压成透明
//  的写入顶回 1.0；本文件的开关开时则直接吞掉 alpha == 0 的写入。
//  无论哪一处先跑，结果都是弹幕可见。区别只在全屏评论区：
//  DYxs 原生规则是全屏评论区保持抖音原生行为（弹幕隐藏），
//  而本开关开着时会连全屏评论区也保持可见——这是上游开关的本意，
//  默认关，不开就不影响现有行为。
//
//  XIGDanmakuPlayerView 的 initWithFrame 里上游写
//  tag = DYYY_IGNORE_GLOBAL_ALPHA_TAG（= 114514），该 tag 的消费者
//  是上游全局透明度逻辑（第 6 批全局类 hook），本批先原样写 tag，
//  在第 6 批之前它不起任何作用。
//

#import "DouyinHeaders.h"

// DouyinHeaders.h 未声明的类：最小声明，不 import 上游 AwemeHeaders。
@interface XIGDanmakuPlayerView : UIView
@end
@interface IESLiveDanmakuVariousView : UIView
@end
@interface IESLiveDanmakuSupremeView : UIView
@end
@interface AWEPlayDanmakuInputContainView : UIView
@end

static BOOL DKXSGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

%hook XIGDanmakuPlayerView

- (id)initWithFrame:(CGRect)frame {
    id orig = %orig;
    ((UIView *)orig).tag = 114514;
    return orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (DKXSGetBool(@"DKXSCommentShowDanmaku") && alpha == 0.0) return;
    %orig(alpha);
}

%end

%hook DDanmakuPlayerView

- (void)setAlpha:(CGFloat)alpha {
    if (DKXSGetBool(@"DKXSCommentShowDanmaku") && alpha == 0.0) return;
    %orig(alpha);
}

%end

%hook IESLiveDanmakuVariousView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}

%end

%hook IESLiveDanmakuSupremeView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideLiveDanmaku")) {
        self.hidden = YES;
        return;
    }
    %orig;
}

%end

%hook AWEPlayDanmakuInputContainView

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSHideDanmuButton")) self.hidden = YES;
}

%end
