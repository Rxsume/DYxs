// 移植自 Si-yi/DYads- f07ddb5（DYYYRecallCoordinator.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
@class AWESettingItemModel;

@interface DKXSRecallCoordinator : NSObject
+ (void)installHooks;
+ (BOOL)enabled;
+ (void)settingsChanged;
+ (void)bindModel:(id)model root:(id)root;
+ (void)captureContent:(id)content model:(id)model;
+ (void)captureOriginalContent:(id)content model:(id)model;
+ (void)observeRecalled:(BOOL)recalled model:(id)model;
+ (BOOL)protectModel:(id)model;
+ (NSDictionary *)protectedContentForModel:(id)model;
+ (id)replacementForUIMessage:(id)message;
+ (id)mediaPathForUIMessage:(id)message original:(id)original;
+ (id)mediaPathsForUIMessage:(id)message original:(id)original;
+ (void)mediaDownloadCompleted:(id)model;
+ (void)captureCell:(UITableViewCell *)cell;
+ (void)resetCell:(UITableViewCell *)cell;
+ (void)controllerAppeared:(UIViewController *)controller;
+ (void)recordHook:(NSString *)name installed:(BOOL)installed;
+ (NSString *)statusText;
+ (void)updateStatusRow:(AWESettingItemModel *)item;
+ (void)clearCurrentAccountFromPresenter:(UIViewController *)presenter statusRow:(AWESettingItemModel *)item;
@end
