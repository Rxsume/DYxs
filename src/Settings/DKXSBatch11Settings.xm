//
//  DKXSBatch11Settings.xm
//  DYxs（第 11 批：Si-yi/DYads- 7083bae 新模块移植）
//
//  第 11 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 7/8/9/10 批同款写法）。1 个开关默认关。
//  登记 1 项，在本批有读取方（DKXSNativeGridRoute）：
//  双列作品全屏打开。
//  改名一律 DYYY -> DKXS（键与类名同步改名，见各模块文件头）。
//  注意：上游的设置行构建方法不移植，行改由本文件登记；
//  本开关上游默认开，DYxs 移植惯例默认关，不跟随。
//  开关切换时重置本会话的路由失败停用状态，下次点击重新尝试。
//

#import "DKSettings.h"
#import "DKXSNativeGridRoute.h"

%ctor {
    DKSettingsRegister(@"DKXSEnableNativeGridFullscreen", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableNativeGridFullscreen", @"双列作品全屏打开",
                                                 @"使用原生全屏路由打开图文和视频；关闭恢复默认入口。仅在首页双列当前可见的卡片上生效，直播不走此入口；入口异常时自动恢复默认打开方式。");
        DKSettingsOnChange(item, ^{ [DKXSNativeGridRoute resetFailure]; });
        return item;
    });
}
