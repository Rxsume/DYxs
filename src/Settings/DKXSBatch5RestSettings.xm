//
//  DKXSBatch5RestSettings.xm
//  DYxs 全量合并第 5 批剩余部分（5b–5e）staging，未并入 DYxs 源码。
//  登记口径与之前各批一致：%ctor 里用 DKSettingsRegister 登记，
//  开关默认关；数值类键按 helper 类型登记，见 REPORT 键表。
//  主 agent 落盘时把这 41 项并入 DKSettingsLayout.m 布局表，不得留未归类。
//
//  不在本文件登记的键（主 agent 复核必读）：
//  - DKXSDefaultSpeed / DKXSLongPressSpeed：第 2 批已有的 float 值键，
//    5b 只复用、不登记（登记成 Choice 会破坏倍速按钮的 float 读取）。
//  - DKXSFilterKeywords / DKXSFilterUsers：第 4 批已登记（长按面板过滤），
//    5c 模型级过滤共用同一批键，不重复登记。
//  - DKXSCommentBlurTransparent：第 4 批已登记，5d 通知毛玻璃复用其 alpha。
//  - DKXSLiveDurationCenterXPercent / CenterYPercent / PositionLocked：
//    开播时长悬浮窗的位置持久化值键，不登记。
//  - DKXSGeonamesUsername 登记在本文件（5e 国外解析账号，文本项）。
//
#import "DKSettings.h"

%ctor {
    // ---------- 5b 播放与速度 ----------
    DKSettingsRegister(@"DKXSEnableBackgroundListen", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableBackgroundListen", @"启用后台播放",
                            @"使受到后台播放限制的视频可以在后台继续播放。");
    });
    DKSettingsRegister(@"DKXSDisableCastVPNCheck", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSDisableCastVPNCheck", @"忽略投屏 VPN 检测",
                            @"开启后在连接 VPN 时也可以正常投屏。");
    });
    DKSettingsRegister(@"DKXSEnableLongPressSpeedGesture", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableLongPressSpeedGesture", @"上下控制倍速",
                            @"长按时可通过上下滑动调整倍速。");
    });
    DKSettingsRegister(@"DKXSEnableLiveRealCount", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableLiveRealCount", @"直播间真实人数",
                            @"直播间人数显示未缩写的真实值。");
    });
    DKSettingsRegister(@"DKXSShowLiveDuration", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSShowLiveDuration", @"开播时长",
                            @"直播间悬浮显示已开播时长，可拖动位置，位置会被记住。");
    });

    // ---------- 5c 过滤与屏蔽 ----------
    DKSettingsRegister(@"DKXSSkipLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipLive", @"推荐过滤直播",
                            @"推荐页跳过直播作品。");
    });
    DKSettingsRegister(@"DKXSSkipHotSpot", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipHotSpot", @"推荐过滤热点",
                            @"推荐页跳过热点卡片作品。");
    });
    DKSettingsRegister(@"DKXSSkipFriendsVideo", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipFriendsVideo", @"推荐过滤朋友视频",
                            @"推荐页跳过熟人视频。");
    });
    DKSettingsRegister(@"DKXSSkipPhotoText", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipPhotoText", @"推荐过滤图文",
                            @"推荐页跳过图文模式作品。");
    });
    DKSettingsRegister(@"DKXSSkipPhoto", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipPhoto", @"推荐过滤图集",
                            @"推荐页跳过图集作品。");
    });
    DKSettingsRegister(@"DKXSSkipMusic", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipMusic", @"推荐过滤音乐",
                            @"推荐页跳过音乐卡片作品。");
    });
    DKSettingsRegister(@"DKXSSkipAIInteraction", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipAIInteraction", @"推荐过滤 AI 互动",
                            @"推荐页跳过 AI 互动作品。");
    });
    DKSettingsRegister(@"DKXSSkipAllLive", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSkipAllLive", @"过滤直播中",
                            @"按“直播中”标签过滤，比推荐过滤直播覆盖更广。");
    });
    DKSettingsRegister(@"DKXSFilterLowLikes", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSFilterLowLikes", @"推荐过滤低赞", @"填0关闭", 12);
    });
    DKSettingsRegister(@"DKXSFilterTimeLimit", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSFilterTimeLimit", @"推荐视频时限", @"填0关闭，单位为天", 12);
    });
    DKSettingsRegister(@"DKXSFilterProp", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSFilterProp", @"过滤拍同款", @"逗号分隔道具名", 64);
    });
    DKSettingsRegister(@"DKXSHDRMode", ^AWESettingItemModel *{
        return DKMakeChoice(@"DKXSHDRMode", @"全局 HDR 设置",
                            @[ @"关闭", @"全局屏蔽 HDR 效果", @"全局过滤 HDR 作品" ]);
    });
    DKSettingsRegister(@"DKXSHideTeenMode", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideTeenMode", @"去青少年弹窗",
                            @"屏蔽青少年模式弹窗。");
    });
    DKSettingsRegister(@"DKXSDisableLivePCDN", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSDisableLivePCDN", @"禁用直播 PCDN 功能",
                            @"阻止直播 PCDN 启动任务。");
    });
    DKSettingsRegister(@"DKXSHideAntiAddictedNotice", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideAntiAddictedNotice", @"隐藏作者声明",
                            @"屏蔽作者声明及风险提示。");
    });

    // ---------- 5d 外观与透明度 ----------
    DKSettingsRegister(@"DKXSTopBarTransparent", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSTopBarTransparent", @"设置顶栏透明", @"0-1小数", 12);
    });
    DKSettingsRegister(@"DKXSGlobalTransparency", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSGlobalTransparency", @"设置全局透明", @"0-1小数", 12);
    });
    DKSettingsRegister(@"DKXSAvatarViewTransparency", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSAvatarViewTransparency", @"首页头像透明", @"0-1小数", 12);
    });
    DKSettingsRegister(@"DKXSVideoBGColor", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSVideoBGColor", @"视频背景颜色", @"十六进制", 12);
    });
    DKSettingsRegister(@"DKXSEnableNotificationTransparency", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableNotificationTransparency", @"通知玻璃效果",
                            @"应用内推送窗口加毛玻璃效果。");
    });
    DKSettingsRegister(@"DKXSNotificationCornerRadius", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSNotificationCornerRadius", @"通知圆角半径", @"默认12", 12);
    });
    DKSettingsRegister(@"DKXSElementScale", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSElementScale", @"右侧栏缩放度", @"不填默认", 12);
    });
    DKSettingsRegister(@"DKXSNicknameScale", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSNicknameScale", @"昵称文案缩放", @"不填默认", 12);
    });
    DKSettingsRegister(@"DKXSNicknameVerticalOffset", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSNicknameVerticalOffset", @"昵称下移距离", @"不填默认", 12);
    });
    DKSettingsRegister(@"DKXSDescriptionVerticalOffset", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSDescriptionVerticalOffset", @"文案下移距离", @"不填默认", 12);
    });
    DKSettingsRegister(@"DKXSIPLabelVerticalOffset", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSIPLabelVerticalOffset", @"属地上移距离", @"不填默认", 12);
    });
    DKSettingsRegister(@"DKXSTabBarHeight", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSTabBarHeight", @"修改底栏高度", @"默认为空", 12);
    });

    // ---------- 5e 杂项与二次确认 ----------
    DKSettingsRegister(@"DKXSEnableArea", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableArea", @"时间属地显示",
                            @"时间标签后追加 IP 属地。");
    });
    DKSettingsRegister(@"DKXSGeonamesUsername", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSGeonamesUsername", @"国外解析账号", @"需填写才能解析国外", 32);
    });
    DKSettingsRegister(@"DKXSLabelColor", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSLabelColor", @"属地标签颜色", @"十六进制", 12);
    });
    DKSettingsRegister(@"DKXSEnableRandomGradient", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableRandomGradient", @"属地随机渐变",
                            @"启用后覆盖上面的属地标签颜色（本移植为随机纯色，见 REPORT）。");
    });
    DKSettingsRegister(@"DKXSCommentExactTime", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSCommentExactTime", @"评论具体时间",
                            @"评论时间显示为 yyyy-MM-dd HH:mm:ss。");
    });
    DKSettingsRegister(@"DKXSEnableVideoHighestQuality", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableVideoHighestQuality", @"提高视频画质",
                            @"默认取最高比特率播放地址。");
    });
    DKSettingsRegister(@"DKXSHideStatusbar", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideStatusbar", @"隐藏系统顶栏",
                            @"播放、直播、详情、热点、图文、纯净页隐藏系统状态栏。");
    });
    DKSettingsRegister(@"DKXSFollowTips", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSFollowTips", @"关注二次确认",
                            @"点关注时先弹确认框。");
    });
    DKSettingsRegister(@"DKXSCollectTips", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSCollectTips", @"收藏二次确认",
                            @"点收藏时先弹确认框。");
    });
}
