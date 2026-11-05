//
//  DY778Entry.m
//  DYxs — DY778（jijiang2333/DY778，1.0-3，b41e81b）保留模块：福袋助手、
//  直播自动点赞、推荐页直播信息（在线人数/卡片开播时长）、星牌查询、
//  主页与作品数字自定义。
//  2026-11-03 用户决定删除 DY778 其余部分：消息留存/编辑历史
//  （src/Features/MessageArchive/）、缓存清理、Feed 过滤、播放倍速均已删除，
//  只留上述模块及其共用的 Core/Toast/Avatar 基础（PlaybackPolicy.h 仅作
//  倍速标签格式化头文件保留，供 DY778Toast.m 使用）。
//  1.0-3 范围说明：Radar、Spark、Confirm 等其他新功能仍排除；LiveClock
//  （直播间开播时长悬浮）不单独装——DYxs 已有等价实现 DKXSLiveDuration.xm，
//  仅把 HTSLiveRoomAPI 取开播时间的网络兜底补进该文件；Fans/DisplayStats
//  用到的 Radar 单元格与表格基类由 DY778SharedUI 本地复刻，未并入 Radar。
//  偏好键：DY778 模块读 DY778 专用 suite（com.dy778.douyin）的点分键，
//  DYxs 设置页的 DKXS* 键由 DY778RemainingSettings.xm 同步过去。
//

#import "DY778Core.h"
#import "DY778LuckyBag.h"
#import "DY778LiveLike.h"
#import "DY778LiveInfo.h"
#import "DY778FansUI.h"
#import "DY778DisplayStats.h"

static void DY778InstallRemainingModules(void) {
    DY778InstallCoreHooks();
    DY778InstallLuckyBagHooks();
    DY778InstallLiveLikeHooks();
    DY778InstallLiveInfoHooks();
    DY778InstallFansHooks();
    DY778InstallDisplayStats();
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
