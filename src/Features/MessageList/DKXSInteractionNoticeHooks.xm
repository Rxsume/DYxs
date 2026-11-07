// 移植自 Si-yi/DYads- cbc2d5a（DYYYInteractionNoticeHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 须先 import UIKit：下方的最小接口声明以 NSObject/UIView/UIViewController 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训）。
#import <UIKit/UIKit.h>
#import "DKXSInteractionNoticeStyle.h"
#import "DKXSChatEnhancementPolicy.h"
// 最小接口声明：以下类在 DKXSAwemeHeaders（39.5 导出）里没有；
// DKXSNative* 是 %hook 占位类，运行时由 installHooks 用 %init 绑定到原生类。
@interface DKXSNativeInteractionNoticeCell : UICollectionViewCell
@end
@interface DKXSNativeFansTableCell : UITableViewCell
@end
@interface DKXSNativeFansCollectionCell : UICollectionViewCell
@end
@interface AWEIMFansContainerViewController : UIViewController
@end
@interface AWEIMFansNewViewController : UIViewController
@end
@interface AWEIMFansAndInteractMergeViewController : UIViewController
@end
static Class DKXSFansTableHookClass;
static Class DKXSFansCollectionHookClass;
static BOOL DKXSNoticeHooksInstalled,DKXSFansContainerHooksInstalled,DKXSFansListHooksInstalled,DKXSFansDisplayHooksInstalled,DKXSFansMergeHooksInstalled,DKXSFansSelectionHooksInstalled;
%group DKXSInteractionNoticeCellHooks
%hook DKXSNativeInteractionNoticeCell
- (void)layoutSubviews { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig; } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} [DKXSInteractionNoticeStyle synchronizeCell:self]; }
- (void)setFrame:(CGRect)frame { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(frame); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)setBounds:(CGRect)bounds { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(bounds); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)didMoveToWindow { %orig;if(((UIView *)self).window)[DKXSInteractionNoticeStyle synchronizeCell:self];else [DKXSInteractionNoticeStyle resetCell:self]; }
- (void)prepareForReuse { [DKXSInteractionNoticeStyle resetCell:self];[DKXSInteractionNoticeStyle clearFansBinding:(UIView *)self];%orig; }
%end
%end
%group DKXSFansControllerHooks
%hook AWEIMFansContainerViewController
- (void)viewDidLayoutSubviews { %orig;[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
- (void)viewDidAppear:(BOOL)animated { %orig(animated);[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
%end
%end
%group DKXSFansTableCellHooks
%hook DKXSNativeFansTableCell
- (void)layoutSubviews { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig; } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} [DKXSInteractionNoticeStyle synchronizeCell:self]; }
- (void)setFrame:(CGRect)frame { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(frame); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)setBounds:(CGRect)bounds { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(bounds); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)didMoveToWindow { %orig;if(((UIView *)self).window)[DKXSInteractionNoticeStyle synchronizeCell:self];else [DKXSInteractionNoticeStyle resetCell:self]; }
- (void)prepareForReuse { [DKXSInteractionNoticeStyle resetCell:self];[DKXSInteractionNoticeStyle clearFansBinding:(UIView *)self];%orig; }
%end
%end
%group DKXSFansCollectionCellHooks
%hook DKXSNativeFansCollectionCell
- (void)layoutSubviews { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig; } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} [DKXSInteractionNoticeStyle synchronizeCell:self]; }
- (void)setFrame:(CGRect)frame { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(frame); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)setBounds:(CGRect)bounds { id t=[DKXSInteractionNoticeStyle beginUpdate:self];@try { %orig(bounds); } @finally {[DKXSInteractionNoticeStyle endUpdate:t];} }
- (void)didMoveToWindow { %orig;if(((UIView *)self).window)[DKXSInteractionNoticeStyle synchronizeCell:self];else [DKXSInteractionNoticeStyle resetCell:self]; }
- (void)prepareForReuse { [DKXSInteractionNoticeStyle resetCell:self];[DKXSInteractionNoticeStyle clearFansBinding:(UIView *)self];%orig; }
%end
%end
%group DKXSFansListLifecycleHooks
%hook AWEIMFansNewViewController
- (void)viewDidLoad { %orig;[DKXSInteractionNoticeStyle installHooks];[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
- (void)viewWillAppear:(BOOL)animated { %orig(animated);[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
- (void)viewDidAppear:(BOOL)animated { %orig(animated);[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
- (void)viewDidLayoutSubviews { %orig;[DKXSInteractionNoticeStyle synchronizeFansController:(UIViewController *)self]; }
%end
%end
%group DKXSFansWillDisplayHooks
%hook AWEIMFansNewViewController
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    %orig(table,cell,path);[DKXSInteractionNoticeStyle prepareFansCell:cell table:table indexPath:path controller:(UIViewController *)self];
}
%end
%end
%group DKXSFansMergedLifecycleHooks
%hook AWEIMFansAndInteractMergeViewController
- (void)viewDidAppear:(BOOL)animated { %orig(animated);[DKXSInteractionNoticeStyle synchronizeMergedController:(UIViewController *)self]; }
%end
%end
%group DKXSFansMergedSelectionHooks
%hook AWEIMFansAndInteractMergeViewController
- (void)setCurrentSelectedIndex:(long long)index { %orig(index);[DKXSInteractionNoticeStyle synchronizeMergedController:(UIViewController *)self]; }
- (void)slidingViewController:(id)controller didSelectIndex:(long long)index transitionType:(long long)type { %orig(controller,index,type);[DKXSInteractionNoticeStyle synchronizeMergedController:(UIViewController *)self]; }
%end
%end
@implementation DKXSInteractionNoticeStyle (RuntimeHooks)
+ (void)installHooks {
    @synchronized(self){
        if(DKXSNoticeHooksInstalled && DKXSFansContainerHooksInstalled && DKXSFansListHooksInstalled && DKXSFansDisplayHooksInstalled && DKXSFansMergeHooksInstalled && DKXSFansSelectionHooksInstalled && DKXSFansTableHookClass)return;
        Class notice=NSClassFromString(@"AWENoticeSwiftBizUI.InteractionNoticeContainerCell");
        if(!DKXSNoticeHooksInstalled && [notice isSubclassOfClass:UICollectionViewCell.class]){ %init(DKXSInteractionNoticeCellHooks,DKXSNativeInteractionNoticeCell=notice);DKXSNoticeHooksInstalled=YES; }
        // 已由两份调试包确认具体关注行，不再等容器先扫描出可见 Cell 才安装。
        [self installFansCellHooksForClass:NSClassFromString(@"AWEIMNewFansTableViewCell")];
        Class fans=NSClassFromString(@"AWEIMFansContainerViewController");
        if(!DKXSFansContainerHooksInstalled && [fans isSubclassOfClass:UIViewController.class] && [DKXSChatEnhancementPolicy class:fans selector:@selector(viewDidLayoutSubviews) result:'v' arguments:@""] && [DKXSChatEnhancementPolicy class:fans selector:@selector(viewDidAppear:) result:'v' arguments:@"B"]){
            %init(DKXSFansControllerHooks);DKXSFansContainerHooksInstalled=YES;
        }
        Class list=NSClassFromString(@"AWEIMFansNewViewController");
        if([list isSubclassOfClass:UIViewController.class] && [DKXSChatEnhancementPolicy class:list selector:@selector(tableView) result:'@' arguments:@""]){
            if(!DKXSFansListHooksInstalled && [DKXSChatEnhancementPolicy class:list selector:@selector(viewWillAppear:) result:'v' arguments:@"B"] && [DKXSChatEnhancementPolicy class:list selector:@selector(viewDidAppear:) result:'v' arguments:@"B"]){%init(DKXSFansListLifecycleHooks);DKXSFansListHooksInstalled=YES;}
            if(!DKXSFansDisplayHooksInstalled && [DKXSChatEnhancementPolicy class:list selector:@selector(tableView:willDisplayCell:forRowAtIndexPath:) result:'v' arguments:@"@@@"]){%init(DKXSFansWillDisplayHooks);DKXSFansDisplayHooksInstalled=YES;}
        }
        Class merge=NSClassFromString(@"AWEIMFansAndInteractMergeViewController");
        if([merge isSubclassOfClass:UIViewController.class] && [DKXSChatEnhancementPolicy class:merge selector:@selector(fansViewController) result:'@' arguments:@""]){
            if(!DKXSFansMergeHooksInstalled && [DKXSChatEnhancementPolicy class:merge selector:@selector(viewDidAppear:) result:'v' arguments:@"B"]){%init(DKXSFansMergedLifecycleHooks);DKXSFansMergeHooksInstalled=YES;}
            if(!DKXSFansSelectionHooksInstalled && [DKXSChatEnhancementPolicy class:merge selector:@selector(setCurrentSelectedIndex:) result:'v' arguments:@"q"] && [DKXSChatEnhancementPolicy class:merge selector:@selector(slidingViewController:didSelectIndex:transitionType:) result:'v' arguments:@"@qq"]){%init(DKXSFansMergedSelectionHooks);DKXSFansSelectionHooksInstalled=YES;}
        }
    }
}
+ (BOOL)installFansCellHooksForClass:(Class)cls {
    if(!cls)return NO;
    NSString *bundle=[NSBundle bundleForClass:cls].bundleIdentifier,*name=NSStringFromClass(cls);
    BOOL known=cls==NSClassFromString(@"AWEIMNewFansTableViewCell");
    if((!known && (!bundle || [bundle hasPrefix:@"com.apple."])) || [name hasPrefix:@"DKXS"] || cls==UITableViewCell.class || cls==UICollectionViewCell.class)return NO;
    if([cls isSubclassOfClass:UITableViewCell.class]){
        if(!DKXSFansTableHookClass){%init(DKXSFansTableCellHooks,DKXSNativeFansTableCell=cls);DKXSFansTableHookClass=cls;}
        return cls==DKXSFansTableHookClass;
    }
    if([cls isSubclassOfClass:UICollectionViewCell.class]){
        if(!DKXSFansCollectionHookClass){%init(DKXSFansCollectionCellHooks,DKXSNativeFansCollectionCell=cls);DKXSFansCollectionHookClass=cls;}
        return cls==DKXSFansCollectionHookClass;
    }return NO;
}
+ (BOOL)installFansCellHooksForCell:(UIView *)cell {return NSThread.isMainThread && [self installFansCellHooksForClass:cell.class];}
+ (NSDictionary *)hookDiagnostics {
    return @{@"noticeCell":@(DKXSNoticeHooksInstalled),@"fansContainer":@(DKXSFansContainerHooksInstalled),@"fansList":@(DKXSFansListHooksInstalled),@"fansWillDisplay":@(DKXSFansDisplayHooksInstalled),@"fansCell":@(DKXSFansTableHookClass!=Nil),@"mergedAppearance":@(DKXSFansMergeHooksInstalled),@"mergedSelection":@(DKXSFansSelectionHooksInstalled)};
}
@end
%ctor { [DKXSInteractionNoticeStyle installHooks]; }
