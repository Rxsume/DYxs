#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 3 移植：超级福袋（SL）。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
// hook 目标 49 个中的 SL 部分：主安装体 4 个（S1–S4，§2.3，类固定
// IESLiveAudienceViewController）与福袋组 1 个（G1，§2.4）。
// SLGroup 先于 SL 主安装体安装（规格 §1.3）。
// SL 安装可在任意线程调用（内部 dispatch_async 到主队列重调，规格 §1.3）。
// SL 安装末尾注册的 4 个 NSNotificationCenter 观察者名字取自运行时
// 全局，静态不可恢复；DYxs 侧不注册猜测的通知名，pause/tick 改由
// hook 与组心跳定时器驱动（见 DY778SuperLucky.m 末尾说明）。
//
// 红线（规格 §11.1、§11.10）：只证明了原版「尝试领取」的代码路径，
// 没有任何证据证明这些调用在抖音 40.8.0 上仍能成功领取；观看任务
// 是否须真实停留未证实——DYxs 侧绝不伪造观看时长，只认任务上下文
// 上报的已完成状态（task_state / hasParticipated）。

FOUNDATION_EXPORT void DY778InstallSuperLuckyHooks(void);
FOUNDATION_EXPORT void DY778InstallSLGroupHooks(void);
// 摇一摇导出诊断段（=== DY778 super lucky diagnostics ===）。
FOUNDATION_EXPORT NSString *DY778SLDiagnosticsText(void);

// 总开关（默认关，见 DY778SuperLuckyPolicy.h）。
FOUNDATION_EXPORT BOOL DY778SuperLuckyEnabled(void);
// 组心跳（规格 §4.7）：读 superLucky.enabled/delay，受 4 门控约束
// （见 DY778RedEnvelope.h 的 DY778LuckyAutomationBlocked）。
FOUNDATION_EXPORT void DY778SLGroupTick(void);

// ---------- 任务上下文（规格 §4.2–§4.3） ----------
// 任务字段：task_infos_v2 / task_id / task_type / task_state /
// hasParticipated / remainingSeconds / activityID / roomID。
// 参与计划字段：watchRemainingSeconds / watchRequiredSeconds /
// watchTaskKey / watchAdmitted / watch-time-insufficient / expired。
// 观看时长不足时只记 watch-time-insufficient，不伪造完成。
@interface DY778SLTaskContext : NSObject
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, copy) NSString *taskType;
@property(nonatomic, copy) NSString *taskState;
@property(nonatomic) BOOL hasParticipated;
@property(nonatomic) NSTimeInterval remainingSeconds;
@property(nonatomic, copy) NSString *activityID;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSDictionary *raw;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (BOOL)complete;
@end
@interface DY778SLParticipationPlan : NSObject
@property(nonatomic) NSTimeInterval watchRemainingSeconds;
@property(nonatomic) NSTimeInterval watchRequiredSeconds;
@property(nonatomic, copy) NSString *watchTaskKey;
@property(nonatomic) BOOL watchAdmitted;
@property(nonatomic) BOOL hasParticipated;
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, copy) NSString *taskType;
@property(nonatomic, copy) NSString *taskState;
@property(nonatomic, copy) NSString *reason;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (BOOL)watchTimeInsufficient;
- (BOOL)expired;
@end

// ---------- 原生请求（规格 §4.4；1.1-2 逆向修正 2026-11-27） ----------
// 1.1-2 实证：经 IESLiveCommonNetworkRequester + IESLiveJSNetworkJsonRequest
// 发送（NSClassFromString 解析、逐键动态 setter set<Key>:、
// request:numToString:callback:），URL 为
// https://lianmengapi.snssdk.com/live/lottery/<command>/，command ∈
// detail / execute_task / participate，method GET、version v1；请求 dict
// {url, method, version, params, data}。DYxs 侧同款实现；类/方法缺失时
// 回退 NSURLSession POST（旧路径，服务端是否接受未证实）。
// 观看任务是否须真实停留未证实——DYxs 侧绝不伪造观看时长。
@interface DY778SLNativeCall : NSObject
@property(nonatomic, weak) id host;
@property(nonatomic, copy) NSString *room;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) void (^response)(NSDictionary *response, NSError *error);
@property(nonatomic, strong) NSArray *keeper;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL started;
- (void)command:(NSString *)command activity:(NSString *)activityID room:(NSString *)roomID params:(NSDictionary *)params completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)postActivity:(NSString *)activityID room:(NSString *)roomID task:(NSDictionary *)task completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)executeTask:(NSString *)taskID activity:(NSString *)activityID room:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)finish:(NSDictionary *)response error:(NSError *)error;
@end

// ---------- 状态机：DY778SLCoordinator（规格 §4.1，50 方法的精简复刻） ----------
@interface DY778SLCoordinator : NSObject
@property(nonatomic, weak) id host;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic) BOOL roomActive;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSTimer *actionTimer;
@property(nonatomic, weak) id button;
@property(nonatomic, weak) id panel;
@property(nonatomic, copy) NSString *roomTitle;
@property(nonatomic) unsigned long long visit;
+ (instancetype)shared;
- (void)activate:(id)host;
- (void)resign:(id)host;
- (void)leave;
- (BOOL)canRun;
- (BOOL)isViewing;
- (void)open;
- (void)pauseAutomatic;
- (void)scheduleAutomatic;
- (void)runAutomatic;
- (void)publishStatus;
- (void)tick;
- (void)discoverEntry;
- (void)clearState;
- (NSString *)displayState;
@end

// ---------- 自动任务执行器：DY778SLAuto（规格 §4.1，19 方法的精简复刻） ----------
@interface DY778SLAuto : NSObject
@property(nonatomic, weak) DY778SLCoordinator *coordinator;
- (instancetype)initWithCoordinator:(DY778SLCoordinator *)coordinator;
- (void)run;
- (BOOL)performBoundTask:(NSDictionary *)task;
- (void)stop;
@end

// ---------- 领取目标与记录 ----------
@interface DY778SLOTarget : NSObject
@property(nonatomic, copy) NSString *activityID;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic) BOOL hasParticipated;
- (instancetype)initWithActivity:(NSString *)activityID room:(NSString *)roomID task:(NSString *)taskID;
@end
@interface DY778SLRecords : NSObject
+ (NSArray<NSDictionary *> *)records;
+ (void)rememberRecord:(NSDictionary *)record status:(NSString *)status;
+ (BOOL)hasParticipatedActivity:(NSString *)activityID;
@end

// ---------- 开奖提醒记录（规格 §9.3：键归模块 3，行为归模块 4） ----------
// 模块 3 只做记录键的写入（recordStage），提醒的到点弹窗/通知实现
// 留给模块 4，不得在本模块重复实现。
FOUNDATION_EXPORT void DY778SLRecordStage(NSString *message);

// ---------- 面板 / 历史 / 入口 ----------
@interface DY778SLPanel : UIViewController
- (instancetype)initWithCoordinator:(DY778SLCoordinator *)coordinator;
- (void)refresh;
@end
@interface DY778SLHistoryController : UIViewController
@end
@interface DY778SLEntry : NSObject
+ (instancetype)shared;
- (void)refresh;
- (void)hide;
@end
