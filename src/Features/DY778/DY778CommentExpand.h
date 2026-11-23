#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 4 移植：评论展开（CommentExpand）。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md §5
//
// Hook 清单（24 个，规格 §2.1 逐对核对）：高度/构建 4 个、控制器
// 生命周期与滚动 9 个、Cell/Label 布局 6 个、Section/模型绑定 5 个。
// 记录键前缀 comment.expand.（键形如 comment.expand.<selName>）。
// 安装时不读设置开关；总开关 comments.enabled 在扫描/派发里查。
//
// 红线（规格 §5.4）：
//  - “展开”的具体 UI 动作未静态还原（改 label 行数？改
//    calculateHeight 返回值？调高度后刷新？均未拆出）。DYxs 侧只做
//    hook 与扫描记录，展开动作留空（DY778CommentExpansionApply
//    为显式空实现，见 .m），不得按猜测实现。
//  - calculateHeight 的返回值是否被替换 block 篡改，未证实——
//    DYxs 侧原样返回，不篡改。
//  - 扫描节奏与 resumeAfter 的具体秒数未证实；总开关 comments.enabled
//    默认值未证实（DYxs 侧默认关）。
//  - 安装函数内 17 处包装器调用点与 24 个目标的完全对齐未证实；
//    类型串里另有 1 个裸 B（返回 BOOL 的方法）未定位到具体目标，
//    DYxs 侧不安装。

FOUNDATION_EXPORT void DY778InstallCommentExpandHooks(void);

// 会话模型（规格 §5.2）。
@interface DY778CommentExpansionSession : NSObject
@property(nonatomic, strong) NSMutableArray *records;
@property(nonatomic) NSUInteger dispatchDepth;
@property(nonatomic, weak) id owner;
@property(nonatomic, weak) id list;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL scanning;
@property(nonatomic) BOOL scanPending;
@property(nonatomic) BOOL suspended;
@property(nonatomic) BOOL closed;
@property(nonatomic) double resumeAfter;
@end

@interface DY778CommentExpansionBinding : NSObject
@property(nonatomic, copy) NSString *identity;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger pendingTicket;
@property(nonatomic, weak) DY778CommentExpansionSession *session;
@property(nonatomic, strong) id record;
@property(nonatomic, weak) id model;
@property(nonatomic, weak) id section;
@end

@interface DY778CommentExpansionTouch : NSObject
@property(nonatomic, weak) DY778CommentExpansionSession *session;
@property(nonatomic, strong) id record;
@property(nonatomic, weak) id cell;
@property(nonatomic, weak) DY778CommentExpansionBinding *binding;
@property(nonatomic) NSUInteger generation;
- (void)userAction:(id)sender;
@end

// 占位类（规格 §5.2：DY778CommentExpansion，0 方法，仅占位）。
@interface DY778CommentExpansion : NSObject
@end

// “展开”的 UI 动作：未静态还原，显式空实现（只记观测，不改 UI）。
// 须在抖音 40.8.0 上运行时验证长评论的展开入口与点后行为后再实现。
FOUNDATION_EXPORT void DY778CommentExpansionApply(DY778CommentExpansionSession *session, id cell);
