// 移植自 Si-yi/DYads- 3819b4c（DYYYContentComments.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>

/// 通用内容详情的内嵌评论列表，共用首页评论材质及透明度。
@interface DKXSContentComments : NSObject
+ (void)synchronize:(UIViewController *)host;
+ (void)synchronizeForList:(UIViewController *)list;
+ (void)restore:(UIViewController *)host;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
