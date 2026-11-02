// 移植来源：Wtrwx/DYYY 的 DYYYFeatureUI.h。
#import <Foundation/Foundation.h>
@interface DKXSFeatureUI : NSObject
+ (id)value:(id)object key:(NSString *)key;
+ (void)setValue:(id)value object:(id)object key:(NSString *)key;
+ (id)ivar:(id)object name:(const char *)name;
@end
