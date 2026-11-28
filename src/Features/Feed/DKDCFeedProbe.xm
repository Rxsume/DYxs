//
//  DKDCFeedProbe.xm
//  首页刷新进入「兴趣探索模式」（双列）的拦截 + 记录。
//  触发签名（用户 2026-11-28 16:06 对照探针导出指认）：
//  tabTap button=AWENormalModeTabBarGeneralButton type=0 selected=2
//  （点首页按钮、当时 selectedIndex=2）。命中签名后 10 秒内：
//  频道页 addChild 双列控制器时拦下不加；双列预览页出现时立即退出。
//  其余路径不拦。事件仍随摇一摇导出带出，真机证实后再删记录部分。
//

#import "DKDCFeedProbe.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface AWEDCFeedSwitchPreviewViewController : UIViewController
@end

@interface AWEHPChannelPageViewController : UIViewController
@end

@interface AWENormalModeTabBarController : UITabBarController
- (void)tabBarButtonDidTouchUpInside:(id)button gestureRecognizer:(id)gesture;
@end

static NSMutableArray<NSString *> *gDCEvents = nil;
static NSTimeInterval gDCStart = 0;
static long long gDCLastTapType = -1;
static NSUInteger gDCLastTapSelected = 0;
static NSTimeInterval gDCLastTapAt = 0;

// 触发签名命中：10 秒内点过 type=0 且当时 selectedIndex=2 的底栏按钮。
static BOOL DKDCShouldBlockExploration(void) {
    if (gDCLastTapAt <= 0) return NO;
    if (CACurrentMediaTime() - gDCLastTapAt > 10) return NO;
    return gDCLastTapType == 0 && gDCLastTapSelected == 2;
}

static void DKDCLog(NSString *format, ...) {
    if (!gDCEvents) {
        gDCEvents = [NSMutableArray array];
        gDCStart = CACurrentMediaTime();
    }
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [gDCEvents addObject:[NSString stringWithFormat:@"[%.2f] %@", CACurrentMediaTime() - gDCStart, text]];
    while (gDCEvents.count > 40) [gDCEvents removeObjectAtIndex:0];
}

static NSString *DKDCClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"(nil)";
}

NSString *DKDCFeedProbeText(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"=== dc feed probe ===\n"];
    if (gDCEvents.count == 0) [out appendString:@"(no events)\n"];
    for (NSString *event in gDCEvents) [out appendFormat:@"%@\n", event];
    return out;
}

%group DKDCFeedProbeHooks

%hook AWEDCFeedSwitchPreviewViewController

- (void)viewDidLoad {
    %orig;
    DKDCLog(@"preview viewDidLoad parent=%@ presenting=%@",
            DKDCClassName(self.parentViewController), DKDCClassName(self.presentingViewController));
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    DKDCLog(@"preview viewWillAppear parent=%@", DKDCClassName(self.parentViewController));
    if (DKDCShouldBlockExploration()) {
        DKDCLog(@"blocked preview (tap signature type=0 selected=2)");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.presentingViewController) {
                [self dismissViewControllerAnimated:NO completion:nil];
            } else if (self.parentViewController) {
                [self willMoveToParentViewController:nil];
                [self.view removeFromSuperview];
                [self removeFromParentViewController];
            }
        });
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DKDCLog(@"preview viewDidAppear parent=%@", DKDCClassName(self.parentViewController));
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    DKDCLog(@"preview viewWillDisappear");
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    DKDCLog(@"preview viewDidDisappear");
}

%end

%hook AWEHPChannelPageViewController

- (void)addChildViewController:(UIViewController *)childController {
    DKDCLog(@"channelPage addChild %@", DKDCClassName(childController));
    if ([DKDCClassName(childController) isEqualToString:@"AWEFeedNewDoubleColumnViewController"] && DKDCShouldBlockExploration()) {
        DKDCLog(@"blocked addChild doubleColumn (tap signature type=0 selected=2)");
        return;
    }
    %orig;
}

%end

%hook AWENormalModeTabBarController

- (void)tabBarButtonDidTouchUpInside:(id)button gestureRecognizer:(id)gesture {
    long long type = -1;
    @try { type = [[button valueForKey:@"type"] longLongValue]; } @catch (__unused NSException *exception) {}
    gDCLastTapType = type;
    gDCLastTapSelected = self.selectedIndex;
    gDCLastTapAt = CACurrentMediaTime();
    DKDCLog(@"tabTap button=%@ type=%lld selected=%lu",
            DKDCClassName(button), type, (unsigned long)self.selectedIndex);
    %orig;
}

%end

%end

%ctor {
    %init(DKDCFeedProbeHooks);
}
