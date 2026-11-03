//
//  DKXSBatch4Settings.xm
//  DYxs（第 4 批 staging，尚未并入 DYxs 源码）
//
//  第 4 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 1、2 批同款写法）。全部默认关。
//  登记 18 项，全部在本批有读取方（见 REPORT.md 键表；
//  刻意不登记的键也在 REPORT.md 里列出原因，杜绝登记了没人读的死键）：
//  毛玻璃 2 项、长按新增功能 5 项、精简 1 项、隐藏面板文本 1 项、
//  评论长按隐藏 9 项。
//  透明度用 DKMakeTextInput 存“0-1小数”字符串（上游同款 cellType 26 文本项），
//  因为协调器读的是 floatValue：若用 0-100 滑条存整数 90，floatValue 得 90
//  会触发 >1 缺省 0.9，滑条等于没用。
//  隐藏面板文本用 DKMakeTextInput（上游同款文本输入项）。
//
#import "DKSettings.h"

%ctor {
    DKSettingsRegister(@"DKXSEnableCommentBlur", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableCommentBlur", @"评论区毛玻璃",
                            @"评论面板跟随实际面板铺毛玻璃；关开关时恢复原生背景。");
    });
    DKSettingsRegister(@"DKXSCommentBlurTransparent", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSCommentBlurTransparent", @"毛玻璃透明度", @"0-1小数，例如 0.9", 32);
    });
    DKSettingsRegister(@"DKXSLongPressCopyText", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressCopyText", @"长按复制视频文案",
                            @"长按面板出现「复制文案」，复制作品文案到剪贴板。");
    });
    DKSettingsRegister(@"DKXSLongPressCopyLink", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressCopyLink", @"长按复制分享链接",
                            @"长按面板出现「复制链接」，复制去掉 ? 后参数的分享链接。");
    });
    DKSettingsRegister(@"DKXSLongPressFilterUser", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressFilterUser", @"长按面板过滤用户",
                            @"长按面板出现「过滤用户」，把当前作者加入过滤列表。");
    });
    DKSettingsRegister(@"DKXSLongPressFilterTitle", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressFilterTitle", @"长按面板过滤文案",
                            @"长按面板出现「过滤文案」，把输入的关键词加入过滤词列表。");
    });
    DKSettingsRegister(@"DKXSLongPressTimerClose", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressTimerClose", @"长按定时关闭抖音",
                            @"长按面板出现「定时关闭」，到时弹窗确认后关闭抖音。");
    });
    DKSettingsRegister(@"DKXSSimplifyLongPressPanel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSimplifyLongPressPanel", @"精简长按面板",
                            @"开启后隐藏所有原始面板选项，只保留自定义功能与 DYxs 保存项。");
    });
    DKSettingsRegister(@"DKXSHidePanelItems", ^AWESettingItemModel *{
        // 隐藏面板项目不限长度：maxWidth 传 0，写多少个项目都存得下。
        return DKMakeTextInput(@"DKXSHidePanelItems", @"隐藏面板项目", @"例如：举报,倍速,投屏,弹幕", 0);
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressFavorite", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressFavorite", @"隐藏评论收藏",
                            @"隐藏评论长按面板中的收藏项。");
    });
    DKSettingsRegister(@"DKXSHideCommentShareToFriends", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentShareToFriends", @"隐藏评论分享",
                            @"隐藏评论分享里的好友横排入口。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressCopy", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressCopy", @"隐藏评论复制",
                            @"隐藏评论长按面板中的复制项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressSaveImage", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressSaveImage", @"隐藏评论保存",
                            @"隐藏评论长按面板中的保存图片项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressReport", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressReport", @"隐藏评论举报",
                            @"隐藏评论长按面板中的举报项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressSearch", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressSearch", @"隐藏评论搜索",
                            @"隐藏评论长按面板中的搜索项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressDaily", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressDaily", @"隐藏评论转发日常",
                            @"隐藏评论长按面板中的转发日常项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressVideoReply", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressVideoReply", @"隐藏评论视频回复",
                            @"隐藏评论长按面板中的视频回复项。");
    });
    DKSettingsRegister(@"DKXSHideCommentLongPressPictureSearch", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLongPressPictureSearch", @"隐藏评论识别图片",
                            @"隐藏评论长按面板中的识别图片项。");
    });
}
