#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 4 移植：抽奖提醒（DrawReminders）。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md §4
//
// 归属（规格 §4.4，已定）：lucky.drawReminder / superLucky.drawReminder
// 等键归模块 3（设置面与记录调用），DY778DrawCenter / DY778DrawCard
// 与 DrawReminder* 全部 8 个 C 函数、提醒计时/弹窗/跳房的全部实现
// 归模块 4。模块 3 不得重复实现提醒弹窗；模块 4 不得改动模块 3 的
// 记录调用点。
//
// 记录模型（规格 §4.1）：键格式 account/kind/room/activity；
// 字段 account、kind、name、avatar、room、lucky、handle、prize、
// deadline、shown、ownerID、activity、confirmed、superLucky，
// 另有 group:（分组键）。deadline 经 longLongValue/doubleValue
// 归一化；shown 为 BOOL。持久化在 drawReminders.records
// （经 DY778Preferences）。
//
// 未证实点（规格 §4.2–§4.3、§10.3）：
//  - 秒数字符串格式（DrawReminderParseSeconds）：可能是 "90" 或
//    "90s"，DYxs 侧两者都接受。
//  - choice block 的装配细节在 tick 的 block 内，未完全还原。
//  - _DY778DrawReminderDue（lead=0 包装）0 个直接调用点，疑似死代码
//    或经函数指针调用——DYxs 侧实现它但不调用。
//  - lucky.drawReminderSeconds 等 4 个键的默认值未证实（模块 3 已
//    按 60 秒登记，见 DY778Core.m）。

// 记录键：'%@/%@/%@/%@'（account/kind/room/activity）。
FOUNDATION_EXPORT NSString *DY778DrawReminderKey(NSString *account, NSString *kind, NSString *room, NSString *activity);
// 由原始字典归一化为记录字典。
FOUNDATION_EXPORT NSDictionary *DY778DrawReminderRecord(NSDictionary *raw);
// 由上下文解析开奖方（规格 §4.1，字段见 .m 内注释）。
FOUNDATION_EXPORT NSDictionary *DY778DrawReminderOwner(id context);
// 秒数解析（"90" 或 "90s" 都接受）。
FOUNDATION_EXPORT NSTimeInterval DY778DrawReminderParseSeconds(id value);
// kind + ".drawReminderSeconds" 读数。
FOUNDATION_EXPORT NSTimeInterval DY778DrawReminderSeconds(NSString *kind);
// deadline 未过且 shown 为假（lead 为提前量）。
FOUNDATION_EXPORT BOOL DY778DrawReminderDueWithLead(NSDictionary *record, NSTimeInterval lead);
// lead=0 的包装（0 个直接调用点，疑似死代码；实现但不调用）。
FOUNDATION_EXPORT BOOL DY778DrawReminderDue(NSDictionary *record);
// 拼 sslocal://webcast_room 路由（room_id/user_id/
// enter_from_merge=live_merge/enter_method=live_cover）。
FOUNDATION_EXPORT NSString *DY778DrawReminderRoute(NSString *roomID, NSString *userID);
// 跳房：先校验 AWERouter transferToURLString: 签名，再路由。
FOUNDATION_EXPORT void DY778NavigateToLiveRoom(NSString *roomID, NSString *userID);
// 模块 3 的记录流程调的入口：把一条归一化记录记进 DrawCenter。
FOUNDATION_EXPORT void DY778DrawReminderRemember(NSDictionary *rawRecord);

// DY778DrawCenter（24 方法 + shared，规格 §4.2）。
@interface DY778DrawCenter : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *records;
@property(nonatomic) double monotonic;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) UIViewController *card;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic) BOOL dismissing;
+ (instancetype)shared;
- (void)armTimer;
- (void)save;
- (BOOL)enabled:(NSString *)kind;
- (NSTimeInterval)remaining:(NSDictionary *)record;
- (void)keyboard:(NSNotification *)notification;
- (void)changed:(NSNotification *)notification;
- (void)remember:(NSDictionary *)rawRecord;
- (BOOL)canPresent:(UIViewController *)presenter;
- (void)close:(NSDictionary *)record;
- (void)tick;
@end

// DY778DrawCard（12 方法，规格 §4.3）。
@interface DY778DrawCard : UIViewController
@property(nonatomic, copy) void (^choice)(BOOL jump);
@property(nonatomic, strong) NSDictionary *record;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *countdownLabel;
- (instancetype)initWithRecord:(NSDictionary *)record;
- (UILabel *)label:(NSString *)text style:(NSString *)style;
- (void)updateRemaining:(NSTimeInterval)remaining;
- (void)jump;
- (void)ignore;
- (void)countdown;
@end
