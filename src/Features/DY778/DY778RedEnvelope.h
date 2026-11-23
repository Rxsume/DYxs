#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class WKWebView;
@class DY778RETarget;

// DY778 1.0-8 模块 3 移植：红包自动抢（RE）。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
// hook 目标 49 个中的 RE 部分：主安装体 35 个（D1–D4 + W1–W31，§2.1）
// 与静默安装体 9 个（Q1–Q9，§2.2）；另有 1 个静默直接 hook（0x244354）
// 类/方法动态算出未解析，DYxs 侧不安装（见 DY778RedEnvelope.m 末尾说明）。
// W19–W24 的 newIMP/orig slot 已用 capstone 重跑安装函数核对（类名/
// 方法名/参数类型串与规格表一致；原版 newIMP/orig 地址本身与 DYxs
// 代码无关，DYxs 用自己的替换实现与静态 IMP 存储）。
//
// 安装顺序（规格 §2.2、§10）：先静默抢（quiet），后主安装体——Q9 与 W5
// 是同一个方法 IESLiveLuckyBoxServiceManager openGrabLuckyBoxView 的
// 双重 hook，后者的 orig 链上是前者；顺序反了链就断。
// RE 安装必须在主线程调用（quiet 安装无 dispatch 重试，规格 §1.2）。
//
// 红线（规格 §11.1–§11.2）：只证明了原版「尝试领取」的代码路径，
// 没有任何证据证明这些调用在抖音 40.8.0 上仍能成功领取；服务端可能
// 已改接口、加签、限流或风控。本文件把领取写成「尝试」，失败/限流/
// 风控路径一律有保护（节流、重试上限、退避，数值见
// DY778RedEnvelopePolicy.h，均为 DYxs 侧保守设定，未证实）。

FOUNDATION_EXPORT void DY778InstallRedEnvelopeHooks(void);

// 总开关与自动领取开关（默认关，见 DY778RedEnvelopePolicy.h）。
FOUNDATION_EXPORT BOOL DY778RedEnvelopeEnabled(void);
FOUNDATION_EXPORT BOOL DY778RedEnvelopeAutoClaim(void);
// 领取模式：quiet / manual / web（规格 §8.1 取值未证实）。
FOUNDATION_EXPORT NSString *DY778RedEnvelopeMode(void);

// ---------- 4 门控（规格 §4.7、§9.1，与 SL 共用） ----------
// 原版 4 个 helper 的内部逻辑未全拆；DYxs 侧按函数名与模块 1 的现有
// 状态推断实现，未证实。任一成立时自动任务不执行。
//   OwnerIsCurrent：当前房间的主播是当前账号（按 host 取 roomModel →
//     owner 链比对账号 ID；取不到主播信息时返回 NO，即不阻断）。
//     另一种可能读法是「LiveTools 会话归属账号仍为当前账号」，未证实。
//   StealthActive：liveTools.stealth 开（模块 1 的隐身开关）。
//   LiveIdentityBlocksAutomation：游客身份生效；DYxs 里游客身份即由
//     stealth 开关驱动（见 DY778LiveGuest.m），故与 StealthActive 重合，
//     为保原版 4 门控结构仍单独保留。
//   LiveAssistantPresentationBlocksAutomation：模块 3 的面板/入口正
//     展示（避免自动任务与用户操作打架）。
FOUNDATION_EXPORT BOOL DY778LuckyLiveToolsOwnerIsCurrent(id host);
FOUNDATION_EXPORT BOOL DY778LuckyLiveToolsStealthActive(void);
FOUNDATION_EXPORT BOOL DY778LuckyLiveIdentityBlocksAutomation(void);
FOUNDATION_EXPORT BOOL DY778LuckyLiveAssistantPresentationBlocksAutomation(void);
FOUNDATION_EXPORT BOOL DY778LuckyAutomationBlocked(id host);

// ---------- 共享取值 helper（规格 §6.3：RE/SL 数据流入的共同入口） ----------
// _DY778LiveContextRoomID（模块 1/2 的 DY778LiveRoomIdentifier 走同一批
// 属性名；对象本身或 roomModel/room/rawRoom/liveRoom/currentRoom 链上取）。
// _DY778CurrentAccountID 在 DY778Core.h 已有，不重复定义。
FOUNDATION_EXPORT NSString *DY778LiveContextRoomID(id object);

// ---------- 模型取值与条件分类（规格 §3.3、§3.7） ----------
typedef NS_ENUM(NSInteger, DY778REConditionCategory) {
    DY778REConditionUnknown = 0,
    DY778REConditionFree,     // 免费/无条件（文本分类，不等于能领到）
    DY778REConditionPresent,  // 需在场（开奖时需在直播间）
    DY778REConditionGated,    // 有门槛（灯牌/粉丝/钻/关注/口令/付费/送礼等）
};
FOUNDATION_EXPORT DY778REConditionCategory DY778REConditionCategoryForText(NSString *text);
FOUNDATION_EXPORT id DY778REModelValue(id model, NSString *key);
FOUNDATION_EXPORT BOOL DY778REModelFlag(id model, NSString *key);
FOUNDATION_EXPORT NSString *DY778REModelID(id model);
// 结果字典读取（规格 §3.3）：succeed / diamondCount / giftName / cashCount。
FOUNDATION_EXPORT NSDictionary *DY778REReadResult(NSDictionary *result);

// ---------- 领取记录（规格 §3.9） ----------
FOUNDATION_EXPORT NSArray<NSDictionary *> *DY778RERecords(void);
FOUNDATION_EXPORT void DY778RERememberRecord(NSDictionary *record, NSString *status);
FOUNDATION_EXPORT BOOL DY778REHasClaimedRecord(NSString *boxID);

// ---------- 状态机：DY778RECoordinator（规格 §3.2，212 方法的精简复刻） ----------
// 只实现驱动领取所需的核心方法；entryForBox:/selectedEntry 的不透明
// 结构体（规格 §3.2）语义未解码，DYxs 侧按字段用途重新设计为
// DY778RETarget，不照搬内存布局。
@interface DY778RECoordinator : NSObject
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, weak) id fragment;
@property(nonatomic, weak) id store;
@property(nonatomic, weak) id manager;
@property(nonatomic, copy) NSString *listToken;
@property(nonatomic, copy) NSArray<NSString *> *discoveredIDs;
@property(nonatomic) NSUInteger listFailures;
@property(nonatomic) BOOL listLoaded;
@property(nonatomic) NSTimeInterval nextListFetch;
@property(nonatomic) BOOL dispatchingClaim;
@property(nonatomic) BOOL officialVisible;
+ (instancetype)shared;
- (void)registerStore:(id)store;
- (void)registerManager:(id)manager reset:(BOOL)reset;
- (void)registerFragment:(id)fragment;
- (void)unregisterFragment:(id)fragment;
- (void)receiveList:(NSArray *)list store:(id)store room:(NSString *)roomID account:(NSString *)accountID session:(NSString *)session;
- (void)receiveBackend:(id)backend manager:(id)manager room:(NSString *)roomID account:(NSString *)accountID session:(NSString *)session now:(NSTimeInterval)now;
- (BOOL)canDiscover;
- (void)refreshDiscovery;
- (void)clearDiscovery;
// 门控：0 = 阻断，1 = 放行（原版返回 int，语义未全拆；DYxs 侧按 SL 的
// 4 门控同款实现，RE 侧是否调同样 helper 未证实，见规格 §9.1）。
- (int)baseGate;
- (int)actionGate;
- (void)drive;
- (void)tick;
- (void)enterRoom:(NSString *)roomID;
- (void)leaveRoom;
- (void)suspend;
- (void)manualOpen:(id)box;
- (void)closeOwnedPanel;
- (NSArray<DY778RETarget *> *)allTargets;
- (NSString *)progressText;
- (void)notifyProgress;
@end

// ---------- 租约：DY778RELease（规格 §9.3，51 方法的精简复刻） ----------
@interface DY778RELease : NSObject
@property(nonatomic, copy) NSString *boxID;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic) NSTimeInterval expiresAt;
@property(nonatomic) BOOL claimed;
@property(nonatomic) BOOL retired;
- (instancetype)initWithBox:(NSString *)boxID room:(NSString *)roomID;
- (BOOL)valid;
- (void)retire;
@end

// ---------- 领取目标（替代原版不透明 entry 结构体） ----------
@interface DY778RETarget : NSObject
@property(nonatomic, copy) NSString *boxID;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *conditionText;
@property(nonatomic) DY778REConditionCategory condition;
@property(nonatomic) BOOL attempted;
@property(nonatomic) NSTimeInterval observedAt;
- (instancetype)initWithBox:(NSString *)boxID room:(NSString *)roomID conditionText:(NSString *)text;
@end

// ---------- 静默抢：DY778REQuietSession / DY778REQuietTicket（规格 §3.4） ----------
// 原版原理：拦截 BDXPopupViewController（元类 open/create/showContainer）
// 与路由跳转，在官方红包容器弹出时由 quiet session 接管流程，不在
// 屏幕上展示官方面板，再由 session 内部走领取路径。
// DYxs 侧的偏离（必须明说）：静默领取的原生调用未静态还原，DYxs 不知道
// 调哪个内部方法能领到；若拦截官方视图又领不到，会使用户丢红包。
// 故 DYxs 的 quiet session 只做观测与发现记录，不拦截官方容器弹出
// （Q1–Q9 的替换实现一律调原 IMP），真正的领取走 manual（点按钮）
// 或 web（WKWebView JS）路径。安装顺序仍保持先静默后主安装，
// 以保 Q9/W5 的双重 hook 链完整。
@interface DY778REQuietTicket : NSObject
@property(nonatomic, weak) id session;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic) BOOL retired;
@property(nonatomic) BOOL manual;
@end
@interface DY778REQuietSession : NSObject
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic) BOOL valid;
@property(nonatomic) BOOL stopped;
@property(nonatomic, readonly) BOOL manual;
+ (instancetype)beginWithHost:(id)host room:(NSString *)roomID valid:(BOOL)valid;
- (BOOL)openModernWithManager:(id)manager models:(NSArray *)models remaining:(double)remaining;
- (BOOL)ownsView:(UIView *)view;
- (void)attach:(id)router schema:(NSString *)schema context:(id)context completion:(void (^)(BOOL handled))completion;
- (void)perform:(id)models;
- (void)cancel;
@end

// ---------- 网页读取/领取（规格 §3.6） ----------
// JS 脚本原文未静态还原；DYxs 侧按结果字段名重新设计注入脚本（按按钮
// 文本找领取按钮并点击，读 succeed/diamondCount/giftName/cashCount），
// 不得声称与原版脚本一致。
@interface DY778REWebPage : NSObject
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSString *boxID;
@property(nonatomic) BOOL claimAttempted;
@property(nonatomic) NSTimeInterval observedAt;
- (instancetype)initWithWebView:(WKWebView *)webView box:(NSString *)boxID;
- (void)readPageWithCompletion:(void (^)(NSDictionary *state))completion;
- (void)claimWithCompletion:(void (^)(BOOL submitted, NSDictionary *result))completion;
- (void)cancel;
@end

// ---------- 页面扫描（规格 §3.7 _DY778REReadPageState 族） ----------
@interface DY778REScan : NSObject
- (NSDictionary *)readPageState:(UIView *)view;
- (NSString *)pageCountdown:(UIView *)view;
- (NSString *)pageStatusText:(UIView *)view;
- (NSString *)pageConditionText:(UIView *)view;
- (NSArray<NSString *> *)boxIDsInView:(UIView *)view;
@end

// ---------- 手动抢与参与确认（规格 §3.5、§3.7） ----------
// 手动抢是界面自动化（点按钮），不是服务端调用；按钮文本在抖音 40.8.0
// 是否一致须真机核对。参与确认做 box ID 多键名匹配。
FOUNDATION_EXPORT BOOL DY778REManualClaimBox(UIView *view);
FOUNDATION_EXPORT BOOL DY778REConfirmParticipation(NSDictionary *payload, NSString *boxID);

// ---------- 面板 / 历史 / 入口 ----------
@interface DY778REPanel : UIViewController
- (instancetype)initWithCoordinator:(DY778RECoordinator *)coordinator;
- (void)refresh;
@end
@interface DY778REHistoryController : UIViewController
@end
@interface DY778REEntry : NSObject
+ (instancetype)shared;
- (void)refresh;
- (void)hide;
@end
