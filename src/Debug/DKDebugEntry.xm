//
//  DKDebugEntry.xm
//  DYxs
//
//  注册调试开关，并在前台窗口变化时同步全局调试浮层。
//

#import "DKDebugInspector.h"
#import "DKDCFeedProbe.h"
#import "DKDebugCapture.h"
#import "DKAudioProbe.h"
#import "DY778Core.h"
#import "DY778LuckyBag.h"
#import "DY778SuperLucky.h"
#import "DY778LiveLike.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/message.h>

static BOOL DKEntryIsDebugWindow(UIWindow *window) {
    return [NSStringFromClass(window.class) hasPrefix:@"DKDebug"];
}

// 轻量 toast：优先用抖音自带的 DUXToast，没有则在目标窗口上贴一个临时 label。
// 只给摇一摇导出这种无界面的手势用；有界面的流程仍走 UIAlertController/DKPrompt。
static void DKDebugShowToast(NSString *text) {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class toastClass = NSClassFromString(@"DUXToast");
        if (toastClass && [toastClass respondsToSelector:@selector(showText:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(toastClass, @selector(showText:), text);
            return;
        }
        UIWindow *window = DKDebugTargetWindow();
        if (!window) return;
        UILabel *label = [[UILabel alloc] init];
        label.text = text;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.8];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.font = [UIFont systemFontOfSize:14];
        label.layer.cornerRadius = 8;
        label.layer.masksToBounds = YES;
        [label sizeToFit];
        CGRect frame = label.frame;
        frame.size.width += 32;
        frame.size.height += 20;
        frame.origin.x = (window.bounds.size.width - frame.size.width) / 2;
        frame.origin.y = window.bounds.size.height - frame.size.height - 120;
        label.frame = frame;
        [window addSubview:label];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [label removeFromSuperview];
        });
    });
}

static AWESettingItemModel *DKMakeDebugSwitch(void) {
    AWESettingItemModel *item = DKMakeSwitch(DKKeyDebugInspectorEnabled, @"调试工具", @"开启后显示全局扳手入口");
    void (^origBlock)(void) = [item.switchChangedBlock copy];
    item.switchChangedBlock = ^{
        if (origBlock) origBlock();
        DKAudioProbePreferenceDidChange();
        DKDebugInspectorRefreshOverlay();
    };
    return item;
}

%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    if (!DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

- (void)makeKeyAndVisible {
    %orig;
    if (!DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    if (!hidden && !DKEntryIsDebugWindow(self)) DKDebugInspectorRefreshOverlay();
}

// 摇一摇导出当前视图树到剪贴板（调试用；huami DYYY 3.0.1，默认关闭）。
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    if (motion == UIEventSubtypeMotionShake && DKPrefBool(DKKeyShakeExportViewTree)) {
        UIWindow *window = DKDebugTargetWindow() ?: self;
        NSString *tree = DKDescribeViewTreeText(window);
        if (tree.length > 0) {
            // 末尾附 DY778 hook 安装报告，方便定位 41.2.0 上哪些 hook 没装上。
            NSMutableString *report = [NSMutableString stringWithString:tree];
            NSDictionary *hooks = DY778HookReport();
            [report appendString:@"\n=== DY778 hook report ===\n"];
            for (NSString *key in [hooks.allKeys sortedArrayUsingSelector:@selector(compare:)])
                [report appendFormat:@"%@ = %@\n", key, [hooks[key] boolValue] ? @"OK" : @"FAIL"];
            [report appendString:DY778LuckyDiagnosticsText()];
            [report appendString:DY778LikeDiagnosticsText()];
            [report appendString:DY778SLDiagnosticsText()];
            [report appendString:DKDCFeedProbeText()];
            [UIPasteboard generalPasteboard].string = report;
            DKDebugShowToast([NSString stringWithFormat:@"视图树已复制（%lu 字）", (unsigned long)report.length]);
        }
    }
}

%end

%ctor {
    DKAudioProbeInstallIfEnabled(YES);
    // 调试入口按设备临时开关，不进备份，恢复与恢复默认都不改它。
    DKSettingsRegister(DKKeyDebugInspectorEnabled, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeDebugSwitch());
    });
    DKSettingsRegister(DKKeyShakeExportViewTree, ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeSwitch(DKKeyShakeExportViewTree, @"摇一摇导出视图树", @"摇一摇把当前视图树（含行高探针）复制到剪贴板，仅调试用"));
    });
    DKDebugInspectorInstall();
}
