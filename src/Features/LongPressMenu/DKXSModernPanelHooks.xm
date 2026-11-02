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
//  偏离（必须真机验证，见 REPORT）：上游 modernLongPressPanelStyleMode
//  在“仅开玻璃、不开深色”与“仅开深色、不开玻璃”两种情况下都没有 return，
//  属于上游原样缺口（设置依赖里玻璃与深色互斥，玻璃单开是正常用法）。
//  本移植把单开情况明确返回 2（上游已定义的另一个风格值；不开玻璃不开深色
//  且浅色模式时也是 2），避免未定义返回值。深色键 DKXSLongPressPanelDark
//  本批未登记（用户未点名），读不到即为 NO；若真机上玻璃效果不对，
//  优先试把单开返回值由 2 改为 1。
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
    if (!DKXSGetBool(@"DKXSEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DKXSGetBool(@"DKXSLongPressPanelBlur");
    BOOL forceDark = DKXSGetBool(@"DKXSLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DKXSUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
    // 上游原样在此缺口（单开无 return）；本移植明确返回 2，见文件头说明。
    return 2;
}
%end

%hook AWEModernLongPressPanelUIConfig
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DKXSGetBool(@"DKXSEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DKXSGetBool(@"DKXSLongPressPanelBlur");
    BOOL forceDark = DKXSGetBool(@"DKXSLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DKXSUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
    // 同上，单开明确返回 2。
    return 2;
}
%end

%ctor {
    %init;
}
