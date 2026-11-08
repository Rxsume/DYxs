// 移植自 Si-yi/DYads- b97c05e（DYYYContentBarAdapter.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

/// 只读取已确认内容外壳中的现成视图，不访问作品模型或私有Swift存储。
@interface DKXSContentBarAdapter : NSObject
+ (BOOL)isRichHost:(UIViewController *)host;
+ (UIView *)topBarInHost:(UIViewController *)host;
+ (UIView *)bottomBarInHost:(UIViewController *)host;
+ (UIScrollView *)viewportInHost:(UIViewController *)host;
+ (NSDictionary<NSString *, UIView *> *)topRoles:(UIView *)bar;
+ (NSDictionary<NSString *, UIView *> *)bottomRoles:(UIView *)bar;
+ (BOOL)isVisible:(UIView *)view in:(UIView *)root;
+ (CGRect)textInk:(UIView *)view in:(UIView *)root;
@end
