// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFeedCardLayout.h）：改名一律 DYYY -> DKXS。
// 只移植 POI 动态卡的底部约束让位；上游的表帧基线（rememberFrame/applyFrame）不移植，
// DYxs 已有 DKVideoFeedTable 存撑高前原高，本文件用 DKFeedCardInset 取同一让位量，
// 与特殊卡/音乐卡/文章的 DKFeedCardFit 共用同一开关与同一基线。
#import <UIKit/UIKit.h>

@interface DKXSFeedCardLayout : NSObject
+ (void)layoutController:(UIViewController *)controller afterLayout:(BOOL)afterLayout;
+ (void)restoreController:(UIViewController *)controller;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
