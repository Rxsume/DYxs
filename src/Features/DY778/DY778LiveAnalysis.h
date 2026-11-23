#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 2 移植：直播数据分析（观众/礼物/PK/人气，只读观测）。
// 规格：~/workspace/plugin-merge/DY778/spec-module2-liveanalysis.md
// hook 目标 24 个（§2），三路数据通道 WebSocket + HTTP 兜底 + 原生接口（§3），
// Protobuf 通用解析器（§3.4，字段号→键映射表未静态还原，见下）。
//
// 与模块 1 的关系（规格 §9）：LA 不改直播间行为，只读当前身份拉数据；
// 入口受 LiveTools 的 owner/遮罩状态影响——但 DYxs 没有
// _DY778LiveToolsOwnerIsCurrent / _DY778LiveOverlaysHidden 这两个 helper，
// 故入口只按 liveAnalysis.enabled + 当前房间上下文门控（见
// DY778LiveAnalysisEntryVisible），不另造一套隐身判定。
// LiveIdentity 已在模块 1，本模块不得重复安装进房拦截类 hook。

FOUNDATION_EXPORT void DY778InstallLiveAnalysisHooks(void);

// 生命周期（规格 §6）：刷新入口、停用、关房前/后。关房两个函数由本模块
// 自己的 fragment hook（componentUnmount / iesHYControllerDidDismiss:）驱动。
FOUNDATION_EXPORT void DY778LiveAnalysisRefresh(void);
FOUNDATION_EXPORT void DY778LiveAnalysisDeactivate(void);
FOUNDATION_EXPORT void DY778LiveAnalysisClosingRoom(void);
FOUNDATION_EXPORT void DY778LiveAnalysisDidCloseRoom(void);

// 总开关（默认关，见 DY778LiveAnalysisPolicy.h）。
FOUNDATION_EXPORT BOOL DY778LiveAnalysisEnabled(void);
// 入口是否可显示：总开关开且当前有房间上下文。
FOUNDATION_EXPORT BOOL DY778LiveAnalysisEntryVisible(void);
// 当前房间 ID：沿 room / roomModel / rawRoom 等链取（与模块 1 的
// roomModel 链同一批属性名，见 DY778LiveRoomIdentifier）。
FOUNDATION_EXPORT NSString *DY778LiveAnalysisRoomID(id object);

// 通用取值 helper（规格 §2.2、§4.1：_DY778LAIdentifier / _DY778LAText /
// _DY778LAArray / _DY778LAInteger 的 DYxs 复刻，两模块共用，不各写一套）。
FOUNDATION_EXPORT NSString *DY778LAIdentifierValue(id value);
FOUNDATION_EXPORT NSString *DY778LATextValue(id value);
FOUNDATION_EXPORT NSArray *DY778LAArrayValue(id value);
FOUNDATION_EXPORT long long DY778LAIntegerValue(id value);

// Protobuf 通用解析器（规格 §3.4）：只做 wire-format 解码，不写死字段号。
// 解码结果以字段号字符串为键（@"1"、@"2"…），值按 wire type 为 NSNumber
//（varint）或 NSData（长度定界/定长）。字段号→键名的完整映射表未静态
// 还原，须运行时抓包反推后补进 DY778LAProtoFieldNames，解析器本身不猜。
FOUNDATION_EXPORT NSDictionary<NSString *, id> *DY778LAProtoDecodeData(NSData *data);
// 已知的字段号→键名映射（当前为空，运行时抓包反推后补；不要凭猜测写死）。
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *DY778LAProtoFieldNames(void);
FOUNDATION_EXPORT NSData *DY778LAProtoInflateData(NSData *data);
FOUNDATION_EXPORT NSString *DY778LAProtoText(NSDictionary<NSString *, id> *decoded, NSUInteger field);
FOUNDATION_EXPORT long long DY778LAProtoInteger(NSDictionary<NSString *, id> *decoded, NSUInteger field);
FOUNDATION_EXPORT NSData *DY778LAProtoBytes(NSDictionary<NSString *, id> *decoded, NSUInteger field);
// 用户记录归一化：只处理带真实键名的字典（HTTP JSON 路径）；proto 路径
// 的字段号字典先原样保留，由调用方在映射表补齐后再归一化。
FOUNDATION_EXPORT NSDictionary *DY778LAProtoUser(NSDictionary *record);

// 登录态判定：Cookie 里有 sessionid / sessionid_ss 即认为已登录（规格 §5）。
FOUNDATION_EXPORT BOOL DY778LiveAnalysisHasLogin(void);
// 凭证：游客 TTWID 注册（POST ttwid.bytedance.com）与 Keychain 会话清理。
FOUNDATION_EXPORT void DY778LiveAnalysisRegisterVisitor(void (^completion)(NSString *ttwid));
FOUNDATION_EXPORT void DY778LiveAnalysisClearCredential(void);
// 网页登录抓 Cookie（规格 §5）：WKWebView 加载 live.douyin.com，走网页
// 登录后读 Cookie；游客注册失败时的 fallback。
FOUNDATION_EXPORT void DY778LiveAnalysisAcquireCredential(void (^completion)(BOOL success));

// ---------- 共享上下文（hook 与面板/入口共用，只读观测状态） ----------
@interface DY778LAContext : NSObject
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic) BOOL finishLoad;
@property(nonatomic) BOOL showRank;
@property(nonatomic, copy) NSArray<NSDictionary *> *audienceRows;
@property(nonatomic) CGPoint lastScrollOffset;
+ (instancetype)shared;
- (void)noteRoomID:(NSString *)roomID;
- (void)noteFinishLoad:(BOOL)finishLoad;
- (void)noteShowRank:(BOOL)showRank;
- (void)noteAudienceDictionary:(NSDictionary *)dictionary;
- (void)noteLynxView:(UIView *)view;
- (void)clear;
@end

// ---------- 数据模型（规格 §4、§7，按需精简的核心类） ----------
@interface DY778LAGiftLedger : NSObject
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, readonly) NSDate *startedAt;
@property(nonatomic, readonly) NSDate *updated;
@property(nonatomic) BOOL incomplete;
@property(nonatomic, readonly) NSArray<NSDictionary *> *cachedRows;
- (instancetype)initWithRoom:(NSString *)roomID;
- (void)markGap;
- (void)consumePayload:(NSDictionary *)payload;
- (NSArray<NSDictionary *> *)mergedGiftsForKeys:(NSArray<NSString *> *)keys;
- (NSArray<NSDictionary *> *)rowsForAnchor:(NSString *)anchorID;
- (NSArray<NSDictionary *> *)giftsForUser:(NSString *)userID;
@end

@interface DY778LABattle : NSObject
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSArray *teams;
@property(nonatomic) BOOL settled;
@property(nonatomic, copy) NSArray *seats;
@property(nonatomic, copy) NSDictionary *teamScores;
@property(nonatomic, copy) NSDictionary *profiles;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL retired;
- (void)consumePayload:(NSDictionary *)payload room:(NSString *)roomID;
- (void)consumeTeamfight:(NSDictionary *)fields clock:(NSTimeInterval)clock;
- (void)endBattle:(NSTimeInterval)clock;
- (NSInteger)contributionIndexForAnchor:(NSString *)anchorID;
- (void)retireBattle;
@end

@interface DY778LABoard : NSObject
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSArray<NSDictionary *> *rankRows;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger failures;
- (instancetype)initWithRoom:(NSString *)roomID seed:(NSDictionary *)seed;
- (void)applyRanks:(NSDictionary *)response;
- (void)applyHot:(NSDictionary *)response;
- (void)applyRoom:(NSDictionary *)room error:(NSError *)error sec:(NSString *)secUserID;
- (void)applyPK:(NSDictionary *)battle room:(NSString *)roomID;
- (void)refresh;
- (void)refreshHot;
- (void)expireHour;
@end

// ---------- 网络层（规格 §3） ----------
@interface DY778LAStream : NSObject
@property(nonatomic, readonly) BOOL socketOpen;
@property(nonatomic, readonly) BOOL receiving;
@property(nonatomic, readonly) BOOL connecting;
@property(nonatomic, readonly) BOOL polling;
@property(nonatomic, readonly) BOOL fallbackUsed;
@property(nonatomic, copy) NSString *cursor;
@property(nonatomic, copy) NSString *internalExt;
@property(nonatomic, copy) NSString *webID;
@property(nonatomic, copy) NSString *visitorID;
- (void)connectRoom:(NSString *)roomID;
- (void)close;
- (void)startHeartbeat;
- (void)send:(NSData *)data;
- (void)consumeData:(NSData *)data;
@end

@interface DY778LAClient : NSObject
@property(nonatomic, readonly) BOOL authenticated;
- (void)get:(NSString *)url params:(NSDictionary *)params completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)fetchAudience:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)fetchHot:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion;
@end

@interface DY778LAPush : NSObject
@property(nonatomic, strong, readonly) DY778LAStream *stream;
@property(nonatomic, strong, readonly) DY778LABattle *battle;
@property(nonatomic, strong, readonly) DY778LAGiftLedger *giftLedger;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *audienceScores;
- (instancetype)initWithRoom:(NSString *)roomID;
- (void)connectRoom:(NSString *)roomID;
- (void)connectAudienceRoom:(NSString *)roomID;
- (void)subscribeRoom:(NSString *)roomID;
- (void)close;
@end

// ---------- UI（规格 §6、§7，40 个方法以下的小类按需合并进面板实现） ----------
@interface DY778LAPanel : UIViewController
- (instancetype)initWithRoom:(NSString *)roomID;
- (void)refreshAll;
- (void)stop;
@end

@interface DY778LAPKPage : UIViewController
- (instancetype)initWithBattle:(DY778LABattle *)battle room:(NSString *)roomID;
@end

@interface DY778LAAudienceSheet : UIViewController
@property(nonatomic) BOOL authMissing;
@property(nonatomic) BOOL readFailed;
@property(nonatomic) BOOL contextMissing;
- (instancetype)initWithRoom:(NSString *)roomID;
- (void)loadScores:(id)sender;
- (void)refreshScores;
@end

@interface DY778LAEntry : NSObject
+ (instancetype)shared;
- (void)refresh;
- (void)hide;
@end
