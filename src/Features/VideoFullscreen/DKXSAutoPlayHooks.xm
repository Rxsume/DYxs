//
//  DKXSAutoPlayHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm %group AutoPlay（5 个 hook，原样移植，
//  仅改名）。上游在 %ctor 里还以 DYYYUserAgreementAccepted（用户协议流程）
//  为门，DYxs 没有这套流程，故本移植只以 DKXSEnableAutoPlay 开关为门，
//  开关关时整组不安装，与“装了但开关关”效果一致；其余逻辑与上游一致。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders；Logos %hook 不需要类声明。
//  冲突核查：DYxs 里 3 个文件 hook AWEAwemeDetailTableViewController，
//  但无一 hook hasIphoneAutoPlaySwitch；其余 4 个类/方法在 DYxs 里均无 hook，
//  零同方法冲突。
//
//  39.6.0 兜底（0.6.9.24）：39.5 头文件导出里“AutoPlay”出现 0 次——
//  AWEFeedIPhoneAutoPlayManager、AWEAwemeDetailContainerPlayControlConfig、
//  AWEFeedModuleService 三个类是 40.x 才有的，39.6.0 上原有 5 个 hook 是
//  静默空操作，功能装了等于没装。兜底（%group AutoPlayFallback）直接改
//  播放器控制器 AWEAwemePlayVideoViewController 的 isAutoPlay：详情页
//  （AWEAwemeDetailTableViewController）内的播放器一律置 YES。原有 5 个
//  hook 保留不动，在 40.x 上仍有效。
//  兜底冲突核查（0.6.9.24）：
//  - DKXSBatch5bPlayback.xm 已 hook 同类同方法 setIsAutoPlay: /
//    prepareForDisplay（常驻，无开关门控）。Logos 同方法双 hook 是串联，
//    Batch5b 只在 %orig 后应用默认倍速（默认倍速为 1.0 时直接返回），不改
//    开关语义；无论串联顺序如何，详情页内最终 isAutoPlay 均为 YES，
//    不互相顶掉。
//  - 其余 hook AWEAwemeDetailTableViewController 的文件（DKVideoDetailTable.xm、
//    DKVideoFeedTable.xm、DKChatVideoBottomBar.xm）只 hook 布局/高度/底栏方法，
//    不碰播放状态；兜底只读控制器层级（parent/presenting 链），不与它们冲突。
//  - DY778LivePreview.m 的 prepareForDisplay 是另一套挂载 hook，不在
//    AWEAwemePlayVideoViewController 上。
//
//  兜底第二版（0.6.9.25）：0.6.9.24 真机仍未生效，两个缺口——
//  1. 只覆盖了一个播放器类。DYYY 在三个播放器类上都 hook 了 setIsAutoPlay:
//     （AWEAwemePlayVideoViewController、AWEDPlayerFeedPlayerViewController、
//     AWEDPlayerViewController_Merge），后两个类在 39.5 头文件里有声明，
//     39.6.0 详情页很可能用的是其中之一。本版三个类全覆盖。
//  2. 时机问题。setIsAutoPlay: / prepareForDisplay 可能发生在播放器控制器
//     挂进层级之前（parentViewController 为 nil），沿链找不到详情页，
//     兜底不触发。本版新增可靠触发点：详情页的
//     tableView:willDisplayCell:forRowAtIndexPath:（39.5 头文件有声明，
//     DYxs 里无文件 hook 该方法），此时层级已建立，且每次滑到新作品都会
//     触发；%orig 后递归遍历 childViewControllers，把三个播放器类之一且
//     isAutoPlay 为 NO 的一律置 YES。
//  兜底冲突核查（0.6.9.25）：
//  - Batch5b 同样 hook 了 AWEDPlayerFeedPlayerViewController 的
//    setIsAutoPlay: / prepareForDisplay（%orig 后应用默认倍速），与 v1 的
//    AWEAwemePlayVideoViewController 一样是串联、不顶掉；
//    AWEDPlayerViewController_Merge 的两个方法只有本兜底 hook。
//  - DKVideoDetailTable.xm / DKVideoFeedTable.xm 只 hook 详情页控制器的
//    setupDetailTableView / viewWillLayoutSubviews / 高度类方法，不碰
//    willDisplayCell；其余 willDisplayCell hook 都在别的控制器类上。
//
//  第三版（0.6.9.26）：前两版只改 isAutoPlay（管“显示时自己开始播”），
//  但用户 16:06 澄清的症状是“视频播完了不自动跳下一个”——播完推进是
//  另一条线，isAutoPlay 管不到；DYYY 里也没有播完跳下一个的代码。
//  本版新增“播完推进”：hook AWEDPlayerViewController_Merge 的
//  -playerWillStartNextLoop:（39.5 头文件有声明；
//  DKXSAutoMessageHooks.xm 已 hook 同方法，证实 39.6.0 上真实存在；
//  Logos 同方法双 hook 是串联），视频播完要循环时截住，改滚详情页到
//  下一行。只在开关开且当前为详情页时触发；主推荐页、直播间不触发。
//  推进成功时跳过 %orig（旧视频不循环）；找不到详情页、已是最后一行、
//  或 0.5 秒内同一播放器重复触发时走 %orig（照常循环）。
//  冲突核查（0.6.9.26）：DKXSAutoMessageHooks.xm 的同方法 hook 只做
//  FriendShare 的 playerWillLoop: 上报再 %orig，与本 hook 串联；本 hook
//  跳过 %orig 时那次上报少一次（视频实际没循环，上报本来就不该有），
//  无害。推进只读详情页的 tableView，不 hook 详情页任何方法。
//
//  第四版（0.6.9.27）：0.6.9.26 只做了详情页的播完推进，用户 16:25
//  反馈主推荐页（Feed）播完仍不跳下一个。本版新增推荐页推进：hook
//  AWEFeedTableViewController 的 -videoControllerWillStartNextLoop:
//  （39.5 头文件有声明；DKXSAutoMessageHooks.xm 已 hook 同方法，证实
//  39.6.0 上真实存在；Logos 同方法双 hook 是串联），视频播完要循环
//  时截住，用原生入口 reloadWithCurrentIndex:（FriendShare 的
//  reloadFeed:atIndex: 已在用的跳转入口，同步 Cell、currentAweme 和
//  播放器）滚到 currentIndex+1，再调 playVideoOnScrollDidEnd 触发播放。
//  只在开关开且当前为主推荐 Feed 时触发；搜索页、直播远端流、详情页
//  一律排除（沿 parent/presenting 链查类名）；已是最后一个视频、或
//  0.5 秒内重复触发时走 %orig 照常循环。详情页仍走 0.6.9.26 那套，
//  本版不动它。
//
//  第六版（0.6.9.28）：0.6.9.27 真机仍失败，两个可疑点——
//  1. 触发点 videoControllerWillStartNextLoop: 可能根本不触发（Merge
//     播放器的 %orig 未必会调它）；
//  2. 推进用的 reloadWithCurrentIndex: 只重载数据、不真正滚动/播放，
//     且 39.5 头文件里 AWEFeedTableViewController 根本没有 tableView
//     属性声明，v4 的 feed.tableView 很可能读到 nil 直接返回 NO。
//  本版两个都换掉：主触发点改成三播放器类的
//  -player:updatePlayTime:canPlayTime:totalTime:（DKXSAutoMessageHooks.xm
//  已 hook 同方法做 FriendShare 播放进度上报，证实在主推荐页触发；
//  播到结尾前 0.5 秒推进）；推进改成 scrollToRowAtIndexPath: 滚下一行
//  （与已证实有效的详情页同法，走 Feed 原生滚动结束逻辑播下一个视频，
//  和手动下滑一样；tableView 读不到时沿 view 层级找），0.4 秒后补一次
//  playVideoOnScrollDidEnd / playIfActive。videoControllerWillStartNextLoop:
//  hook 保留并改用新 helper，多一个触发渠道。
//
//  第七版（0.6.9.29）：去掉本版的临时诊断提示（用户要求取消）；其余不动。
//

#import <UIKit/UIKit.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

// 最小接口声明：39.5 头文件里三个播放器控制器都只有极简声明
// （无 setIsAutoPlay: / isAutoPlay）；本文件不 import 上游头文件，按
// PR #31 的教训在此补声明，供兜底读写 isAutoPlay。调用前另有
// respondsToSelector: 守卫，防止 39.6.0 上属性不存在时直接调用崩溃。
@interface AWEAwemePlayVideoViewController : UIViewController
- (void)setIsAutoPlay:(BOOL)isAutoPlay;
- (BOOL)isAutoPlay;
@end

@interface AWEDPlayerFeedPlayerViewController : UIViewController
- (void)setIsAutoPlay:(BOOL)isAutoPlay;
- (BOOL)isAutoPlay;
@end

@interface AWEDPlayerViewController_Merge : UIViewController
- (void)setIsAutoPlay:(BOOL)isAutoPlay;
- (BOOL)isAutoPlay;
@end

// 详情页控制器：本文件内无完整声明，只补推进逻辑要读的 tableView 属性。
// 用 (id) + respondsToSelector: 守卫访问，声明仅作说明。
@interface AWEAwemeDetailTableViewController : UIViewController
@property(nonatomic, strong) UITableView *tableView;
@end

// 主推荐页控制器：39.5 头文件里声明了 videoControllerWillStartNextLoop: /
// playVideoOnScrollDidEnd / playIfActive 等，但无 tableView 属性；本文件
// 不 import 上游头文件，按 PR #31 的教训在此补最小声明。所有调用均用
// (id) + respondsToSelector: 守卫。0.6.9.28 起推进改用 scrollToRowAtIndexPath:
// 滚动，currentIndex / reloadWithCurrentIndex: 不再使用，已从声明里去掉。
@interface AWEFeedTableViewController : UIViewController
@property(nonatomic, strong) UITableView *tableView;
- (void)playVideoOnScrollDidEnd;
- (void)playIfActive;
@end

%group AutoPlay

%hook AWEAwemeDetailTableViewController

- (BOOL)hasIphoneAutoPlaySwitch {
    return YES;
}

%end

%hook AWEAwemeDetailContainerPlayControlConfig

- (BOOL)enableUserProfilePostAutoPlay {
    return YES;
}

%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)isAutoPlayOpen {
    return YES;
}

%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
    return YES;
}
%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)getFeedIphoneAutoPlayState {
    BOOL r = %orig;
    return YES;
}
%end

%end

%group AutoPlayFallback

// 该控制器是不是三个播放器类之一。类不存在时 NSClassFromString 返回 nil，
// isKindOfClass: 返回 NO，不会崩。
static BOOL DKXSAutoPlayIsPlayerVC(UIViewController *vc) {
    if (!vc) return NO;
    static Class playVCClass = nil;
    static Class feedPlayerClass = nil;
    static Class mergePlayerClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        playVCClass = NSClassFromString(@"AWEAwemePlayVideoViewController");
        feedPlayerClass = NSClassFromString(@"AWEDPlayerFeedPlayerViewController");
        mergePlayerClass = NSClassFromString(@"AWEDPlayerViewController_Merge");
    });
    return [vc isKindOfClass:playVCClass] ||
           [vc isKindOfClass:feedPlayerClass] ||
           [vc isKindOfClass:mergePlayerClass];
}

// 该播放器是否处于详情页内：沿 parentViewController / presentingViewController
// 链向上找 AWEAwemeDetailTableViewController。类不存在时 NSClassFromString
// 返回 nil，isKindOfClass: 返回 NO，不会崩。
static BOOL DKXSAutoPlayInDetailPage(UIViewController *vc) {
    for (UIViewController *c = vc; c != nil; ) {
        if ([c isKindOfClass:NSClassFromString(@"AWEAwemeDetailTableViewController")]) {
            return YES;
        }
        UIViewController *next = c.parentViewController;
        if (!next) next = c.presentingViewController;
        if (next == c) break;
        c = next;
    }
    return NO;
}

// 播放器 isAutoPlay 为 NO 时置 YES（带 respondsToSelector: 守卫）。
// 在 prepareForDisplay 里调 setter 会再次触发串联的 setIsAutoPlay: hook，
// 该 hook 见到 YES 直接透传，不递归。
static void DKXSAutoPlayForcePlayer(UIViewController *vc) {
    if (!vc) return;
    if (![vc respondsToSelector:@selector(isAutoPlay)] ||
        ![vc respondsToSelector:@selector(setIsAutoPlay:)]) {
        return;
    }
    if (![(id)vc isAutoPlay]) {
        [(id)vc setIsAutoPlay:YES];
    }
}

// 递归遍历 childViewControllers，把三个播放器类之一且 isAutoPlay 为 NO 的
// 一律置 YES。播放器可能挂在 cell 控制器下，不只在详情页的直接子节点里，
// 故递归；深度上限防异常环。
static void DKXSAutoPlayForceInChildren(UIViewController *vc, int depth) {
    if (!vc || depth > 8) return;
    for (UIViewController *child in vc.childViewControllers) {
        if (DKXSAutoPlayIsPlayerVC(child)) {
            DKXSAutoPlayForcePlayer(child);
        }
        DKXSAutoPlayForceInChildren(child, depth + 1);
    }
}

// ---- 第三版（0.6.9.26）：播完跳下一个 ----

// 沿 parent/presenting 链找详情页控制器；遇到远端直播流
//（AFDPlayRemoteFeedTableViewController）直接返回 nil，不推进。
// 复用 DKXSFullscreenCoordinator usesDetailLayoutForController: 的思路
//（同文件父链 walk + 远端排除）。
static UIViewController *DKXSAutoPlayDetailTableVC(UIViewController *vc) {
    Class detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    for (UIViewController *c = vc; c != nil; ) {
        if (remoteClass && [c isKindOfClass:remoteClass]) return nil;
        if (detailClass && [c isKindOfClass:detailClass]) return c;
        UIViewController *next = c.parentViewController;
        if (!next) next = c.presentingViewController;
        if (next == c) break;
        c = next;
    }
    return nil;
}

// 详情页滚到下一行；成功返回 YES。只读 tableView，不 hook 它。
// 当前行取可视区域中心点所在行（详情页一次只显示一个全屏 cell），
// 取不到时退到第一个可见行；已是最后一行时不推进。
static BOOL DKXSAutoPlayAdvanceDetailTable(UIViewController *detailVC) {
    if (!detailVC) return NO;
    if (![detailVC respondsToSelector:@selector(tableView)]) return NO;
    UITableView *tableView = [(id)detailVC tableView];
    if (!tableView) return NO;
    NSIndexPath *current = [tableView indexPathForRowAtPoint:CGPointMake(CGRectGetMidX(tableView.bounds), CGRectGetMidY(tableView.bounds))];
    if (!current) current = [[tableView indexPathsForVisibleRows] firstObject];
    if (!current) return NO;
    NSInteger nextRow = current.row + 1;
    if (nextRow >= [tableView numberOfRowsInSection:current.section]) return NO;
    NSIndexPath *next = [NSIndexPath indexPathForRow:nextRow inSection:current.section];
    [tableView scrollToRowAtIndexPath:next atScrollPosition:UITableViewScrollPositionTop animated:YES];
    return YES;
}

// ---- 第四版（0.6.9.27）：主推荐页播完跳下一个 ----

// 是不是主推荐 Feed：沿 parent/presenting 链排除直播远端流、搜索页、
// 详情页，命中任一排除类返回 NO；其余（主推荐 Tab、关注 Tab，同为首页
// Feed）认作主推荐页。类不存在时 NSClassFromString 返回 nil，不会崩。
static BOOL DKXSAutoPlayIsMainFeed(UIViewController *vc) {
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    Class searchClass = NSClassFromString(@"AWESearchViewController");
    Class detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    for (UIViewController *c = vc; c != nil; ) {
        if ((remoteClass && [c isKindOfClass:remoteClass]) ||
            (searchClass && [c isKindOfClass:searchClass]) ||
            (detailClass && [c isKindOfClass:detailClass])) {
            return NO;
        }
        UIViewController *next = c.parentViewController;
        if (!next) next = c.presentingViewController;
        if (next == c) break;
        c = next;
    }
    return YES;
}

// ---- 第六版（0.6.9.28）：时间回调触发 + 滚动推进 ----

// 沿 parent/presenting 链找主推荐页控制器；命中排除类（远端直播流、
// 搜索页、详情页）直接返回 nil，没找到也返回 nil。
static UIViewController *DKXSAutoPlayFeedVC(UIViewController *vc) {
    Class feedClass = NSClassFromString(@"AWEFeedTableViewController");
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    Class searchClass = NSClassFromString(@"AWESearchViewController");
    Class detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    for (UIViewController *c = vc; c != nil; ) {
        if ((remoteClass && [c isKindOfClass:remoteClass]) ||
            (searchClass && [c isKindOfClass:searchClass]) ||
            (detailClass && [c isKindOfClass:detailClass])) {
            return nil;
        }
        if (feedClass && [c isKindOfClass:feedClass]) return c;
        UIViewController *next = c.parentViewController;
        if (!next) next = c.presentingViewController;
        if (next == c) break;
        c = next;
    }
    return nil;
}

// 在视图层级里深度优先找第一个 UITableView。参考
// DKXSFullscreenCoordinator pagingViewForCell: 的 isKindOfClass: 判定；
// 39.5 头文件里 Feed 控制器没有 tableView 属性声明，属性读不到时用
// 这个兜底。深度上限防异常层级。
static UITableView *DKXSAutoPlayFindTableViewInView(UIView *view, int depth) {
    if (!view || depth > 6) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *found = DKXSAutoPlayFindTableViewInView(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

// 取 Feed 的 tableView：feed.tableView 有就用，没有就沿 view 层级找。
static UITableView *DKXSAutoPlayFeedTableView(UIViewController *feedVC) {
    if (!feedVC) return nil;
    if ([feedVC respondsToSelector:@selector(tableView)]) {
        UITableView *tableView = [(id)feedVC tableView];
        if (tableView) return tableView;
    }
    UIView *view = feedVC.viewIfLoaded;
    if (!view) return nil;
    return DKXSAutoPlayFindTableViewInView(view, 0);
}

// 推荐页滚到下一行；成功返回 YES。与已证实有效的详情页相同的办法
//（scrollToRowAtIndexPath:，走 Feed 原生滚动结束逻辑播下一个视频，
// 和手动下滑一样）；不调 reloadWithCurrentIndex:。
// 当前行取可视区域中心点所在行，取不到退到第一个可见行；
// 已是最后一行时不推进。
static BOOL DKXSAutoPlayAdvanceFeedByScroll(UIViewController *feedVC) {
    if (!feedVC) return NO;
    UITableView *tableView = DKXSAutoPlayFeedTableView(feedVC);
    if (!tableView) return NO;
    NSIndexPath *current = [tableView indexPathForRowAtPoint:CGPointMake(CGRectGetMidX(tableView.bounds), CGRectGetMidY(tableView.bounds))];
    if (!current) current = [[tableView indexPathsForVisibleRows] firstObject];
    if (!current) return NO;
    NSInteger nextRow = current.row + 1;
    if (nextRow >= [tableView numberOfRowsInSection:current.section]) return NO;
    NSIndexPath *next = [NSIndexPath indexPathForRow:nextRow inSection:current.section];
    [tableView scrollToRowAtIndexPath:next atScrollPosition:UITableViewScrollPositionTop animated:YES];
    return YES;
}

// 滚动发起后 0.4 秒补一次播放触发（有哪个调哪个），防止原生滚动
// 结束逻辑没接上。调用前加 respondsToSelector: 守卫；Feed 控制器
// 已释放时弱引用为 nil，直接返回。
static void DKXSAutoPlayKickFeedPlayback(UIViewController *feedVC) {
    if (!feedVC) return;
    __weak UIViewController *weakFeed = feedVC;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *feed = weakFeed;
        if (!feed) return;
        if ([feed respondsToSelector:@selector(playVideoOnScrollDidEnd)]) {
            [(id)feed playVideoOnScrollDidEnd];
        } else if ([feed respondsToSelector:@selector(playIfActive)]) {
            [(id)feed playIfActive];
        }
    });
}

// 播放时间回调里的推进判断：播到结尾前 0.5 秒、开关开、且在主推荐页
// 时推进一次。调用者每次回调都必须调 %orig，本 helper 只做判断与推进，
// 不断 FriendShare 的串联。同一播放器 2 秒内只推进一次（static 弱引用
// + 时间戳，尝试时即更新，失败导致循环后时间重新走到结尾时 2 秒窗口
// 已过即可再试）；推进成功后补播放触发。
static void DKXSAutoPlayMaybeAdvanceFeedOnTime(UIViewController *playerVC, double time, double total) {
    if (!playerVC) return;
    if (total <= 1 || time < total - 0.5) return;
    if (!DKXSGetBool(@"DKXSEnableAutoPlay")) return;
    UIViewController *feedVC = DKXSAutoPlayFeedVC(playerVC);
    if (!feedVC) return;
    static __weak UIViewController *sLastPlayer = nil;
    static NSTimeInterval sLastAdvanceTime = 0;
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (sLastPlayer == playerVC && now - sLastAdvanceTime < 2.0) return;
    sLastPlayer = playerVC;
    sLastAdvanceTime = now;
    if (DKXSAutoPlayAdvanceFeedByScroll(feedVC)) {
        DKXSAutoPlayKickFeedPlayback(feedVC);
    }
}

%hook AWEAwemePlayVideoViewController

// 调用方传 NO 时，详情页内的播放器改为 YES 再 %orig；详情页外原样 %orig。
- (void)setIsAutoPlay:(BOOL)arg0 {
    if (!arg0 && DKXSAutoPlayInDetailPage(self)) {
        %orig(YES);
    } else {
        %orig;
    }
}

// 39.6.0 的详情页可能根本不调 setter、属性默认 NO：%orig 后再强制置 YES。
- (void)prepareForDisplay {
    %orig;
    if ([self respondsToSelector:@selector(isAutoPlay)] &&
        [self respondsToSelector:@selector(setIsAutoPlay:)] &&
        DKXSAutoPlayInDetailPage(self) && ![self isAutoPlay]) {
        [self setIsAutoPlay:YES];
    }
}

// （第六版）时间回调触发：视频播到结尾前 0.5 秒，主推荐页内推进到
// 下一个视频。每次回调都调 %orig（不断串联）。
- (void)player:(id)player updatePlayTime:(double)time canPlayTime:(double)buffered totalTime:(double)total {
    DKXSAutoPlayMaybeAdvanceFeedOnTime((UIViewController *)self, time, total);
    %orig(player, time, buffered, total);
}

%end

%hook AWEDPlayerFeedPlayerViewController

// 与 AWEAwemePlayVideoViewController 同逻辑；Batch5b 也 hook 了这两个方法，
// 串联只应用默认倍速，不顶掉。
- (void)setIsAutoPlay:(BOOL)arg0 {
    if (!arg0 && DKXSAutoPlayInDetailPage(self)) {
        %orig(YES);
    } else {
        %orig;
    }
}

- (void)prepareForDisplay {
    %orig;
    if ([self respondsToSelector:@selector(isAutoPlay)] &&
        [self respondsToSelector:@selector(setIsAutoPlay:)] &&
        DKXSAutoPlayInDetailPage(self) && ![self isAutoPlay]) {
        [self setIsAutoPlay:YES];
    }
}

// （第六版）时间回调触发：与 AWEAwemePlayVideoViewController 同逻辑。
- (void)player:(id)player updatePlayTime:(double)time canPlayTime:(double)buffered totalTime:(double)total {
    DKXSAutoPlayMaybeAdvanceFeedOnTime((UIViewController *)self, time, total);
    %orig(player, time, buffered, total);
}

%end

%hook AWEDPlayerViewController_Merge

// 与上面两个播放器类同逻辑；这两个方法只有本兜底 hook。
- (void)setIsAutoPlay:(BOOL)arg0 {
    if (!arg0 && DKXSAutoPlayInDetailPage(self)) {
        %orig(YES);
    } else {
        %orig;
    }
}

- (void)prepareForDisplay {
    %orig;
    if ([self respondsToSelector:@selector(isAutoPlay)] &&
        [self respondsToSelector:@selector(setIsAutoPlay:)] &&
        DKXSAutoPlayInDetailPage(self) && ![self isAutoPlay]) {
        [self setIsAutoPlay:YES];
    }
}

// （第六版）时间回调触发：与上面两个播放器类同逻辑。注意
// DKXSAutoMessageHooks.xm 在本类上 hook 了同方法做 FriendShare 播放
// 进度上报，两处串联；本 hook 每次回调都调 %orig，不断链。
- (void)player:(id)player updatePlayTime:(double)time canPlayTime:(double)buffered totalTime:(double)total {
    DKXSAutoPlayMaybeAdvanceFeedOnTime((UIViewController *)self, time, total);
    %orig(player, time, buffered, total);
}

%end

%hook AWEAwemeDetailTableViewController

// 可靠触发点：滑到新作品时 cell 将显示，层级已建立；%orig 后把详情页内
// 三个播放器类之一且 isAutoPlay 为 NO 的一律置 YES。
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    DKXSAutoPlayForceInChildren((UIViewController *)self, 0);
}

%end

%hook AWEDPlayerViewController_Merge

// 视频播完要循环重播时截住：详情页内就滚到下一行（不循环）；
// 详情页外、已是最后一行、或 0.5 秒内同一播放器重复触发时走 %orig 照常循环。
// 注意：DKXSAutoMessageHooks.xm 也 hook 了同方法（FriendShare 上报），
// 两处串联；本 hook 跳过 %orig 时那次上报少一次（视频实际没循环），无害。
- (void)playerWillStartNextLoop:(id)player {
    UIViewController *detailVC = DKXSAutoPlayDetailTableVC((UIViewController *)self);
    if (detailVC) {
        static __weak UIViewController *sLastPlayer = nil;
        static NSTimeInterval sLastAdvanceTime = 0;
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (!(sLastPlayer == self && now - sLastAdvanceTime < 0.5)) {
            if (DKXSAutoPlayAdvanceDetailTable(detailVC)) {
                sLastPlayer = self;
                sLastAdvanceTime = now;
                return; // 已推进，跳过 %orig，旧视频不循环
            }
        }
    }
    %orig;
}

%end

%hook AWEFeedTableViewController

// 视频播完要循环重播时截住：主推荐页内就滚到下一个视频（不循环）；
// 开关关、非主推荐页（搜索/直播/详情页）、已是最后一个视频、
// 或 0.5 秒内重复触发时走 %orig 照常循环。
// 注意：DKXSAutoMessageHooks.xm 也 hook 了同方法（FriendShare 上报），
// 两处串联；本 hook 跳过 %orig 时那次上报少一次（视频实际没循环），无害。
// 开关在 hook 内再读一次：%ctor 只管加载时，关开关后当次会话内即停，
// 不必等重启；与 0.6.9.26 的详情页 hook 保持各自原样，不互相改。
// （第六版）推进改用 scrollToRowAtIndexPath: 滚动 helper（与时间回调
// 同一路），不再调 reloadWithCurrentIndex:；推进成功后补一次播放触发。
- (void)videoControllerWillStartNextLoop:(id)controller {
    if (DKXSGetBool(@"DKXSEnableAutoPlay") && DKXSAutoPlayIsMainFeed((UIViewController *)self)) {
        static __weak AWEFeedTableViewController *sLastFeed = nil;
        static NSTimeInterval sLastAdvanceTime = 0;
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (!(sLastFeed == self && now - sLastAdvanceTime < 0.5)) {
            if (DKXSAutoPlayAdvanceFeedByScroll((UIViewController *)self)) {
                sLastFeed = self;
                sLastAdvanceTime = now;
                DKXSAutoPlayKickFeedPlayback((UIViewController *)self);
                return; // 已推进，跳过 %orig，旧视频不循环
            }
        }
    }
    %orig;
}

%end

%end

%ctor {
    if (DKXSGetBool(@"DKXSEnableAutoPlay")) {
        %init(AutoPlay);
        %init(AutoPlayFallback);
    }
}
