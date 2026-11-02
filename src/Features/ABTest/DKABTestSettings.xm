//
//  DKABTestSettings.xm
//  DYxs
//
//  从 DYads- 移植的 ABTest 远程配置的 DYxs 设置入口。
//  本文件不直接 import DKXSABTestHook 头文件，调用走 NSClassFromString，
//  避免 DKXSAwemeHeaders 与 DouyinHeaders 在同一编译单元重复声明。
//

#import "DKSettings.h"
// DKXSABTestHook.h 只 import Foundation，不带 Aweme 头文件，与 DouyinHeaders 无冲突，
// 但必须 import 它才能声明 +checkForRemoteConfigUpdate，否则第 27 行的动态调用
// 会被编译器报成未声明标识符（build #37 的错误）。
#import "DKXSABTestHook.h"

%ctor {
    DKSettingsRegister(@"DKXSABTestBlockEnabled", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeSwitch(@"DKXSABTestBlockEnabled", @"禁止 ABTest 下发",
                                               @"阻止抖音更新 ABTest 数据，本地固定配置除外。"),
                                  @"移植自 DYads- 的 ABTestHook：拦截 AWEABTestManager 的 setAbTestData。");
    });
    DKSettingsRegister(@"DKXSRemoteConfigURL", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeTextInput(@"DKXSRemoteConfigURL", @"远程 ABTest 配置地址",
                                                  @"https://github.com/Nathalie-Annis/AWEABTestDataPatch/releases/latest/download/ABTestDataPatch_A.json", 256),
                                  @"留空时用默认地址；只接受 https。下载的 JSON 只写到本地 abtest_data_fixed.json 并喂给抖音 ABTest 管理器，不上传数据。");
    });
    DKSettingsRegister(@"DKXSABTestCheckUpdate", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSABTestCheckUpdate", @"检查远程配置更新", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            Class hook = NSClassFromString(@"DKXSABTestHook");
            if ([hook respondsToSelector:@selector(checkForRemoteConfigUpdate:)]) [hook checkForRemoteConfigUpdate:YES];
        }));
    });
}
