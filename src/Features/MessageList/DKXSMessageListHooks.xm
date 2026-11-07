// 移植自 Si-yi/DYads- f07ddb5（DYYYMessageListHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 须先 import UIKit：下方的最小接口声明以 UIViewController/UITableViewCell/UIView 为父类，
// 未引入 UIKit 时编译器找不到父类接口（与 DKXSRecallHooks.xm 在 0.6.9.20 CI run #121 的同类失败）。
#import <UIKit/UIKit.h>
// 最小接口声明（沿用第 8 批写法，不 import 大头文件）。
@interface AWEIMChatListViewController : UIViewController
- (void)setChatList:(NSArray *)chats;
@end
@interface AWEIMChatListCommonCell : UITableViewCell
- (void)renderWithHolder:(id)holder;
- (void)onThemeDidChanged;
@end
@interface AWENavigationBar : UIView
- (void)addRightNaviBarBtnView:(UIView *)view;
- (void)setRightBtnsContainerView:(UIView *)view;
@end
#import "DKXSMessageListStyle.h"
#import "DKXSChatEnhancementPolicy.h"

%group DKXSMessageListControllerHooks
%hook AWEIMChatListViewController
- (void)viewDidLayoutSubviews { %orig; [DKXSMessageListStyle synchronizeController:self]; }
- (void)viewWillAppear:(BOOL)animated { %orig(animated); [DKXSMessageListStyle synchronizeController:self]; }
- (void)viewDidAppear:(BOOL)animated { %orig(animated); [DKXSMessageListStyle synchronizeController:self]; }
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    %orig(table,cell,path); [DKXSMessageListStyle synchronizeCell:cell];
}
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    [DKXSMessageListStyle resetCell:cell]; %orig(table,cell,path);
}
%end
%end
%group DKXSMessageListDataHooks
%hook AWEIMChatListViewController
- (void)setChatList:(NSArray *)chats { %orig(chats); [DKXSMessageListStyle synchronizeController:self]; }
%end
%end
%group DKXSMessageListCellHooks
%hook AWEIMChatListCommonCell
- (void)layoutSubviews { [DKXSMessageListStyle prepareCellLayout:self]; %orig; [DKXSMessageListStyle synchronizeCell:self]; }
- (void)didMoveToWindow { %orig; if(self.window)[DKXSMessageListStyle synchronizeCell:self];else [DKXSMessageListStyle resetCell:self]; }
- (void)prepareForReuse { [DKXSMessageListStyle resetCell:self]; %orig; }
- (void)renderWithHolder:(id)holder { [DKXSMessageListStyle resetCell:self]; %orig(holder); [DKXSMessageListStyle synchronizeCell:self]; }
%end
%end
%group DKXSMessageListBarHooks
%hook AWENavigationBar
- (void)setBackgroundColor:(UIColor *)color { %orig([DKXSMessageListStyle nativeBackgroundColor:color forBar:self]); }
- (void)setOpaque:(BOOL)opaque { %orig([DKXSMessageListStyle nativeOpaque:opaque forBar:self]); }
- (void)layoutSubviews { %orig; [DKXSMessageListStyle synchronizeBar:self]; [DKXSMessageListStyle scheduleBarSynchronization:self]; }
- (void)didMoveToWindow { %orig; [DKXSMessageListStyle synchronizeBar:self]; [DKXSMessageListStyle scheduleBarSynchronization:self]; }
%end
%end
%group DKXSMessageListBarConfigurationHooks
%hook AWENavigationBar
- (void)addRightNaviBarBtnView:(UIView *)view { %orig(view); [DKXSMessageListStyle synchronizeBar:self]; [DKXSMessageListStyle scheduleBarSynchronization:self]; }
- (void)setRightBtnsContainerView:(UIView *)view { %orig(view); [DKXSMessageListStyle synchronizeBar:self]; [DKXSMessageListStyle scheduleBarSynchronization:self]; }
%end
%end
%group DKXSMessageListCellThemeHooks
%hook AWEIMChatListCommonCell
- (void)onThemeDidChanged { %orig; [DKXSMessageListStyle synchronizeCell:self]; }
%end
%end
%ctor {
    [DKXSMessageListStyle preparePreferences];
    Class list=NSClassFromString(@"AWEIMChatListViewController"),cell=NSClassFromString(@"AWEIMChatListCommonCell");
    if([list isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:list selector:@selector(tableView) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:list selector:@selector(chatList) result:'@' arguments:@""]) {
        %init(DKXSMessageListControllerHooks);
        if([DKXSChatEnhancementPolicy class:list selector:@selector(setChatList:) result:'v' arguments:@"@"]) { %init(DKXSMessageListDataHooks); }
    }
    if([cell isSubclassOfClass:UITableViewCell.class] && [DKXSChatEnhancementPolicy class:cell selector:@selector(renderWithHolder:) result:'v' arguments:@"@"]) {
        %init(DKXSMessageListCellHooks);
        if([DKXSChatEnhancementPolicy class:cell selector:@selector(onThemeDidChanged) result:'v' arguments:@""]) { %init(DKXSMessageListCellThemeHooks); }
    }
    Class bar=NSClassFromString(@"AWENavigationBar");
    if([bar isSubclassOfClass:UIView.class] && [DKXSChatEnhancementPolicy class:bar selector:@selector(rightBtnsContainerView) result:'@' arguments:@""]) {
        %init(DKXSMessageListBarHooks);
        if([DKXSChatEnhancementPolicy class:bar selector:@selector(addRightNaviBarBtnView:) result:'v' arguments:@"@"] &&
           [DKXSChatEnhancementPolicy class:bar selector:@selector(setRightBtnsContainerView:) result:'v' arguments:@"@"]) { %init(DKXSMessageListBarConfigurationHooks); }
    }
}
