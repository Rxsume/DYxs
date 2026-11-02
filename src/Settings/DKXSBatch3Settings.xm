//
//  DKXSBatch3Settings.xm
//  DYxs — 第 3 批 staging（尚未并入 DYxs 源码）
//  全量合并第 3 批（隐藏剩余：底栏/顶栏、侧边栏/消息页/搜索与关注、头像/文案/直播间）的设置登记。
//  参照第 1、2 批写法：%ctor + DKSettingsRegister + DKMakeSwitch，只登记本批新增的开关。
//  全部默认关（NSUserDefaults 未写入即为 NO）。布局入表建议见同目录 REPORT.md。
//  注意：本文件登记的 59 个键中，合并片段（.merge）里的键在片段并入现有文件前不会生效；
//  独立文件（.xm）里的键随本文件一起上传即生效。不要只传本文件不传 hook 文件。
//

#import "DKSettings.h"

%ctor {
    // ---------- 3a：底栏与顶栏 ----------
    DKSettingsRegister(@"DKXSHideBottomDot", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideBottomDot", @"隐藏底栏红点", @"隐藏底栏上的红点角标。");
    });
    DKSettingsRegister(@"DKXSHideDoubleColumnEntry", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideDoubleColumnEntry", @"隐藏双列箭头", @"隐藏底栏双列入口箭头。");
    });
    DKSettingsRegister(@"DKXSHideShopButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideShopButton", @"隐藏底栏商城", @"隐藏底栏商城按钮。");
    });
    DKSettingsRegister(@"DKXSHideMessageButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMessageButton", @"隐藏底栏消息", @"隐藏底栏消息按钮。");
    });
    DKSettingsRegister(@"DKXSHideFriendsButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideFriendsButton", @"隐藏底栏朋友", @"隐藏底栏朋友按钮。");
    });
    DKSettingsRegister(@"DKXSHidePlusButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePlusButton", @"隐藏底栏加号", @"隐藏底栏中间加号按钮。");
    });
    DKSettingsRegister(@"DKXSHideMyButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMyButton", @"隐藏底栏我的", @"隐藏底栏我的按钮。");
    });
    DKSettingsRegister(@"DKXSHideComment", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideComment", @"隐藏底栏评论", @"上游标题如此；实现为移除评论输入背景视图（见 REPORT.md）。");
    });
    DKSettingsRegister(@"DKXSHideHotSearch", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideHotSearch", @"隐藏底栏热榜", @"隐藏热搜底部视图。");
    });
    DKSettingsRegister(@"DKXSHidePadTabBarElements", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePadTabBarElements", @"精简平板底栏", @"隐藏平板底栏元素容器。");
    });
    DKSettingsRegister(@"DKXSHideEntry", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideEntry", @"隐藏全屏观看", @"隐藏全屏观看入口（原始位置仍可点击）。");
    });
    DKSettingsRegister(@"DKXSRemoveEntry", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSRemoveEntry", @"移除全屏观看", @"完全移除全屏观看入口，不可点击。");
    });

    // ---------- 3b：侧边栏、消息页、搜索与关注 ----------
    DKSettingsRegister(@"DKXSHideLeftSideBar", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLeftSideBar", @"隐藏左侧边栏", @"隐藏左侧边栏入口图标。");
    });
    DKSettingsRegister(@"DKXSHideSidebarDot", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSidebarDot", @"隐藏侧栏红点", @"隐藏侧边栏与顶栏 CTA 的红点。");
    });
    DKSettingsRegister(@"DKXSHideSidebarRecentApps", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSidebarRecentApps", @"隐藏常用小程序", @"隐藏侧边栏常用小程序模块；开任一侧栏精简开关时侧栏顶区只保留天气、设置、扫一扫（见 REPORT.md）。");
    });
    DKSettingsRegister(@"DKXSHideSidebarRecentUsers", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSidebarRecentUsers", @"隐藏常访问的人", @"隐藏侧边栏常访问的人模块；同上，顶区副作用见 REPORT.md。");
    });
    DKSettingsRegister(@"DKXSHideAvatarList", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideAvatarList", @"隐藏消息头像列表", @"隐藏消息页头像列表（将其高度压到最小）。");
    });
    DKSettingsRegister(@"DKXSHideAvatarBubble", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideAvatarBubble", @"隐藏消息头像气泡", @"隐藏消息头像气泡。");
    });
    DKSettingsRegister(@"DKXSHideMessageTabRedPacket", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMessageTabRedPacket", @"隐藏消息顶栏红包", @"隐藏消息页顶栏红包入口。");
    });
    DKSettingsRegister(@"DKXSHidePushBanner", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePushBanner", @"隐藏通知权限提示", @"隐藏消息页开启通知提示条。");
    });
    DKSettingsRegister(@"DKXSHideButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideButton", @"隐藏我的添加朋友", @"隐藏我的页添加朋友按钮。");
    });
    DKSettingsRegister(@"DKXSHideFamiliar", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideFamiliar", @"隐藏朋友日常按钮", @"隐藏朋友关注/不关注按钮与朋友日常按钮。");
    });
    DKSettingsRegister(@"DKXSHideShareContentView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideShareContentView", @"隐藏分享提示", @"隐藏分享给朋友提示。");
    });
    DKSettingsRegister(@"DKXSHideGroupShop", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGroupShop", @"隐藏群聊商店按钮", @"隐藏群聊商店按钮。");
    });
    DKSettingsRegister(@"DKXSHideGroupLiveIndicator", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGroupLiveIndicator", @"隐藏群头像直播中", @"隐藏群头像直播中提示。");
    });
    DKSettingsRegister(@"DKXSHideGroupInputActionBar", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGroupInputActionBar", @"隐藏聊天页工具栏", @"隐藏群聊天输入框上方快捷方式栏。");
    });
    DKSettingsRegister(@"DKXSHideReply", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideReply", @"隐藏底部私信回复", @"隐藏底部私信回复输入区。");
    });
    DKSettingsRegister(@"DKXSHidePostView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePostView", @"隐藏我的页发作品", @"隐藏我的页发作品引导区。");
    });
    DKSettingsRegister(@"DKXSHideInteractionSearch", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideInteractionSearch", @"隐藏相关搜索", @"隐藏相关搜索入口。");
    });
    DKSettingsRegister(@"DKXSHideSearchBubble", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSearchBubble", @"隐藏弹出热搜", @"隐藏弹出热搜入口。");
    });
    DKSettingsRegister(@"DKXSHideSearchSame", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSearchSame", @"隐藏搜索同款", @"隐藏搜索同款入口。");
    });
    DKSettingsRegister(@"DKXSHideSearchEntrance", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSearchEntrance", @"隐藏顶部搜索框", @"隐藏视频顶部搜索框。");
    });
    DKSettingsRegister(@"DKXSHideSearchEntranceIndicator", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSearchEntranceIndicator", @"隐藏搜索框背景", @"隐藏搜索框背景图。");
    });
    DKSettingsRegister(@"DKXSHideDiscover", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideDiscover", @"隐藏右上搜索", @"隐藏右上搜索图标（仍可点击）。");
    });
    DKSettingsRegister(@"DKXSHideLiveView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLiveView", @"隐藏关注顶端", @"隐藏关注顶端直播入口。");
    });
    DKSettingsRegister(@"DKXSHideConcernCapsuleView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideConcernCapsuleView", @"隐藏关注直播", @"隐藏关注直播胶囊。");
    });
    DKSettingsRegister(@"DKXSHideMenuView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMenuView", @"隐藏同城顶端", @"隐藏同城顶端入口。");
    });
    DKSettingsRegister(@"DKXSHideNearbyCapsuleView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideNearbyCapsuleView", @"隐藏吃喝玩乐", @"隐藏吃喝玩乐胶囊。");
    });
    DKSettingsRegister(@"DKXSHideEnterLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideEnterLive", @"隐藏点击进入直播间", @"隐藏点击进入直播间入口。");
    });
    DKSettingsRegister(@"DKXSHideLiveCapsuleView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLiveCapsuleView", @"隐藏直播提示", @"隐藏直播胶囊提示。");
    });
    // 顶栏频道移除（共享 AWEFeedChannelManager 一个方法，必须整块并入 DKTopChannelFilter，见 REPORT.md）
    DKSettingsRegister(@"DKXSHideHotContainer", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideHotContainer", @"移除推荐", @"移除顶栏推荐频道。");
    });
    DKSettingsRegister(@"DKXSHideFollow", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideFollow", @"移除关注", @"移除顶栏关注频道。注意：这不是“文案关注”，文案关注对应头像加号两键（见 REPORT.md）。");
    });
    DKSettingsRegister(@"DKXSHideFriend", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideFriend", @"移除朋友", @"移除顶栏朋友频道。");
    });
    DKSettingsRegister(@"DKXSHideMediumVideo", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMediumVideo", @"移除长视频", @"移除顶栏长视频频道。");
    });
    DKSettingsRegister(@"DKXSHideMall", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMall", @"移除商城", @"移除顶栏商城频道。");
    });
    DKSettingsRegister(@"DKXSHideNearby", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideNearby", @"移除同城", @"移除顶栏同城频道。");
    });
    DKSettingsRegister(@"DKXSHideGroupon", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGroupon", @"移除团购", @"移除顶栏团购频道。");
    });
    DKSettingsRegister(@"DKXSHideTabLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideTabLive", @"移除直播", @"移除顶栏直播频道。");
    });
    DKSettingsRegister(@"DKXSHidePadHot", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePadHot", @"移除热点", @"移除顶栏热点频道。");
    });
    DKSettingsRegister(@"DKXSHideHangout", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideHangout", @"移除经验", @"移除顶栏经验频道。");
    });
    DKSettingsRegister(@"DKXSHidePlaylet", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePlaylet", @"移除短剧", @"移除顶栏短剧频道。");
    });
    DKSettingsRegister(@"DKXSHideCinema", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCinema", @"移除看剧", @"移除顶栏看剧频道。");
    });
    DKSettingsRegister(@"DKXSHideKidsV2", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideKidsV2", @"移除少儿", @"移除顶栏少儿频道。");
    });
    DKSettingsRegister(@"DKXSHideGame", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGame", @"移除游戏", @"移除顶栏游戏频道。");
    });

    // ---------- 3c：头像、文案与直播间 ----------
    DKSettingsRegister(@"DKXSHideAvatarButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideAvatarButton", @"隐藏头像及周边", @"隐藏头像及周边视觉；周边强制隐藏需第 6 批全局 hook 补齐（见 REPORT.md）。");
    });
    DKSettingsRegister(@"DKXSHideAvatarLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideAvatarLive", @"隐藏头像直播提示", @"隐藏头像直播提示；实现为 roomID 返回 0（见 REPORT.md）。");
    });
    DKSettingsRegister(@"DKXSHideLOTAnimationView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLOTAnimationView", @"隐藏头像加号", @"隐藏头像加号，原始位置仍可点击；与移除头像加号互斥（上游设定）。");
    });
    DKSettingsRegister(@"DKXSHideFollowPromptView", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideFollowPromptView", @"移除头像加号", @"完全移除头像加号，不可点击；与隐藏头像加号互斥（上游设定）。");
    });
    DKSettingsRegister(@"DKXSHideGradient", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideGradient", @"隐藏遮罩效果", @"隐藏遮罩渐变效果。");
    });
}
