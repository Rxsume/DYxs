#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

FOUNDATION_EXPORT NSString *const DY778Version;
FOUNDATION_EXPORT NSString *const DY778BuildTime;
FOUNDATION_EXPORT NSNotificationName const DY778PreferencesChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DY778RecallChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DY778RecallDetectedNotification;
FOUNDATION_EXPORT void DY778RegisterDefaults(void);
FOUNDATION_EXPORT void DY778ResetSettings(void);
FOUNDATION_EXPORT NSUserDefaults *DY778Preferences(void);
FOUNDATION_EXPORT NSUserDefaults *DY778MigratedPreferences(void);
FOUNDATION_EXPORT BOOL DY778Bool(NSString *key);
FOUNDATION_EXPORT double DY778Number(NSString *key);
FOUNDATION_EXPORT NSString *DY778String(NSString *key);
FOUNDATION_EXPORT NSString *DY778RecallMarkerText(void);
FOUNDATION_EXPORT NSString *DY778EditMarkerText(void);
FOUNDATION_EXPORT void DY778Set(NSString *key, id value);
FOUNDATION_EXPORT id DY778Read(id object, NSString *key);
FOUNDATION_EXPORT BOOL DY778Write(id object, NSString *key, id value);
FOUNDATION_EXPORT NSString *DY778Identifier(id value);
FOUNDATION_EXPORT NSString *DY778CurrentAccountID(void);
FOUNDATION_EXPORT BOOL DY778Hook(Class cls, SEL selector, IMP replacement, IMP *original);
FOUNDATION_EXPORT void DY778RecordHook(NSString *name, BOOL installed);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *DY778HookReport(void);
FOUNDATION_EXPORT UIWindow *DY778ActiveWindow(void);
FOUNDATION_EXPORT UIViewController *DY778TopController(void);
FOUNDATION_EXPORT UIUserInterfaceStyle DY778InterfaceStyle(void);
FOUNDATION_EXPORT UIColor *DY778Accent(void);
FOUNDATION_EXPORT UIColor *DY778Background(void);
FOUNDATION_EXPORT UIColor *DY778CardBackground(void);
FOUNDATION_EXPORT UIImage *DY778MenuIcon(NSString *symbol);
FOUNDATION_EXPORT UIColor *DY778ColorFromHex(NSString *hex, UIColor *fallback);
FOUNDATION_EXPORT void DY778StyleController(UIViewController *controller);
FOUNDATION_EXPORT void DY778PresentController(UIViewController *source, UIViewController *controller);
FOUNDATION_EXPORT void DY778Toast(NSString *message);
FOUNDATION_EXPORT void DY778ShowToast(NSString *channel, NSString *message, BOOL loading, BOOL success);
FOUNDATION_EXPORT void DY778DismissToast(NSString *channel);
FOUNDATION_EXPORT void DY778ShowSpeedToast(NSString *token, double rate);
FOUNDATION_EXPORT void DY778DismissSpeedToast(NSString *token);
FOUNDATION_EXPORT void DY778ShowNotice(UIViewController *source, NSString *title, NSString *message);
FOUNDATION_EXPORT void DY778Confirm(UIViewController *source, NSString *title, NSString *message,
                                  NSString *confirmTitle, BOOL destructive, dispatch_block_t action);
FOUNDATION_EXPORT void DY778ConfirmDelayed(UIViewController *source, NSString *title, NSString *message,
                                         NSTimeInterval delay, dispatch_block_t action);
FOUNDATION_EXPORT void DY778InstallCoreHooks(void);
FOUNDATION_EXPORT void DY778InstallSettingsHook(void);
FOUNDATION_EXPORT UIViewController *DY778SettingsController(void);
// 混合路由观测（DY778RedEnvelope 的 openHybridWithScheme 钩子记录）：
// 福袋入口在 41.2.0 走 Lynx，点开时经此路由打开的 scheme 是发现线索。
FOUNDATION_EXPORT NSUInteger DY778HybridSchemeCount(void);
FOUNDATION_EXPORT NSString *DY778LastHybridScheme(void);
FOUNDATION_EXPORT NSString *DY778LastLotteryScheme(void);
// BDX 弹窗与 Annie 路由观测（DY778RedEnvelope 的 quiet 钩子记录）：
// 福袋入口点击若不走 hybrid 路由，可能走这两条。
FOUNDATION_EXPORT NSUInteger DY778BDXCreateCount(void);
FOUNDATION_EXPORT NSString *DY778LastBDXURL(void);
FOUNDATION_EXPORT NSString *DY778LastLotteryBDXURL(void);
FOUNDATION_EXPORT NSUInteger DY778AnnieSchemaCount(void);
FOUNDATION_EXPORT NSString *DY778LastAnnieSchema(void);
FOUNDATION_EXPORT NSString *DY778LastLotteryAnnieSchema(void);
