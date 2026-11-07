// 移植自 Si-yi/DYads- f07ddb5（DYYYRecallStore.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>

/// 本插件自己的串行本地留存，不写抖音数据库、不查询聊天历史。
@interface DKXSRecallStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (void)saveRecord:(NSDictionary *)record completion:(void (^)(NSDictionary *saved, NSString *error))completion;
- (void)recordForAccount:(NSString *)account conversation:(NSString *)conversation message:(NSString *)message server:(NSString *)server completion:(void (^)(NSDictionary *record))completion;
- (void)copyMediaAtPath:(NSString *)source record:(NSDictionary *)record completion:(void (^)(NSDictionary *media, NSString *error))completion;
- (void)clearAccount:(NSString *)account completion:(void (^)(BOOL success))completion;
- (void)statisticsForAccount:(NSString *)account completion:(void (^)(NSDictionary *statistics))completion;
@end
