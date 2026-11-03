//
//  DY778Entry.m
//  DYxs — DY778（jijiang2333/DY778，commit 4c26f4f）仅保留福袋助手。
//  2026-11-03 用户决定删除 DY778 其余部分：消息留存/编辑历史
//  （src/Features/MessageArchive/）、缓存清理、Feed 过滤、播放倍速均已删除，
//  只留福袋助手及其共用的 Core/Toast/Avatar 基础（PlaybackPolicy.h 仅作
//  倍速标签格式化头文件保留，供 DY778Toast.m 使用）。
//  偏好键：DY778 模块读 DY778 专用 suite（com.dy778.douyin）的点分键，
//  DYxs 设置页的 DKXS* 键由 DY778RemainingSettings.xm 同步过去。
//

#import "DY778Core.h"
#import "DY778LuckyBag.h"

static void DY778InstallRemainingModules(void) {
    DY778InstallCoreHooks();
    DY778InstallLuckyBagHooks();
}

__attribute__((constructor)) static void DY778Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) return;
        DY778RegisterDefaults();
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778InstallRemainingModules();
            for (NSNumber *delay in @[@1, @3, @10]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ DY778InstallRemainingModules(); });
            }
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) { DY778InstallRemainingModules(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                    NSString *key = notification.userInfo[@"key"];
                    if (!key.length || [key hasPrefix:@"lucky."] || [key isEqualToString:@"appearance"] || [key isEqualToString:@"accent"]) DY778LuckyPreferencesChanged();
                }];
        });
    }
}
