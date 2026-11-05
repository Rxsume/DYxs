// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>
#import "DKXSHomeDailyFilter.h"
#import "DKXSFeedCardPolicy.h"

//  最小接口声明（只声明本文件用到的成员，不 import 上游 AwemeHeaders / DouyinHeaders）。
@interface AWEFeedTableViewController : UIViewController
@property (nonatomic, strong) id dataController;
- (void)setDataController:(id)controller;
@end
@interface AWEListDataController : NSObject
@property (nonatomic, strong) NSMutableArray *filteredDataSource;
- (void)setFilteredDataSource:(NSMutableArray *)data;
- (void)calculateFilteredDataSource;
@end

%hook AWEFeedTableViewController
- (void)setDataController:(id)controller {
    [DKXSHomeDailyFilter bindFeed:self controller:controller];
    [DKXSFeedCardPolicy bindFeed:self controller:controller];
    %orig(controller);
}
- (void)viewWillAppear:(BOOL)animated {
    // 首次请求可能早于父控制器挂载；显示前补建原生过滤列表，不改原始作品、游标或播放模型。
    id controller = self.dataController;
    BOOL dailyChanged = [DKXSHomeDailyFilter bindFeed:self controller:controller];
    BOOL cardChanged = [DKXSFeedCardPolicy bindFeed:self controller:controller];
    if ((dailyChanged || cardChanged) &&
        [controller respondsToSelector:@selector(calculateFilteredDataSource)]) {
        [controller calculateFilteredDataSource];
    }
    %orig(animated);
}
%end

%hook AWEListDataController
- (void)setFilteredDataSource:(NSMutableArray *)data {
    NSArray *filtered = [DKXSHomeDailyFilter filterArray:data controller:self];
    filtered = [DKXSFeedCardPolicy filterArray:filtered controller:self];
    %orig(filtered);
}
- (void)calculateFilteredDataSource {
    %orig;
    if (![DKXSHomeDailyFilter isEnabledForController:self] && ![DKXSFeedCardPolicy isEnabledForController:self]) return;
    // 兼容原生直接写 ivar 的版本。只在原生计算结束处理一次，绝不在 getter / 每帧布局中删数据。
    NSMutableArray *source = self.filteredDataSource;
    NSArray *filtered = [DKXSHomeDailyFilter filterArray:source controller:self];
    filtered = [DKXSFeedCardPolicy filterArray:filtered controller:self];
    if (filtered != source) self.filteredDataSource = [filtered mutableCopy];
}
%end
