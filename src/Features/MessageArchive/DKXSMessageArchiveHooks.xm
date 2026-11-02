//
//  DKXSMessageArchiveHooks.xm
//  DY778 第 1 批 staging：消息留存 / 编辑历史 / 时间标签的全部 Logos 钩子。
//  上游 DY778 用手写 swizzle（DY778Hook，启动后多次重装），本批全部改写为 Logos %hook：
//  · 同一方法只留一个钩子，走 %orig 链；DY778 的重装逻辑（回前台再包一层）直接丢弃；
//  · 本批钩子与 DYxs 现有钩子无同名冲突（见 REPORT），不需要并入已有文件；
//  · 抖音类只给最小 @interface 声明，不 import DouyinHeaders、不 import 上游 AwemeHeaders；
//  · 传 UIViewController* 时显式转型（Logos 只给前置声明，见第 1 批 build #45 教训）；
//  · 用 objc_msgSend 的地方本文件没有（动态调用集中在 DKXSArchiveNative.m，已 import <objc/message.h>）。
//

#import "DKXSRecall.h"
#import "DKXSEditHistory.h"
#import "DKXSEditContent.h"
#import "DKXSMessageUI.h"
#import "DKXSArchiveCore.h"
#import "DKXSRecallNotifications.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface TIMXOMessage : NSObject
- (id)content;
- (void)setContent:(id)content;
- (BOOL)recalled;
- (void)setRecalled:(BOOL)recalled;
- (void)setRecalledContent:(id)content;
- (void)setEditInfo:(id)info;
- (void)applyAttributesFromModel:(id)model;
- (void)applyAttributesFromModelV2:(id)model;
@end

@interface AWEIMMessageViewModel : NSObject
- (void)setupWithMessage:(id)message;
- (void)setConversation:(id)conversation;
@end

@interface AWEIMMessageListViewController : UIViewController
@end

@interface AWEIMMessageBaseHeaderView : UIView
- (void)configWithText:(id)text chatHasBackground:(BOOL)hasBackground;
@end

@interface IESIMChatSettingsListViewModelProviderComponent : NSObject
- (id)createSectionViewModels;
@end

// ---- 聊天信息页入口（上游 DY778ChatSectionsHook 的 Logos 版） ----
// 40.8.0 风险点（见 REPORT）：IESIMChatSettingsItem*ViewModel 的构造与点击属性名
// 未在 40.8.0 下验证；构造失败时静默不追加入口，记录页仍可从 DYxs 设置页进入。
static id DKXSRecallChatSections(id original) {
    if (![original isKindOfClass:NSArray.class]) return original;
    if (!DKXSArchiveBool(@"DKXSRecallEnabled") || !DKXSArchiveBool(@"DKXSRecallArchiveEntry")) return original;
    Class itemClass = NSClassFromString(@"IESIMChatSettingsItemViewModel");
    if (!itemClass || ![itemClass instancesRespondToSelector:@selector(initWithIdentifier:)]) return original;
    id item = nil;
    @try { item = [[itemClass alloc] initWithIdentifier:DKXSRecallChatItemIdentifier]; } @catch (__unused NSException *e) { return original; }
    if (!item) return original;
    // 标题与点击：多路 KVC 尝试，属性名对不上时只留标题，点按无动作也比崩溃好。
    DKXSArchiveWrite(item, @"title", @"撤回记录");
    DKXSArchiveWrite(item, @"name", @"撤回记录");
    DKXSArchiveWrite(item, @"icon", @"ic_msg_outlined_20");
    void (^open)(void) = ^{ DKXSRecallArchivePresentedFrom(nil, nil); };
    DKXSArchiveWrite(item, @"handler", open);
    DKXSArchiveWrite(item, @"action", open);
    DKXSArchiveWrite(item, @"didSelect", open);
    NSMutableArray *sections = [original mutableCopy];
    [sections addObject:item];
    return sections;
}

// ---- 消息模型层：留存观测 + getter 恢复 + 编辑观测 ----
%hook TIMXOMessage
- (id)content {
    id original = %orig;
    id restored = DKXSRecallContentForMessage(self);
    return restored ?: original;
}
- (void)setContent:(id)content {
    %orig;
    DKXSObserveMessage(self);
}
- (BOOL)recalled {
    BOOL original = %orig;
    return DKXSRecallRecalledDisplay(self, original);
}
- (void)setRecalled:(BOOL)recalled {
    %orig;
    DKXSObserveMessage(self);
}
- (void)setRecalledContent:(id)content {
    %orig;
    DKXSObserveMessage(self);
}
- (void)setEditInfo:(id)info {
    %orig;
    DKXSEditObserveMessage(self, nil, DKXSEditInfoSnapshot(info));
}
- (void)applyAttributesFromModel:(id)model {
    %orig;
    DKXSObserveMessage(self);
    DKXSEditObserveMessage(self, nil, nil);
}
- (void)applyAttributesFromModelV2:(id)model {
    %orig;
    DKXSObserveMessage(self);
    DKXSEditObserveMessage(self, nil, nil);
}
%end

// ---- VM 装配：会话身份 + 恢复呈现 ----
%hook AWEIMMessageViewModel
- (void)setupWithMessage:(id)message {
    %orig;
    DKXSRestoreRecallPresentation(self, message);
}
- (void)setConversation:(id)conversation {
    %orig;
    DKXSObserveMessageContext(self);
}
%end

// ---- 聊天列表：装饰层生命周期 ----
%hook AWEIMMessageListViewController
- (void)viewDidLoad {
    %orig;
    DKXSMessageUIRegisterController((UIViewController *)self);
    DKXSMessageUIInvalidate(NO);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DKXSMessageUIRegisterController((UIViewController *)self);
    DKXSMessageUIInvalidate(YES);
}
- (void)vm_afterReloadData {
    %orig;
    DKXSMessageUIInvalidate(NO);
}
- (void)vm_afterUpdateData {
    %orig;
    DKXSMessageUIInvalidate(NO);
}
- (void)tableView:(id)tableView willDisplayCell:(id)cell forRowAtIndexPath:(id)indexPath {
    %orig;
    DKXSMessageUIBindCell(cell, (UIViewController *)self);
}
%end

// ---- 消息 cell：装饰重定位 + 复用清理（11 类，与上游一致） ----
%hook AWEIMReusableCommonCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMMessageBaseTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMUserMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMCloseFriendInviteMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMInviteFriendTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMShareH5GoodsMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMShareGameMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMShareLiveMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMTextLinkMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMThirdPartLinkMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end
%hook AWEIMVoipMessageTableViewCell
- (void)layoutSubviews { %orig; DKXSMessageUICellLayout(self); }
- (void)prepareForReuse { %orig; DKXSMessageUICellReuse(self); }
%end

// ---- 官方时间头：hideOfficial 开时隐藏 ----
%hook AWEIMMessageBaseHeaderView
- (void)configWithText:(id)text chatHasBackground:(BOOL)hasBackground {
    %orig;
    DKXSMessageUIHideOfficialHeader(self);
}
%end

// ---- 聊天信息页：撤回记录入口 ----
%hook IESIMChatSettingsListViewModelProviderComponent
- (id)createSectionViewModels {
    id original = %orig;
    return DKXSRecallChatSections(original);
}
%end

// ---- 通知 delegate 转发（只在提醒开关开时才包一层；原 delegate 为空时不接管） ----
%hook UNUserNotificationCenter
- (void)setDelegate:(id)delegate {
    %orig;
    if (DKXSArchiveBool(@"DKXSRecallNotifications") || DKXSArchiveBool(@"DKXSEditNotifications")) {
        DKXSArchiveInstallNotificationDelegate();
    }
}
%end

// ---- 存在性自检：Logos 对不存在的方法是静默不生效，40.8.0 下必须能发现 ----
// 只记日志，不改行为；缺失项的含义见 REPORT 第 5 节。
static void DKXSArchiveSelfCheck(void) {
    static NSArray *checks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        checks = @[
            @[@"TIMXOMessage", @"content"], @[@"TIMXOMessage", @"setContent:"],
            @[@"TIMXOMessage", @"recalled"], @[@"TIMXOMessage", @"setRecalled:"],
            @[@"TIMXOMessage", @"setRecalledContent:"], @[@"TIMXOMessage", @"setEditInfo:"],
            @[@"TIMXOMessage", @"applyAttributesFromModel:"], @[@"TIMXOMessage", @"applyAttributesFromModelV2:"],
            @[@"AWEIMMessageViewModel", @"setupWithMessage:"], @[@"AWEIMMessageViewModel", @"setConversation:"],
            @[@"AWEIMMessageListViewController", @"viewDidLoad"], @[@"AWEIMMessageListViewController", @"viewDidAppear:"],
            @[@"AWEIMMessageListViewController", @"vm_afterReloadData"], @[@"AWEIMMessageListViewController", @"vm_afterUpdateData"],
            @[@"AWEIMMessageListViewController", @"tableView:willDisplayCell:forRowAtIndexPath:"],
            @[@"AWEIMMessageBaseHeaderView", @"configWithText:chatHasBackground:"],
            @[@"IESIMChatSettingsListViewModelProviderComponent", @"createSectionViewModels"],
        ];
    });
    NSUInteger missing = 0;
    for (NSArray *check in checks) {
        Class cls = NSClassFromString(check[0]);
        SEL selector = NSSelectorFromString(check[1]);
        if (!cls || !class_getInstanceMethod(cls, selector)) {
            missing++;
            NSLog(@"[DKXS-Archive] hook missing: %@ %@", check[0], check[1]);
        }
    }
    NSLog(@"[DKXS-Archive] self-check done, %lu/%lu present", (unsigned long)(checks.count - missing), (unsigned long)checks.count);
}

%ctor {
    // 延迟自检：抖音类多在启动后陆续加载，%ctor 当下查会误报。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DKXSArchiveSelfCheck();
    });
}
