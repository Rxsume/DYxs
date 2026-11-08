// 移植自 Si-yi/DYads- b97c05e（DYYYABTestOverridePolicy.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>

/// 双列布局与首页点击使用抖音提供的值，不再由增强配置接管。
@interface DKXSABTestOverridePolicy : NSObject
+ (NSSet<NSString *> *)nativeLayoutKeys;
+ (NSDictionary *)nativeLayoutValuesFrom:(NSDictionary *)native;
+ (NSDictionary *)configurationForNative:(NSDictionary *)native originalLayout:(NSDictionary *)original
                              overrides:(NSDictionary *)overrides patchMode:(BOOL)patch;
@end
