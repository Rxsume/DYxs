//
//  DY778Entry.m
//  DYxs — DY778（jijiang2333/DY778，1.0-3，b41e81b）保留模块：福袋助手、
//  直播自动点赞、推荐页直播信息（在线人数/卡片开播时长）、星牌查询、
//  主页与作品数字自定义。
//  1.0-8 模块 1（2026-11-23，按 1.0-8 deb 拆包规格重写）：直播间工具
//  （隐身进直播间、定时弹幕、礼物风控）与游客身份（请求层去 token + 注入
//  游客 TTWID），见 DY778LiveTools.m / DY778LiveGuest.m。
//  1.0-8 模块 2（2026-11-23，按 1.0-8 deb 拆包规格重写）：直播数据分析
//  （观众/礼物/PK/人气，只读观测），见 DY778LiveAnalysis.m。作者已转 TG 频道，
//  GitHub 不再更新源码，后续模块按同一方式拆包重写。
//  1.0-8 模块 3（2026-11-23，按 1.0-8 deb 拆包规格重写）：红包自动抢
//  （RE，见 DY778RedEnvelope.m）与超级福袋（SL，见 DY778SuperLucky.m）。
//  只证明了原版「尝试领取」的代码路径，没有任何证据证明在抖音 40.8.0
//  上仍能成功领取；静默领取的原生调用未静态还原，DYxs 侧 quiet 模式
//  只做观测与记录、不拦截官方领取视图（见 DY778RedEnvelope.m 头注）。
//  1.0-8 模块 4（2026-11-23，按 1.0-8 deb 拆包规格重写）：备份恢复 +
//  抽奖提醒 + 评论展开 + 清理关注 + 直播外观编辑（见 DY778Misc.m、
//  DY778Backup.m、DY778DrawReminder.m、DY778CommentExpand.m、
//  DY778ListClear.m、DY778LiveAppearance.m）。
//  清理关注是破坏性操作：取关是否走服务端接口、是否立即生效、是否
//  可逆，一律未证实，DYxs 侧取关提交不执行（见 DY778ListClear.h）；
//  评论展开的“展开” UI 动作未静态还原，DYxs 侧只做 hook 与扫描记录。
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
#import "DY778LiveTools.h"
#import "DY778LiveGuest.h"
#import "DY778LiveAnalysis.h"
#import "DY778RedEnvelope.h"
#import "DY778SuperLucky.h"
#import "DY778Misc.h"
#import "DY778FansUI.h"
#import "DY778DisplayStats.h"

static void DY778InstallRemainingModules(void) {
    DY778InstallCoreHooks();
    DY778InstallLuckyBagHooks();
    DY778InstallLiveLikeHooks();
    DY778InstallLiveInfoHooks();
    DY778InstallLiveToolsHooks();
    DY778InstallLiveGuestHooks();
    DY778InstallLiveAnalysisHooks();
    // 1.0-8 模块 3：先装 RE（内含先静默后主安装的双重 hook 链），
    // 后装 SL——两模块在 IESLiveAudienceViewController 上共享 4 个
    // hook 目标（viewDidAppear:/roomDidBecomeActive:/
    // roomWillResignActive:/onStartLeaveRoomAnimation），SL 的替换实现
    // 外层包 RE 的替换实现，orig 链完整。
    DY778InstallRedEnvelopeHooks();
    DY778InstallSuperLuckyHooks();
    // 1.0-8 模块 4：备份恢复 + 抽奖提醒 + 评论展开 + 清理关注 +
    // 直播外观编辑（见 DY778Misc.m）。备份与外观无安装函数，
    // 走设置页调用；抽奖提醒只 dispatch_async 调 DrawCenter tick。
    DY778InstallMiscHooks();
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
