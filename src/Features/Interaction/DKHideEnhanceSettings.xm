//
//  DKHideEnhanceSettings.xm
//  DYxs
//
//  从 DYads-（DYYY）简单移植的第一批隐藏设置与增强设置。
//  设置键全部由 DYYY* 改为 DKXS*，与已移植的自动消息 / ABTest 保持同一命名规则。
//  本文件只登记设置行，不含 hook；hook 见 DKHideEnhanceHooks.xm。
//  未在 DYxs 设置布局表中登记的键会自动出现在设置页末尾的「未归类」分区。
//

#import "DKSettings.h"

%ctor {
    DKSettingsRegister(@"DKXSHideLikeButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLikeButton", @"隐藏点赞按钮", @"隐藏视频右侧的点赞按钮。");
    });
    DKSettingsRegister(@"DKXSHideLikeLabel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLikeLabel", @"隐藏点赞数值", @"只隐藏点赞数，保留点赞按钮和点击功能。");
    });
    DKSettingsRegister(@"DKXSHideCommentButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentButton", @"隐藏评论按钮", @"隐藏视频右侧的评论按钮。");
    });
    DKSettingsRegister(@"DKXSHideCommentLabel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentLabel", @"隐藏评论数值", @"只隐藏评论数，保留评论按钮和点击功能。");
    });
    DKSettingsRegister(@"DKXSHideShareButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideShareButton", @"隐藏分享按钮", @"隐藏视频右侧的分享按钮。");
    });
    DKSettingsRegister(@"DKXSHideShareLabel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideShareLabel", @"隐藏分享数值", @"只隐藏分享数，保留分享按钮和点击功能。");
    });
    DKSettingsRegister(@"DKXSHideCollectButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCollectButton", @"隐藏收藏按钮", @"隐藏视频右侧的收藏按钮。");
    });
    DKSettingsRegister(@"DKXSHideCollectLabel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCollectLabel", @"隐藏收藏数值", @"只隐藏收藏数，保留收藏按钮和点击功能。");
    });
    DKSettingsRegister(@"DKXSHideMusicButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMusicButton", @"隐藏音乐按钮", @"隐藏视频右下角的音乐唱片按钮。");
    });
    DKSettingsRegister(@"DKXSDisableAutoEnterLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSDisableAutoEnterLive", @"禁用自动进入直播", @"禁止顶栏直播下自动进入直播间。");
    });
    DKSettingsRegister(@"DKXSDisableAutoHideLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSDisableAutoHideLive", @"禁止直播标签收缩", @"禁止直播类型选择标签自动收缩成直播发现标签。");
    });
}
