// 移植自 Si-yi/DYads- b97c05e（DYYYInteractionNoticeViewport.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

// 最小接口声明：InteractionNoticeTabListContainerViewController 不在 DKXSAwemeHeaders
//（39.5 导出）里；以下为本模块直接调用的布局入口。
@interface InteractionNoticeTabListContainerViewController : UIViewController
@property (nonatomic, strong, readonly) UIScrollView *containerScrollView;
@property (nonatomic, strong, readonly) UIViewController *currentHeaderViewController;
- (double)topSafeAreaForTabList;
- (double)heightForHeaderView;
- (void)updateHeaderViewLayout;
- (void)layoutTabListSubviews;
@end

@interface DKXSInteractionNoticeViewport : NSObject
+ (double)top:(double)native controller:(UIViewController *)controller;
+ (double)header:(double)native controller:(UIViewController *)controller;
+ (void)beginAppearance:(UIViewController *)controller;
+ (void)prepareController:(UIViewController *)controller;
+ (void)didLayoutController:(UIViewController *)controller;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSInteractionNoticeViewport (RuntimeHooks)
+ (void)installHooks;
@end
