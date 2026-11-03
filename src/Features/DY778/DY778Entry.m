//
//  DY778Entry.m
//  DYxs — DY778（jijiang2333/DY778，commit 4c26f4f）剩余模块的入口。
//  只安装 DYxs 里尚未移植的模块：福袋助手、缓存清理、Feed 过滤、播放倍速，
//  以及它们共用的 Core/Toast/Avatar 基础。
//  不安装的部分（已在 DYxs 里以 DKXS* 改名前缀移植，见
//  src/Features/MessageArchive/）：设置页、编辑历史、消息留存/撤回、
//  撤回通知、消息 UI。重复安装会造成两套留存库、两套撤回标记。
//  偏好键：DY778 模块读 DY778 专用 suite（com.dy778.douyin）的点分键，
//  DYxs 设置页的 DKXS* 键由 DY778RemainingSettings.xm 同步过去。
//

#import "DY778Core.h"
#import "DY778LuckyBag.h"
#import "DY778CacheCleaner.h"
#import "DY778FeedFilter.h"
#import "DY778Playback.h"

static void DY778InstallRemainingModules(void) {
    DY778InstallCoreHooks();
    DY778InstallLuckyBagHooks();
    DY778InstallPlaybackHooks();
    DY778InstallDefaultPlaybackHooks();
    DY778InstallFeedFilterHooks();
    DY778InstallCacheCleanerHooks();
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
                    // 缓存清理模块自己监听偏好变化并重载配置、按启动/回前台触发清理，这里不另行调用。
                }];
        });
    }
}
