//
//  DKXSProgressScheduleHooks.xm
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//
//  上游来源：DYYY.xm 的进度时长标签实现（AWEFeedProgressSlider 的 dyyy_* %new 方法、
//  AWEPlayInteractionProgressController 的同步、UIView 的 legacy 回退路径）。
//  改名：dyyy_* → dkxs_*；设置键 DYYY* → DKXS*（经 DKXSProgressScheduleLabel.h 读取）。
//
//  与现有文件的分工（不要重复建 hook）：
//  · AWEFeedProgressSlider setAlpha / setHidden、AWEDProgressCoreContainer
//    updateProgressSliderWithTime:totalDuration: 已由 DKProgressTime.xm hook，
//    本批只给 DKProgressTime.xm 一个 .merge 片段（DKXSProgressScheduleTime.merge），
//    不要在这里再 hook 这三个方法，否则同一方法两处 %hook 虽能走 %orig 链，
//    但两处各写一份 alpha/hidden 逻辑会互相顶。
//  · AWEFeedProgressSlider layoutSubviews、AWEDPlayerProgressContainerView
//    layoutSubviews、AWEPlayInteractionProgressContainerView layoutSubviews 在上游
//    只有清屏进度调用（第 2 批已由 DKXSFloatClearButton 的遍历机制覆盖）
//    与全屏背景清除（第 6 批 DYYYEnableFullScreen），本批无内容，不建 hook。
//  · AWEPlayInteractionProgressController 在 DouyinHeaders.h 里没有声明，
//    这里只给最小 @interface（第 2、4 批同款做法）；方法内一律走
//    valueForKey / respondsToSelector，不直接访问未声明的属性。
//

#import "DouyinHeaders.h"
#import "DKXSProgressScheduleLabel.h"

// DouyinHeaders.h 未声明的类：最小声明，不 import 上游 AwemeHeaders。
@interface AWEPlayInteractionProgressController : NSObject
@end

// 本文件内 %new 方法的声明（供跨方法调用；同一 @implementation 内其实可见，
// 写出来是为了让 .merge 那边的调用方照抄这段声明时口径一致）。
@interface AWEFeedProgressSlider (DKXSProgressSchedule)
- (NSString *)dkxs_formatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dkxs_modelDurationInSeconds;
- (CGFloat)dkxs_scheduleVerticalOffset;
- (void)dkxs_removeScheduleLabels;
- (void)dkxs_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface UIView (DKXSProgressLabelLegacy)
- (NSString *)dkxs_legacyFormatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dkxs_legacyScheduleVerticalOffset;
- (CGFloat)dkxs_legacyModelDurationInSeconds:(id)model;
- (void)dkxs_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model;
@end

@implementation UIView (DKXSProgressLabelLegacy)

- (NSString *)dkxs_legacyFormatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) safeSeconds = 0;
    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

- (CGFloat)dkxs_legacyScheduleVerticalOffset {
    return DKXSProgressVerticalOffset();
}

- (CGFloat)dkxs_legacyModelDurationInSeconds:(id)model {
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) return 0;
    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) return 0;
    return videoDurationMs / 1000.0;
}

// 上游 legacy 路径原样：只有当进度条不是 AWEFeedProgressSlider（因而没有
// dkxs_updateScheduleLabelsWithCurrentTime:totalDuration:）时才走这里。
// 标签逻辑与主路径一致（左/右标签 tag 10001/10002，8pt 字，颜色缺省白色）。
- (void)dkxs_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model {
    if (!DKXSProgressScheduleOn()) {
        UIView *parentView = self.superview;
        if (parentView) {
            [[parentView viewWithTag:10001] removeFromSuperview];
            [[parentView viewWithTag:10002] removeFromSuperview];
        }
        return;
    }
    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf dkxs_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
        });
        return;
    }
    UIView *parentView = self.superview;
    if (!parentView) return;
    NSString *scheduleStyle = DKXSProgressScheduleStyleString();
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];
    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;
    CGFloat modelDuration = [self dkxs_legacyModelDurationInSeconds:model];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) effectiveTotalDuration = 0;
    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) effectiveCurrentTime = 0;
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) effectiveCurrentTime = effectiveTotalDuration;
    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) return;
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dkxs_legacyScheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    UIColor *labelColor = DKXSProgressLabelColor() ?: [UIColor whiteColor];
    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) { [leftLabel removeFromSuperview]; leftLabel = nil; }
    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }
        leftLabel.font = labelFont;
        leftLabel.textColor = labelColor;
        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dkxs_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dkxs_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dkxs_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dkxs_legacyFormatTimeFromSeconds:effectiveCurrentTime];
        }
        if (![leftLabel.text isEqualToString:newLeftText]) leftLabel.text = newLeftText;
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
    } else {
        [leftLabel removeFromSuperview];
    }
    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) { [rightLabel removeFromSuperview]; rightLabel = nil; }
    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }
        rightLabel.font = labelFont;
        rightLabel.textColor = labelColor;
        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dkxs_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dkxs_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dkxs_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dkxs_legacyFormatTimeFromSeconds:effectiveTotalDuration];
        }
        if (![rightLabel.text isEqualToString:newRightText]) rightLabel.text = newRightText;
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
    } else {
        [rightLabel removeFromSuperview];
    }
}

@end

%hook AWEFeedProgressSlider

%new
- (NSString *)dkxs_formatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) safeSeconds = 0;
    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

%new
- (CGFloat)dkxs_modelDurationInSeconds {
    id delegate = self.progressSliderDelegate;
    if (!delegate || ![delegate respondsToSelector:@selector(model)]) return 0;
    id model = [delegate valueForKey:@"model"];
    if (!model || ![model respondsToSelector:@selector(videoDuration)]) return 0;
    CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
    if (videoDurationMs <= 0) return 0;
    return videoDurationMs / 1000.0;
}

%new
- (CGFloat)dkxs_scheduleVerticalOffset {
    return DKXSProgressVerticalOffset();
}

%new
- (void)dkxs_removeScheduleLabels {
    UIView *parentView = self.superview;
    if (!parentView) return;
    [[parentView viewWithTag:10001] removeFromSuperview];
    [[parentView viewWithTag:10002] removeFromSuperview];
}

%new
- (void)dkxs_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DKXSProgressScheduleOn()) {
        [self dkxs_removeScheduleLabels];
        return;
    }
    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf dkxs_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
        });
        return;
    }
    UIView *parentView = self.superview;
    if (!parentView) return;
    NSString *scheduleStyle = DKXSProgressScheduleStyleString();
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];
    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;
    CGFloat modelDuration = [self dkxs_modelDurationInSeconds];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) effectiveTotalDuration = 0;
    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) effectiveCurrentTime = 0;
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) effectiveCurrentTime = effectiveTotalDuration;
    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) return;
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dkxs_scheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    // 上游用 DYYYUtils applyColorSettingsToLabel（attributed 换色，支持 random/渐变等 scheme）；
    // 本移植的进度标签颜色是十六进制文本项，只做 hex → textColor，空或非法时白色（与上游 fallback 一致）。
    UIColor *labelColor = DKXSProgressLabelColor() ?: [UIColor whiteColor];
    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) { [leftLabel removeFromSuperview]; leftLabel = nil; }
    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }
        leftLabel.font = labelFont;
        leftLabel.textColor = labelColor;
        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dkxs_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dkxs_formatTimeFromSeconds:effectiveCurrentTime], [self dkxs_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dkxs_formatTimeFromSeconds:effectiveCurrentTime];
        }
        if (![leftLabel.text isEqualToString:newLeftText]) leftLabel.text = newLeftText;
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
    } else {
        [leftLabel removeFromSuperview];
    }
    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) { [rightLabel removeFromSuperview]; rightLabel = nil; }
    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }
        rightLabel.font = labelFont;
        rightLabel.textColor = labelColor;
        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dkxs_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dkxs_formatTimeFromSeconds:effectiveCurrentTime], [self dkxs_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dkxs_formatTimeFromSeconds:effectiveTotalDuration];
        }
        if (![rightLabel.text isEqualToString:newRightText]) rightLabel.text = newRightText;
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
    } else {
        [rightLabel removeFromSuperview];
    }
}

// 上游原样：布局策略上限动作区变化时，用 0/0 刷一次标签（触发关开关时清标签）。
- (void)setLimitUpperActionArea:(BOOL)arg1 {
    %orig;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf dkxs_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
    });
}

%end

%hook AWEPlayInteractionProgressController

%new
- (void)dkxs_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DKXSProgressScheduleOn()) return;
    id progressSlider = [self valueForKey:@"progressSlider"];
    if (progressSlider && [progressSlider respondsToSelector:@selector(dkxs_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dkxs_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
        return;
    }
    id model = nil;
    if ([self respondsToSelector:@selector(model)]) model = [self valueForKey:@"model"];
    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dkxs_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dkxs_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end
