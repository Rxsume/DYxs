#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// DKXS 移植层的设置助手：只实现自动消息用到的创建行 / 分区 / 输入框，
/// 原版的依赖联动、冲突处理、图标定制等不移植（移植模块内无此需求）。
/// 返回类型用 id，避免本文件引入 DouyinHeaders，与 DKXSAwemeHeaders 重复声明冲突；
/// 调用方（DKXSAutoMessage.m）本身已通过 DKXSAwemeHeaders 获得 AWESetting* 类型。
@interface DKXSSettingsHelper : NSObject
+ (BOOL)getUserDefaults:(NSString *)key;
+ (void)setUserDefaults:(id)object forKey:(NSString *)key;
+ (void)showTextInputAlert:(NSString *)title
               defaultText:(NSString *)defaultText
               placeholder:(NSString *)placeholder
                 onConfirm:(void (^)(NSString *text))onConfirm
                  onCancel:(void (^)(void))onCancel;
+ (id)createSettingItem:(NSDictionary *)dict;
+ (id)createSectionWithTitle:(NSString *)title items:(NSArray *)items;
+ (id)createSectionWithTitle:(NSString *)title footerTitle:(NSString *)footerTitle items:(NSArray *)items;
+ (UIViewController *)createSubSettingsViewController:(NSString *)title sections:(NSArray *)sectionsArray;
+ (UIViewController *)findViewController:(UIResponder *)responder;
@end
