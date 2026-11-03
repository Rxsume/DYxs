//
//  DKXSBatch7Settings.xm
//  DYxs（第 7 批：Si-yi/DYads- fb78fd91 新模块移植）
//
//  第 7 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 1、2、4、6 批同款写法）。全部默认关。
//  登记 4 项，全部在本批有读取方：
//  首页限时日常过滤、头像光圈、音乐文字、屏蔽展开视频缩放。
//  改名一律 DYYY -> DKXS（键与类名同步改名，见各模块文件头）。
//  注意：昵称上方标签玻璃（DKXSFeedTagGlass）无开关、始终生效，故不登记；
//  其余 DYads- 模块或已在 DYxs 有等价实现、或与现有 hook 冲突，见本批说明，均未登记。
//

#import "DKSettings.h"
#import "DKXSHomeDailyFilter.h"
#import "DKXSAvatarRing.h"
#import "DKXSSameStyleVisibility.h"
#import "DKXSCommentVideoLayout.h"

%ctor {
    DKSettingsRegister(@"DKXSHideHomeDaily", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideHomeDaily", @"隐藏限时日常",
                            @"过滤首页的限时日常作品，修改后重启抖音生效。");
    });
    DKSettingsRegister(@"DKXSHideAvatarColorRing", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSHideAvatarColorRing", @"隐藏头像光圈",
                                                 @"仅隐藏彩色光圈，保留头像和原有点击动作。");
        DKSettingsOnChange(item, ^{ [DKXSAvatarRing refreshVisibleRings]; });
        return item;
    });
    DKSettingsRegister(@"DKXSHideSameStyleButton", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSHideSameStyleButton", @"隐藏音乐文字",
                                                 @"隐藏右下角音乐图标上的所有文字，保留图标和点击功能。");
        DKSettingsOnChange(item, ^{ [DKXSSameStyleVisibility refreshVisibleViews]; });
        return item;
    });
    DKSettingsRegister(@"DKXSDisableCommentVideoShrink", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSDisableCommentVideoShrink", @"屏蔽展开视频缩放",
                                                 @"展开评论区时，视频保持原尺寸，评论面板覆盖在画面上。");
        DKSettingsOnChange(item, ^{ [DKXSCommentVideoLayout refreshVisiblePlayers]; });
        return item;
    });
}
