// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFeedCardHooks.xm 的 POI 卡片部分）：改名一律 DYYY -> DKXS。
// 只接 POI 动态卡的布局入口；上游同文件的 AWEFeedTableView setFrame 入口不移植，
// DYxs 已有 DKVideoFeedTable 接管表帧；聊天视频背景组不移植，见 DKXSFeedCardLayout.m 头注。
#import "DKXSFeedCardLayout.h"

// 最小接口声明（只声明本文件 hook 到的类，不 import 上游 AwemeHeaders / DouyinHeaders）。
@interface AWEFeedPOIDynamicCardCellViewController : UIViewController
@end

%group DKXSPOICardFit
%hook AWEFeedPOIDynamicCardCellViewController
- (void)viewWillLayoutSubviews {
    [DKXSFeedCardLayout layoutController:self afterLayout:NO];
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSFeedCardLayout layoutController:self afterLayout:YES];
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    [DKXSFeedCardLayout restoreController:self];
}
%end
%end

%ctor {
    Class poi = NSClassFromString(@"AWEFeedPOIDynamicCardCellViewController");
    if ([poi isSubclassOfClass:UIViewController.class]) { %init(DKXSPOICardFit); }
}
