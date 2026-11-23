//
//  DKVideoDetailTable.xm
//  详情页在建行和分页计算前准备视频表，让原生行位置与 Cell 使用相同高度。
//

#import "DouyinHeaders.h"
#import "DKVideoFeedTable.h"
#import "DKVideoFullscreen.h"
#import <math.h>
#import <objc/runtime.h>

static BOOL gDKDetailHooksInstalled;
static const CGFloat kDKDetailHeightTolerance = 0.5;
static NSUInteger gDKDetailPrepareRuns;
static NSUInteger gDKDetailPrepareChanges;
struct DKDetailHeightStats {
    NSUInteger runs;
    NSUInteger changes;
};
static DKDetailHeightStats gDKDetailFixedStats = {};
static DKDetailHeightStats gDKDetailIndexStats = {};
static DKDetailHeightStats gDKDetailRowStats = {};

static void DKPrepareDetailTable(AWEAwemeDetailTableViewController *controller,
                                 UITableView *table) {
    if (!DKVideoFullscreenOn()) return;
    gDKDetailPrepareRuns++;
    if (DKVideoFeedTablePrepareForController(controller, table)) {
        gDKDetailPrepareChanges++;
    }
}

// 仅统一已接管表中的整页行高；原生特殊行、自动尺寸和未就绪尺寸继续使用原返回值。
static double DKDetailRowHeight(UITableView *table, double nativeHeight,
                                DKDetailHeightStats *stats) {
    if (!DKVideoFullscreenOn() || !NSThread.isMainThread) return nativeHeight;
    stats->runs++;
    NSNumber *original = DKVideoFeedTableOriginalHeight(table);
    CGFloat target = CGRectGetHeight(table.bounds);
    if (!original || !isfinite(nativeHeight) || !isfinite(target)
        || nativeHeight <= 0.0 || target <= original.doubleValue + kDKDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - original.doubleValue) > kDKDetailHeightTolerance
        && fabs(nativeHeight - target) > kDKDetailHeightTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - target) > kDKDetailHeightTolerance) stats->changes++;
    return target;
}

// huami DYYY 3.0.2 (9f35660)：详情页全屏时，行高/翻页基准来自 fixedCellHeight /
// originalTableViewHeight；原生表高是"屏高 - 底栏"，全屏把表拉到屏高后，拉之前
// 量过的行仍是旧值，导致 873/956 混排。这里让基准高度从一开始就是屏高。
// 只在差值 (1, 160) 内才拉满，避免误改其他高度。
// 注意：这几个类属 41.x 接管架构，40.8.0 头文件里没有；各组 %ctor 里查到类
// 与方法才安装，不存在则静默不生效。AWEAwemeDetailTableViewController 的
// fixedCellHeight 已由本文件 DKDetailRowHeight 覆盖，不重复 hook。
static CGFloat DKDetailFullHeight(CGFloat orig) {
    if (!DKVideoFullscreenOn()) return orig;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat diff = screenH - orig;
    return (orig > 1.0 && diff > 1.0 && diff < 160.0) ? screenH : orig;
}

NSString *DKVideoDetailTableStats(void) {
    return [NSString stringWithFormat:
        @"详情行高 Hook=%@  详情建行前准备 跑=%lu 补正=%lu  固定行高 跑=%lu 修正=%lu  "
         "索引行高 跑=%lu 修正=%lu  表代理行高 跑=%lu 修正=%lu",
        gDKDetailHooksInstalled ? @"已安装" : @"入口缺失",
        (unsigned long)gDKDetailPrepareRuns, (unsigned long)gDKDetailPrepareChanges,
        (unsigned long)gDKDetailFixedStats.runs, (unsigned long)gDKDetailFixedStats.changes,
        (unsigned long)gDKDetailIndexStats.runs, (unsigned long)gDKDetailIndexStats.changes,
        (unsigned long)gDKDetailRowStats.runs, (unsigned long)gDKDetailRowStats.changes];
}

%group DKVideoDetailTableHooks

%hook AWEAwemeDetailTableViewController

- (void)setupDetailTableView {
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

- (void)viewWillLayoutSubviews {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

- (double)fixedCellHeight {
    if (!DKVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailFixedStats);
}

- (double)cellHeightAtIndex:(long long)index {
    if (!DKVideoFullscreenOn()) return %orig;
    UITableView *table = self.tableView;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailIndexStats);
}

- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DKVideoFullscreenOn()) return %orig;
    DKPrepareDetailTable(self, table);
    double nativeHeight = %orig;
    return DKDetailRowHeight(table, nativeHeight, &gDKDetailRowStats);
}

- (double)contentOffsetYForCellAtIndex:(long long)index {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    return %orig;
}

- (void)adjustTableViewHeightForTargetIndex:(long long)index {
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
    %orig;
    if (DKVideoFullscreenOn()) DKPrepareDetailTable(self, self.tableView);
}

%end

%end

// huami DYYY 3.0.2 (9f35660) 高度源：行高/翻页偏移的输入端。接管架构下
// tableView 的真实 delegate 链经 AWEDetailFeedScrollDelegateContainer；
// 从直播间/带直播卡的主页进详情时，普通视频行高走 originalTableViewHeight
// 而非 fixedCellHeight；作者正在直播时走直播卡布局的 normalHeight。
// 各组只在 %ctor 查到类与方法时安装。
%group DKDetailScrollDelegateHeightGroup

%hook DKDetailScrollDelegateContainer

- (double)fixedCellHeight {
    return DKDetailFullHeight(%orig);
}

%end

%end

%group DKDetailAdDataHeightGroup

%hook DKDetailAdDataLayer

- (double)originalTableViewHeight {
    return DKDetailFullHeight(%orig);
}

- (void)setOriginalTableViewHeight:(double)height {
    %orig(DKDetailFullHeight(height));
}

%end

%end

%group DKDetailAdVideoHeightGroup

%hook DKDetailAdVideoController

- (double)originalTableViewHeight {
    return DKDetailFullHeight(%orig);
}

- (void)updateOriginalTableViewHeight:(double)height {
    %orig(DKDetailFullHeight(height));
}

%end

%end

%group DKDetailLiveCardHeightGroup

%hook DKDetailLiveCardController

- (double)originalTableViewHeight {
    return DKDetailFullHeight(%orig);
}

- (void)setOriginalTableViewHeight:(double)height {
    %orig(DKDetailFullHeight(height));
}

%end

%end

%group DKDetailLiveCardDataHeightGroup

%hook DKDetailLiveCardDataLayer

- (double)normalHeight {
    return DKDetailFullHeight(%orig);
}

- (double)originalTableViewHeight {
    return DKDetailFullHeight(%orig);
}

- (void)setOriginalTableViewHeight:(double)height {
    %orig(DKDetailFullHeight(height));
}

%end

%end

%ctor {
    Class controllerClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    SEL selectors[] = {
        @selector(setupDetailTableView), @selector(viewWillLayoutSubviews),
        @selector(fixedCellHeight), @selector(cellHeightAtIndex:),
        @selector(tableView:heightForRowAtIndexPath:),
        @selector(contentOffsetYForCellAtIndex:),
        @selector(adjustTableViewHeightForTargetIndex:)
    };
    for (SEL selector : selectors) {
        if (!class_getInstanceMethod(controllerClass, selector)) return;
    }
    %init(DKVideoDetailTableHooks);
    gDKDetailHooksInstalled = YES;

    // huami 3.0.2 高度源各组：类或方法不存在时跳过该组（41.x 接管架构
    // 的类在 40.8.0 可能不存在，静默不生效，不报错）。
    Class dkDetailClass = nil;
    if ((dkDetailClass = objc_getClass("AWEDetailFeedScrollDelegateContainer")) &&
        class_getInstanceMethod(dkDetailClass, @selector(fixedCellHeight))) {
        %init(DKDetailScrollDelegateHeightGroup, DKDetailScrollDelegateContainer = dkDetailClass);
    }
    if ((dkDetailClass = objc_getClass("AWEUserProfileAdDataLayer")) &&
        class_getInstanceMethod(dkDetailClass, @selector(originalTableViewHeight)) &&
        class_getInstanceMethod(dkDetailClass, @selector(setOriginalTableViewHeight:))) {
        %init(DKDetailAdDataHeightGroup, DKDetailAdDataLayer = dkDetailClass);
    }
    if ((dkDetailClass = objc_getClass("AWEUserProFileAdVideoDataController")) &&
        class_getInstanceMethod(dkDetailClass, @selector(originalTableViewHeight)) &&
        class_getInstanceMethod(dkDetailClass, @selector(updateOriginalTableViewHeight:))) {
        %init(DKDetailAdVideoHeightGroup, DKDetailAdVideoController = dkDetailClass);
    }
    if ((dkDetailClass = objc_getClass("AWELivePostWorkLiveCardLayoutController")) &&
        class_getInstanceMethod(dkDetailClass, @selector(originalTableViewHeight)) &&
        class_getInstanceMethod(dkDetailClass, @selector(setOriginalTableViewHeight:))) {
        %init(DKDetailLiveCardHeightGroup, DKDetailLiveCardController = dkDetailClass);
    }
    if ((dkDetailClass = objc_getClass("AWELivePostWorkLiveCardLayoutDataLayer")) &&
        class_getInstanceMethod(dkDetailClass, @selector(normalHeight)) &&
        class_getInstanceMethod(dkDetailClass, @selector(originalTableViewHeight)) &&
        class_getInstanceMethod(dkDetailClass, @selector(setOriginalTableViewHeight:))) {
        %init(DKDetailLiveCardDataHeightGroup, DKDetailLiveCardDataLayer = dkDetailClass);
    }
}
