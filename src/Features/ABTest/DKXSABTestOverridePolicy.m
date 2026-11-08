// 移植自 Si-yi/DYads- b97c05e（DYYYABTestOverridePolicy.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSABTestOverridePolicy.h"

@implementation DKXSABTestOverridePolicy
+ (NSSet<NSString *> *)nativeLayoutKeys {
    static NSSet *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            @"homepage_long_press_setting",
            @"c2_feed_switch_preview_entry",
            @"c2_recommend_feed_entry_style",
            @"double_column_recommend_exp",
            @"pinch_to_c2_feed"
        ]];
    });
    return keys;
}
+ (NSDictionary *)nativeLayoutValuesFrom:(NSDictionary *)native {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if ([native isKindOfClass:NSDictionary.class])
        for (NSString *key in [self nativeLayoutKeys]) if (native[key]) values[key] = native[key];
    return [values copy];
}
+ (NSDictionary *)configurationForNative:(NSDictionary *)native originalLayout:(NSDictionary *)original
                              overrides:(NSDictionary *)overrides patchMode:(BOOL)patch {
    NSMutableDictionary *baseline = [native isKindOfClass:NSDictionary.class] ? [native mutableCopy] : [NSMutableDictionary dictionary];
    // 合成后的manager值可能已经含有旧增强项，优先采用原生设置回调记录的五项快照。
    if ([original isKindOfClass:NSDictionary.class]) {
        [baseline removeObjectsForKeys:[self nativeLayoutKeys].allObjects];
        [baseline addEntriesFromDictionary:[self nativeLayoutValuesFrom:original]];
    }
    if (![overrides isKindOfClass:NSDictionary.class]) return [baseline copy];
    NSMutableDictionary *custom = [overrides mutableCopy];
    [custom removeObjectsForKeys:[self nativeLayoutKeys].allObjects];
    NSMutableDictionary *result = patch ? [baseline mutableCopy] : [NSMutableDictionary dictionary];
    [result addEntriesFromDictionary:custom];
    // 替换模式也保留这些原生项；不存在的项保持不存在，交给抖音自身默认值。
    for (NSString *key in [self nativeLayoutKeys]) {
        id value = baseline[key];
        if (value) result[key] = value;
        else [result removeObjectForKey:key];
    }
    return [result copy];
}
@end
