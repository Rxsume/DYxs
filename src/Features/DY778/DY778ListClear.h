#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DY778MiscPolicy.h"

// DY778 1.0-8 模块 4 移植：清理关注（FollowClear / ListClear）。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md §6
//
// 两个引擎并存（规格 §6，先说结论）：
//  - DY778FollowJob（关注专用）：操作对象是用户，读列表走抖音原生
//    AWEUserFollowingManager；设置页的关注清理入口走它。
//  - DY778ListClearJob（通用）：kind（NSUInteger）区分清理对象
//    （关注/点赞/推荐/收藏夹），读列表走 AWEFamiliarRecommendWork-
//    DataController / AWEFavoriteAwemeDataController /
//    AWEUserLikesDataManager + 收藏夹读器；种类选择器与长按手势走它。
// 两者共享原生拦截层（AWENetworkService get/post hook）与一批
// DY778List* helper，都发 DY778PreferencesChanged 观察。
//
// 红线（规格 §6.8，必读）：
//  - 取关是否走服务端接口、是否立即生效、是否可逆，一律未证实：
//    静态证据只证明原版“尝试取关”的代码路径，没有任何证据证明
//    在抖音 40.8.0 上仍能成功取关，也没有证据证明取关后能否一键
//    恢复。DYxs 侧 DY778ListClearCanSubmit 在未证实前恒为 NO，
//    即取关提交不执行，只做列表读取/选择/保护/排除与收据记录；
//    removeNext/removeNextBatch 走到提交点即停并弹提示，绝不凭
//    猜测调原生方法发请求。
//  - 批量取关的节流间隔/重试上限/退避策略未还原；ListClearJob kind
//    的枚举值未静态还原（DY778ListClearKind 的取值是 DYxs 侧内部
//    编号，不得写成原版数值）；Receipt verified 的核对方式未还原；
//    helper 0x8f150 的确切语义未完全还原；confirmKind 里 200 疑似
//    单次上限，未证实；第 4 个 UI hook（setTitle:forState:）归属
//    未解析，DYxs 侧不安装。
//  - 保护机制照抄：互关/特别关注/备注/手动排除表（规格 §6.6）。

// 原生拦截层：取关请求怎么走（规格 §6.4）——hook 本身不发取关请求，
// 只观察并核对经由 AWENetworkService 发出的请求/回包。
FOUNDATION_EXPORT void DY778InstallListNativeHooks(void);
FOUNDATION_EXPORT void DY778InstallListClearHooks(void);
// 取关提交是否可执行：未证实前恒为 NO（见头注红线）。
FOUNDATION_EXPORT BOOL DY778ListClearCanSubmit(void);

// _DY778List* helper（规格 §6.1）。
FOUNDATION_EXPORT BOOL DY778ListMethod(id object, SEL selector, const char *result, NSArray<NSString *> *arguments);
FOUNDATION_EXPORT NSString *DY778ListID(id value);
FOUNDATION_EXPORT NSString *DY778ListCurrentUser(void);
FOUNDATION_EXPORT id DY778ListAcquire(void);
FOUNDATION_EXPORT BOOL DY778ListMore(id object);
FOUNDATION_EXPORT void DY778ListRelease(id object);
FOUNDATION_EXPORT BOOL DY778ListVerificationVisible(void);
FOUNDATION_EXPORT void DY778ListStartCollectionClear(id owner, id folder, id context);
FOUNDATION_EXPORT void DY778ListShowClearTask(id owner);
FOUNDATION_EXPORT void DY778ListStopCollectionClear(void);
FOUNDATION_EXPORT UIViewController *DY778ListClearSettingsController(void);
FOUNDATION_EXPORT UIViewController *DY778ListFoldersController(void);
FOUNDATION_EXPORT UIViewController *DY778FollowClearController(void);
FOUNDATION_EXPORT BOOL DY778FollowClearActive(void);
FOUNDATION_EXPORT void DY778FollowClearStop(void);
FOUNDATION_EXPORT void DY778ResetListClear(void);

// DY778ListNativeRequest（22 方法 + 1 类方法，规格 §6.4 尾部 A）。
@interface DY778ListNativeRequest : NSObject
@property(nonatomic) BOOL cancel;
@property(nonatomic) BOOL submitted;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, weak) id target;
@property(nonatomic, strong) id completion;
@property(nonatomic, strong) id task;
@property(nonatomic, strong) Class responseClass;
@property(nonatomic) BOOL captured;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL received;
+ (instancetype)account:(NSString *)account target:(id)target model:(Class)model
                 invoke:(id)invoke completion:(id)completion;
- (void)invoke;
- (void)cancelRequest;
@end

// DY778ListClearReceipt（21 方法，纯属性，规格 §6.3）。
// 四阶段 intercepted → submitted → received → verified。
@interface DY778ListClearReceipt : NSObject
@property(nonatomic) DY778ListClearKind kind;
@property(nonatomic, strong) NSSet<NSString *> *expectedIDs;
@property(nonatomic, strong) NSMutableSet<NSString *> *failedIDs;
@property(nonatomic, strong) id current;
@property(nonatomic, weak) id task;
@property(nonatomic) BOOL intercepted;
@property(nonatomic) BOOL submitted;
@property(nonatomic) BOOL received;
@property(nonatomic) BOOL verified;
@property(nonatomic, copy) NSString *failureReason;
@end

// DY778FollowJob（75 方法 + shared，规格 §6.2）。
@interface DY778FollowJob : NSObject
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *toastToken;
@property(nonatomic, strong) NSMutableArray *users;
@property(nonatomic, strong) NSMutableSet *seen;
@property(nonatomic, strong) NSMutableDictionary *cursors;
@property(nonatomic, strong) NSMutableArray *selected;
@property(nonatomic, strong) NSMutableSet *excluded;
@property(nonatomic, strong) NSMutableSet *uncertain;
@property(nonatomic, strong) NSMutableArray *queue;
@property(nonatomic, strong) id manager;
@property(nonatomic, strong) id request;
@property(nonatomic, copy) NSString *checkpoint;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL changed;
@property(nonatomic) BOOL reading;
@property(nonatomic) BOOL removing;
@property(nonatomic) BOOL waiting;
@property(nonatomic) BOOL failed;
@property(nonatomic) BOOL more;
@property(nonatomic) BOOL excludeMutual;
@property(nonatomic) BOOL excludeSpecial;
@property(nonatomic) BOOL excludeRemark;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger pages;
@property(nonatomic) BOOL completed;
@property(nonatomic) double nextAt;
@property(nonatomic) double waitingAt;
@property(nonatomic) double removeStartedAt;
+ (instancetype)shared;
- (void)resume;
- (void)readPage;
- (void)tick;
- (BOOL)protectedUser:(id)user;
- (void)startRemoval;
- (void)removeNext;
- (void)stop;
- (void)reset;
- (void)releaseTransient;
- (void)background;
- (void)render;
- (NSString *)exclusionKey;
- (NSString *)uncertainKey;
- (void)saveExcluded;
- (void)saveUncertain;
- (void)settingsChanged;
@end

// DY778ListClearJob（102 方法 + shared，规格 §6.3）。
@interface DY778ListClearJob : NSObject
@property(nonatomic) DY778ListClearKind kind;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, weak) id owner;
@property(nonatomic, strong) NSMutableArray *snapshot;
@property(nonatomic, strong) id dataController;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *toastToken;
@property(nonatomic, strong) DY778ListClearReceipt *receipt;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL reading;
@property(nonatomic) BOOL removing;
@property(nonatomic) BOOL slowed;
@property(nonatomic, copy) NSString *pauseReason;
@property(nonatomic) BOOL verificationVisible;
@property(nonatomic) double nextStepAt;
@property(nonatomic) double timeoutAt;
@property(nonatomic) double requestStartedAt;
@property(nonatomic) NSUInteger readLimit;
@property(nonatomic, strong) NSMutableSet *classifiedIDs;
@property(nonatomic, strong) NSMutableSet *disabledItemIds;
@property(nonatomic) BOOL hasUnavailableItems;
@property(nonatomic, copy) NSString *readCheckpoint;
@property(nonatomic, strong) NSArray *folders;
@property(nonatomic) NSUInteger folderIndex;
@property(nonatomic) BOOL reverseOrder;
@property(nonatomic) BOOL collectionSelection;
@property(nonatomic) BOOL collectionScope;
@property(nonatomic) BOOL classificationReady;
+ (instancetype)shared;
- (void)startKind:(DY778ListClearKind)kind user:(id)user owner:(id)owner mergedContainer:(id)container;
- (void)chooseKind:(id)user owner:(id)owner merged:(id)merged settings:(id)settings folder:(id)folder;
- (void)confirmKind:(DY778ListClearKind)kind user:(id)user owner:(id)owner merged:(id)merged limit:(NSUInteger)limit;
- (void)showTaskFrom:(id)owner;
- (void)resumeReading;
- (void)readPage:(id)cursor;
- (void)readClassificationItems:(NSArray *)items disabled:(NSSet *)disabled more:(BOOL)more cursor:(id)cursor;
- (void)prepareFolderReader;
- (void)completeReadScope;
- (void)beginRemoval;
- (void)removeNextBatch;
- (void)tick;
- (void)finish:(BOOL)success uncertain:(NSSet *)uncertain;
- (void)stop:(NSString *)reason;
- (id)cursor;
- (void)updateProgress;
- (void)settingsChanged;
@end

// DY778FollowViewController（30 方法，规格 §6.5）。
@interface DY778FollowViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, strong) DY778FollowJob *job;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, copy) NSString *scope;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UILabel *count;
@property(nonatomic, strong) UIButton *clearButton;
@property(nonatomic) BOOL visible;
- (void)render;
- (void)options;
- (void)confirmClear;
@end

// DY778ListClearSettingsViewController（12 方法，规格 §6.5）。
@interface DY778ListClearSettingsViewController : UITableViewController
- (void)close;
- (void)refresh;
- (void)toggle:(UISwitch *)sender;
@end

// DY778ListFolderViewController（82 方法，规格 §6.5）。
@interface DY778ListFolderViewController : UITableViewController
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *resultMessage;
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, strong) id reader;
@property(nonatomic, strong) id request;
@property(nonatomic, strong) NSMutableArray *folders;
@property(nonatomic, strong) NSMutableSet *seen;
@property(nonatomic, strong) NSMutableDictionary *cursors;
@property(nonatomic, strong) NSMutableSet *selectedIDs;
@property(nonatomic, copy) NSString *checkpoint;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UILabel *count;
@property(nonatomic, strong) UIButton *clearButton;
@property(nonatomic, strong) UIButton *taskButton;
@property(nonatomic, strong) UIProgressView *progress;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL waiting;
@property(nonatomic) BOOL more;
@property(nonatomic) BOOL failed;
@property(nonatomic) BOOL first;
@property(nonatomic) BOOL allWorks;
@property(nonatomic) BOOL unclassified;
@property(nonatomic) BOOL allFolders;
@property(nonatomic) BOOL wasRunning;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger pages;
@property(nonatomic) double nextAt;
@property(nonatomic) double waitingAt;
- (void)reloadFolders;
- (void)render;
- (void)tick;
- (void)resume;
- (void)loadPage;
- (void)selectAll;
- (void)taskTapped;
- (void)clearTapped;
@end

// DY778ListFolderPrivacyBadge（4 方法，规格 §6.5）。
@interface DY778ListFolderPrivacyBadge : UILabel
@end
