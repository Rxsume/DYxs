//
//  DKXSBatch1Settings.xm
//  DYxs（staging，尚未并入 DYxs 源码）
//
//  全量合并第 1 批的设置登记 + 运行时 hook 启动。
//  参照 DYxs 已有写法（src/Features/Interaction/DKHideEnhanceSettings.xm）：
//  只用 DKSettingsRegister / DKMakeSwitch，不 import 上游 AwemeHeaders，
//  不搬上游 DYYYSettingsHelper / DYYYSettingViewController。
//  所有开关默认关（NSUserDefaults 未写入即为 NO），与已移植两批的做法一致。
//
//  运行时 hook 的安装与开关无关：DKXSStartHideMessageAndMinePageHooks
//  只安装替换函数，替换函数实时读设置，开关关闭时透传原实现
//  （这是上游的设计，本移植保持原样）。
//

#import "DKSettings.h"
#import "DKXSHideMessageAndMinePageHooks.h"

%ctor {
    DKSettingsRegister(@"DKXSHideRecommendAppDownload", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideRecommendAppDownload", @"隐藏推荐应用下载",
                            @"隐藏文案下推荐应用下载横幅与抖音精选底栏应用引流；不删作品文案与普通音乐信息。");
    });
    DKSettingsRegister(@"DKXSHideLiveRoomShareCompanion", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideLiveRoomShareCompanion", @"隐藏直播伴侣提示",
                            @"隐藏直播间分享面板中的直播伴侣下载提示。");
    });
    DKSettingsRegister(@"DKXSHideMessageTabStarMall", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMessageTabStarMall", @"隐藏消息星光商城",
                            @"隐藏消息页导航栏的星光商城入口。");
    });
    DKSettingsRegister(@"DKXSHideMineAvatarPlus", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMineAvatarPlus", @"隐藏我的页头像加号",
                            @"隐藏我的页头像上的加号（发布入口）。");
    });
    DKSettingsRegister(@"DKXSHideMineAICreation", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideMineAICreation", @"隐藏我的创作AI作品",
                            @"隐藏我的页创作列表中的 AI 作品。");
    });
    DKSettingsRegister(@"DKXSCommentPausePlayback", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSCommentPausePlayback", @"查看评论暂停播放",
                            @"打开评论区时暂停当前播放。");
    });

    DKXSStartHideMessageAndMinePageHooks();
}
