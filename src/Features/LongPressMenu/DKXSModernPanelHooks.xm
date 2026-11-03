//
//  DKXSModernPanelHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm「强制启用新版抖音长按 UI（现代风）」
//  三段 hook（AWELongPressPanelDataManager、AWELongPressPanelABSettings、
//  AWEModernLongPressPanelUIConfig），仅改名。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders，只给最小类声明。
//  冲突核查：DYxs src 里没有任何文件 hook 这 3 个类的方法，零冲突。
//  与第 4 批的划分：第 4 批做长按面板的菜单项/过滤（DKXSLongPressPanelHooks），
//  不含本文件的现代风开关与风格模式；两边无重叠。
//
//  偏离（39.6.0 实测修正）：上游 modernLongPressPanelStyleMode 在“仅开玻璃、
//  不开深色”与“仅开深色、不开玻璃”两种情况下都没有 return，属于上游原样缺口
//  （设置依赖里玻璃与深色互斥，玻璃单开是正常用法）。39.6.0 上只开玻璃时玻璃
//  完全不生效，且玻璃开关还被现代面板总开关 gate 住。改为：玻璃/深色任一开关
//  打开即独立于总开关生效，单开取样式 1（玻璃+深色共用的样式值）；三者全关
//  时返回原生样式。深色键 DKXSLongPressPanelDark 未登记，读不到即为 NO。
//

#import <UIKit/UIKit.h>
#import "DKXSUtils.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

@interface AWELongPressPanelDataManager : NSObject
+ (BOOL)enableModernLongPressPanelConfigWithSceneIdentifier:(id)arg1;
@end

@interface AWELongPressPanelABSettings : NSObject
+ (NSUInteger)modernLongPressPanelStyleMode;
@end

@interface AWEModernLongPressPanelUIConfig : NSObject
+ (NSUInteger)modernLongPressPanelStyleMode;
@end

%hook AWELongPressPanelDataManager
+ (BOOL)enableModernLongPressPanelConfigWithSceneIdentifier:(id)arg1 {
    return DKXSGetBool(@"DKXSEnableModernPanel");
}
%end

%hook AWELongPressPanelABSettings
+ (NSUInteger)modernLongPressPanelStyleMode {
    BOOL forceBlur = DKXSGetBool(@"DKXSLongPressPanelBlur");
    BOOL forceDark = DKXSGetBool(@"DKXSLongPressPanelDark");
    // 玻璃/深色开关独立于现代面板总开关：只开玻璃时此前直接返回原生样式，
    // 玻璃表现为完全不生效。任一单开都取玻璃样式 1（见文件头说明）。
    if (!DKXSGetBool(@"DKXSEnableModernPanel") && !forceBlur && !forceDark) {
        return %orig;
    }

    if (forceBlur || forceDark) {
        return 1;
    }
    BOOL isDarkMode = [DKXSUtils isDarkMode];
    return isDarkMode ? 1 : 2;
}
%end

%hook AWEModernLongPressPanelUIConfig
+ (NSUInteger)modernLongPressPanelStyleMode {
    BOOL forceBlur = DKXSGetBool(@"DKXSLongPressPanelBlur");
    BOOL forceDark = DKXSGetBool(@"DKXSLongPressPanelDark");
    if (!DKXSGetBool(@"DKXSEnableModernPanel") && !forceBlur && !forceDark) {
        return %orig;
    }

    if (forceBlur || forceDark) {
        return 1;
    }
    BOOL isDarkMode = [DKXSUtils isDarkMode];
    return isDarkMode ? 1 : 2;
}
%end

%ctor {
    %init;
}
