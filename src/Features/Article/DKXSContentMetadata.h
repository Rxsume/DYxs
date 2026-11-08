// 移植自 Si-yi/DYads- 3819b4c（DYYYContentMetadata.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>

/// 隐藏内容详情文案上方的原生创作引导整栏，保留原生列表布局和模型。
@interface DKXSContentMetadata : NSObject
+ (void)synchronize:(UICollectionViewCell *)cell;
+ (void)synchronizeInHost:(UIViewController *)host;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSContentMetadata (Hooks)
+ (void)installHooks;
@end
