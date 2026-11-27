//
//  DKDCFeedProbe.xm
//  探针：记录底栏点按、频道页子控制器增减与双列预览页生命周期，
//  定位「点首页刷新进入兴趣探索模式」的触发点。只记录不拦截；
//  定位后换成拦截实现并删掉本探针。
//

#import "DKDCFeedProbe.h"

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
    %orig;
}

%end

%hook AWENormalModeTabBarController

- (void)tabBarButtonDidTouchUpInside:(id)button gestureRecognizer:(id)gesture {
    long long type = -1;
    @try { type = [[button valueForKey:@"type"] longLongValue]; } @catch (__unused NSException *exception) {}
    DKDCLog(@"tabTap button=%@ type=%lld selected=%lu",
            DKDCClassName(button), type, (unsigned long)self.selectedIndex);
    %orig;
}

%end

%end

%ctor {
    %init(DKDCFeedProbeHooks);
}
