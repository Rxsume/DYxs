// 移植自 Si-yi/DYads- f07ddb5（DYYYRecallPolicy.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>

@interface DKXSRecallPolicy : NSObject
+ (NSString *)fingerprint:(NSDictionary *)record;
+ (NSDictionary *)contentSnapshot:(id)content;
+ (BOOL)isRecallPlaceholder:(id)content;
+ (BOOL)canProtectAccount:(NSString *)account sender:(NSString *)sender conversation:(NSString *)conversation message:(NSString *)message content:(NSDictionary *)content;
+ (NSString *)keyForAccount:(NSString *)account conversation:(NSString *)conversation message:(NSString *)message;
+ (NSString *)textForContent:(NSDictionary *)content;
@end
