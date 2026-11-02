// 移植来源：Wtrwx/DYYY 的 DYYYCommentPlaybackCoordinator.h。
#import <UIKit/UIKit.h>

@interface DKXSCommentPlaybackCoordinator : NSObject
+ (void)registerViewModel:(id)viewModel;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
+ (BOOL)ownsPlayback;
+ (BOOL)shouldSkipLifecycle:(UIViewController *)controller;
@end
