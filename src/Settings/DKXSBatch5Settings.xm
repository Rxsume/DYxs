//
//  DKXSBatch5Settings.xm
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//  %ctor + DKSettingsRegister + DKMakeSwitch / DKMakeChoice / DKMakeTextInput，
//  与第 1、2、4 批同款写法。全部默认关。
//  注意 DKMakeChoice 存的是选项下标（整数），不是字符串：
//  DKXSScheduleStyle 的选项顺序固定为 [进度条两侧上下, 进度条左侧剩余,
//  进度条左侧完整, 进度条右侧剩余, 进度条右侧完整]，
//  DKXSProgressScheduleLabel.m 按此顺序换算回上游比对用的中文字符串。
//  未设置时返回 nil，hook 按上游默认行为处理（两侧都显示：左=当前、右=总长）。
//  文字项用 DKMakeTextInput 存字符串：进度标签颜色是十六进制文本，
//  进度纵轴位置是数字文本（上游同款 cellType 26 文本项）；
//  纵轴为 0 时上游仍取缺省 -12.5，见 DKXSProgressScheduleLabel.m 注释。
//

#import "DKSettings.h"

%ctor {
    DKSettingsRegister(@"DKXSShowScheduleDisplay", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSShowScheduleDisplay", @"显示进度时长",
                            @"强制显示所有视频的进度条和时长。进度条两侧出现时长标签，样式由下方进度时长样式控制。");
    });
    DKSettingsRegister(@"DKXSScheduleStyle", ^AWESettingItemModel *{
        return DKMakeChoice(@"DKXSScheduleStyle", @"进度时长样式",
                            @[ @"进度条两侧上下", @"进度条左侧剩余", @"进度条左侧完整", @"进度条右侧剩余", @"进度条右侧完整" ]);
    });
    DKSettingsRegister(@"DKXSProgressLabelColor", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSProgressLabelColor", @"进度标签颜色", @"十六进制，例如 #FFFFFF", 16);
    });
    DKSettingsRegister(@"DKXSTimelineVerticalPosition", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSTimelineVerticalPosition", @"进度纵轴位置", @"-12.5", 16);
    });
    DKSettingsRegister(@"DKXSHideVideoProgress", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideVideoProgress", @"隐藏视频进度",
                            @"隐藏视频进度条。需同时开显示进度时长时，进度条本体隐藏、时长标签继续显示。");
    });
    DKSettingsRegister(@"DKXSHideStoryProgressSlide", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideStoryProgressSlide", @"隐藏视频滑条",
                            @"隐藏图文作品底部的视频滑条。");
    });
    DKSettingsRegister(@"DKXSHideDotsIndicator", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideDotsIndicator", @"隐藏图片滑条",
                            @"隐藏图文作品底部的图片分段圆点指示器。");
    });
    DKSettingsRegister(@"DKXSHideChapterProgress", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideChapterProgress", @"隐藏章节进度",
                            @"隐藏可能出现在视频上方或者下方的章节进度条。");
    });
    DKSettingsRegister(@"DKXSCommentShowDanmaku", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSCommentShowDanmaku", @"查看评论显示弹幕",
                            @"打开评论区时保持弹幕可见。开着时连全屏评论区也保持可见，会覆盖 DYxs 原有的全屏评论区原生行为。");
    });
    DKSettingsRegister(@"DKXSHideLiveDanmaku", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLiveDanmaku", @"隐藏滚动弹幕",
                            @"隐藏直播间管理员发送的特殊横向滚动弹幕。");
    });
    DKSettingsRegister(@"DKXSHideDanmuButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideDanmuButton", @"隐藏弹幕按钮",
                            @"隐藏播放页的弹幕按钮。");
    });
}
