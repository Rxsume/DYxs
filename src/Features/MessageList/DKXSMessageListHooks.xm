// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 须先 import UIKit：下方的最小接口声明以 UIViewController/UITableViewCell/UIView 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSMessageListStyle.h"
#import "DKXSInteractionNoticeStyle.h"
#import "DKXSMessageListViewport.h"
#import "DKXSRefreshIndicatorStyle.h"
#import "DKXSInteractionNoticeViewport.h"
#import "DKXSChatEnhancementPolicy.h"
// 最小接口声明（沿用第 8 批写法，不 import 大头文件）：AWEIMChatListViewController /
// AWEIMChatListCommonCell / AWENavigationBar 沿用本批已有声明；新增本次上游用到的
// AWEIMChatTabTableView、AWEIMChatCellRecommendChatLIView、UITableViewCellContentView、
// AWEIMFansAndInteractMergeViewControllerNaviBar（均不在 DKXSAwemeHeaders 39.5 导出里）。
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
@interface AWEIMChatTabTableView : UITableView
@end
@interface AWEIMChatCellRecommendChatLIView : UIView
@property (nonatomic, strong, readonly) UIButton *lightInteractionBtn;
@end
@interface UITableViewCellContentView : UIView
@end
@interface AWEIMFansAndInteractMergeViewControllerNaviBar : UIView
@property (nonatomic, strong, readonly) NSArray<UIView *> *itemViews;
@property (nonatomic, assign, readonly) long long currentSelectedIndex;
@property (nonatomic, strong, readonly) UIView *indicatorView;
- (void)setSelectedIndex:(long long)index;
@end

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
%group DKXSMessageViewportTableHooks
%hook AWEIMChatTabTableView
- (void)setFrame:(CGRect)frame { %orig([DKXSMessageListViewport nativeFrame:frame table:(UITableView *)self]); }
- (void)setContentInsetAdjustmentBehavior:(UIScrollViewContentInsetAdjustmentBehavior)behavior { %orig([DKXSMessageListViewport nativeAdjustment:behavior table:(UITableView *)self]); }
- (void)setContentInset:(UIEdgeInsets)inset { %orig([DKXSMessageListViewport nativeInset:inset table:(UITableView *)self indicator:NO]); }
- (void)setVerticalScrollIndicatorInsets:(UIEdgeInsets)inset { %orig([DKXSMessageListViewport nativeInset:inset table:(UITableView *)self indicator:YES]); }
- (void)didMoveToWindow { %orig;if(!((UIView *)self).window)[DKXSMessageListViewport detachTable:(UITableView *)self]; }
%end
%end
%group DKXSMessageViewportScrollHooks
%hook AWEIMChatListViewController
- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate { %orig(scroll,decelerate);if(!decelerate)[DKXSMessageListViewport synchronizeController:(UIViewController *)self]; }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll { %orig(scroll);[DKXSMessageListViewport synchronizeController:(UIViewController *)self]; }
%end
%end
%group DKXSMessageListDataHooks
%hook AWEIMChatListViewController
- (void)setChatList:(NSArray *)chats { %orig(chats); [DKXSMessageListStyle synchronizeController:self]; }
%end
%end
%group DKXSMessageListRowHeightHooks
%hook AWEIMChatListViewController
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    CGFloat native=%orig(table,path);
    return [DKXSMessageListStyle rowHeight:native controller:self table:table indexPath:path];
}
%end
%end
%group DKXSMessageLightInteractionHooks
%hook AWEIMChatCellRecommendChatLIView
- (void)layoutSubviews { %orig; [DKXSMessageListStyle synchronizeLightInteraction:self]; }
- (void)didMoveToWindow { %orig; if(self.window)[DKXSMessageListStyle synchronizeLightInteraction:self];else [DKXSMessageListStyle resetLightInteraction:self]; }
%end
%end
%group DKXSMessageListCellHooks
%hook AWEIMChatListCommonCell
- (void)layoutSubviews { %orig; [DKXSMessageListStyle synchronizeCell:self]; }
- (void)didMoveToWindow { %orig; if(self.window)[DKXSMessageListStyle synchronizeCell:self];else [DKXSMessageListStyle resetCell:self]; }
- (void)prepareForReuse { [DKXSMessageListStyle resetCell:self]; %orig; }
- (void)renderWithHolder:(id)holder { %orig(holder); [DKXSMessageListStyle synchronizeCell:self]; }
%end
%end
%group DKXSMessageContentGeometryHooks
// 仅接管已关联消息列表状态的 contentView；其他 Cell 原样透传。
%hook UITableViewCellContentView
- (void)setFrame:(CGRect)frame {
    CGRect native=[DKXSMessageListStyle nativeContentFrame:frame forView:self];
    id token=[DKXSMessageListStyle beginContentGeometry:self];
    @try { %orig(native); } @finally { [DKXSMessageListStyle endContentGeometry:token]; }
}
- (void)setBounds:(CGRect)bounds {
    id token=[DKXSMessageListStyle beginContentGeometry:self];
    @try { %orig(bounds); } @finally { [DKXSMessageListStyle endContentGeometry:token]; }
}
- (void)setCenter:(CGPoint)center {
    id token=[DKXSMessageListStyle beginContentGeometry:self];
    @try { %orig(center); } @finally { [DKXSMessageListStyle endContentGeometry:token]; }
}
- (void)setTransform:(CGAffineTransform)transform {
    %orig([DKXSMessageListStyle nativeContentTransform:transform forView:self]);
    [DKXSMessageListStyle didSetContentTransform:self];
}
%end
%end
%group DKXSMessageListBarHooks
%hook AWENavigationBar
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {if([DKXSMessageListStyle passThroughNoticeActions:point bar:(UIView *)self])return nil;return %orig(point,event);}
- (void)setBackgroundColor:(UIColor *)color { %orig([DKXSMessageListStyle nativeBackgroundColor:color forBar:self]); }
- (void)setOpaque:(BOOL)opaque { %orig([DKXSMessageListStyle nativeOpaque:opaque forBar:self]); }
- (void)layoutSubviews { %orig; [DKXSInteractionNoticeStyle installHooks]; [DKXSRefreshIndicatorStyle installHooks]; [DKXSInteractionNoticeViewport installHooks]; [DKXSMessageListStyle synchronizeBar:self]; [DKXSMessageListStyle scheduleBarSynchronization:self]; }
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
%group DKXSNoticeTabSelectionHooks
%hook AWEIMFansAndInteractMergeViewControllerNaviBar
- (void)setSelectedIndex:(long long)index { %orig(index); [DKXSMessageListStyle synchronizeHeaderForView:(UIView *)self]; }
%end
%end
%ctor {
    [DKXSMessageListStyle preparePreferences];
    if([DKXSMessageListStyle contentAdapterReady]) { %init(DKXSMessageContentGeometryHooks); }
    if([DKXSMessageListViewport adapterReady]){%init(DKXSMessageViewportTableHooks);}
    Class list=NSClassFromString(@"AWEIMChatListViewController"),cell=NSClassFromString(@"AWEIMChatListCommonCell");
    if([list isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:list selector:@selector(tableView) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:list selector:@selector(chatList) result:'@' arguments:@""]) {
        %init(DKXSMessageListControllerHooks);
        if([DKXSChatEnhancementPolicy class:list selector:@selector(scrollViewDidEndDragging:willDecelerate:) result:'v' arguments:[@"@" stringByAppendingString:[NSString stringWithUTF8String:@encode(BOOL)]]] && [DKXSChatEnhancementPolicy class:list selector:@selector(scrollViewDidEndDecelerating:) result:'v' arguments:@"@"]) {%init(DKXSMessageViewportScrollHooks);}
        if([DKXSChatEnhancementPolicy class:list selector:@selector(tableView:heightForRowAtIndexPath:) result:@encode(CGFloat)[0] arguments:@"@@"]) { %init(DKXSMessageListRowHeightHooks); }
        if([DKXSChatEnhancementPolicy class:list selector:@selector(setChatList:) result:'v' arguments:@"@"]) { %init(DKXSMessageListDataHooks); }
    }
    Class light=NSClassFromString(@"AWEIMChatCellRecommendChatLIView");
    if([light isSubclassOfClass:UIView.class] && [DKXSChatEnhancementPolicy class:light selector:@selector(lightInteractionBtn) result:'@' arguments:@""]) { %init(DKXSMessageLightInteractionHooks); }
    Class tabs=NSClassFromString(@"AWEIMFansAndInteractMergeViewControllerNaviBar");
    if([tabs isSubclassOfClass:UIView.class] && [DKXSChatEnhancementPolicy class:tabs selector:@selector(setSelectedIndex:) result:'v' arguments:@"q"]) { %init(DKXSNoticeTabSelectionHooks); }
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
