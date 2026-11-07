// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListViewport.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
// 仅消息主列表的绘制视口；原生分页容器、行高和消息数据保持原样。
@interface DKXSMessageListViewport : NSObject
+ (BOOL)adapterReady;
+ (void)synchronizeController:(UIViewController *)controller;
+ (CGRect)nativeFrame:(CGRect)frame table:(UITableView *)table;
+ (UIEdgeInsets)nativeInset:(UIEdgeInsets)inset table:(UITableView *)table indicator:(BOOL)indicator;
+ (UIScrollViewContentInsetAdjustmentBehavior)nativeAdjustment:(UIScrollViewContentInsetAdjustmentBehavior)behavior table:(UITableView *)table;
+ (void)detachTable:(UITableView *)table;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
