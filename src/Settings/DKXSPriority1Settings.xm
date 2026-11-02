//
//  DKXSPriority1Settings.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  用户点名的 14 个键，全部 DYYY* -> DKXS* 改名，全部默认关/默认空。
//  参照 DYxs 已有写法（src/Features/Interaction/DKHideEnhanceSettings.xm）：
//  %ctor + DKSettingsRegister；开关用 DKMakeSwitch，选项用 DKMakeChoice，
//  文字用 DKMakeTextInput。不 import 上游 AwemeHeaders，不搬上游设置体系。
//
//  注意 DKMakeChoice 存的是选项下标（整数），不是字符串：
//  DKXSLiveQuality 的选项顺序固定为 [自动, 蓝光帧彩, 蓝光, 超清, 高清, 标清]，
//  下标 0 = 自动（跳过），LiveQuality hook 按下标换算成上游的画质名字符串。
//  上游存的是字符串，新键从 DKXS 起用下标存法，不存在旧值迁移问题。
//

#import "DKSettings.h"

%ctor {
    DKSettingsRegister(@"DKXSLiveQuality", ^AWESettingItemModel *{
        return DKMakeChoice(@"DKXSLiveQuality", @"默认直播画质",
                            @[ @"自动", @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清" ]);
    });
    DKSettingsRegister(@"DKXSEnableAutoPlay", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableAutoPlay", @"启用自动播放",
                            @"个人主页作品自动播放。");
    });
    DKSettingsRegister(@"DKXSEnableModernPanel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableModernPanel", @"启用新版长按面板",
                            @"强制启用新版抖音长按面板。");
    });
    DKSettingsRegister(@"DKXSLongPressPanelBlur", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSLongPressPanelBlur", @"长按面板玻璃效果",
                            @"新版长按面板的玻璃风格（与深色模式键互斥，上游原样；深色键本批未登记，默认关）。");
    });
    DKSettingsRegister(@"DKXSEnableSheetBlur", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableSheetBlur", @"保存面板玻璃效果",
                            @"给保存/操作面板加毛玻璃效果与白色文字。");
    });
    DKSettingsRegister(@"DKXSSheetBlurTransparent", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSSheetBlurTransparent", @"面板毛玻璃透明度", @"0-1小数", 16);
    });
    DKSettingsRegister(@"DKXSInterfaceDownload", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSInterfaceDownload", @"接口解析保存媒体", @"不填关闭", 128);
    });
    DKSettingsRegister(@"DKXSShowAllVideoQuality", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSShowAllVideoQuality", @"接口显示清晰选项",
                            @"接口解析到多清晰度/多资源时弹出选择，否则直接下载。");
    });
    DKSettingsRegister(@"DKXSModifyTopTabText", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSModifyTopTabText", @"设置顶栏标题", @"标题=修改#标题=修改", 128);
    });
    DKSettingsRegister(@"DKXSIndexTitle", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSIndexTitle", @"设置首页标题", @"不填默认", 40);
    });
    DKSettingsRegister(@"DKXSFriendsTitle", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSFriendsTitle", @"设置朋友标题", @"不填默认", 40);
    });
    DKSettingsRegister(@"DKXSMsgTitle", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSMsgTitle", @"设置消息标题", @"不填默认", 40);
    });
    DKSettingsRegister(@"DKXSSelfTitle", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSSelfTitle", @"设置我的标题", @"不填默认", 40);
    });
}
