// 移植自 Si-yi/DYads- 3819b4c（DYYYArticleChrome.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>

@interface DKXSArticleChrome : NSObject
+ (void)preparePreferences;
+ (void)beginAppearance:(UIViewController *)controller;
+ (void)synchronize:(UIViewController *)controller;
+ (void)synchronizeForBar:(UIView *)bar;
+ (id)beginNativeUpdate:(id)origin;
+ (id)beginGeometryUpdate:(id)origin;
+ (UIColor *)backgroundForRichBar:(UIView *)bar native:(UIColor *)color;
+ (void)endNativeUpdate:(id)token;
+ (void)restore:(UIViewController *)controller;
+ (void)refresh;
+ (double)topAreaForHost:(UIViewController *)host native:(double)native;
+ (NSDictionary *)diagnostics;
@end

@interface DKXSArticleChrome (Hooks)
+ (void)installHooks;
@end

// 富内容宿主占位类：原生 Swift 类 AWEKnowledgeRichContentImpl.FullPageFeedTabListViewController
// 及其顶栏/底栏视图；Hooks 文件以 %init 绑定真实类（上游 AwemeHeaders.h 同款做法的最小声明版）。
@interface DKXSRichContentHost : UIViewController
- (void)layoutTabListSubviews;
- (double)topSafeAreaForTabList;
@end
@interface DKXSRichContentTopBar : UIView
@end
@interface DKXSRichContentBottomBar : UIView
@end
@interface DKXSRichContentList : UIViewController
@end
@interface DKXSRichRelationButton : UIButton
@end
