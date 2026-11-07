// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListStateStore.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
// 同一个原生表格上的两类状态必须使用独立键，不能复用方法 selector。
@interface DKXSMessageListStateStore : NSObject
+ (id)viewportForObject:(id)object;
+ (void)setViewport:(id)viewport forObject:(id)object;
+ (NSNumber *)separatorForObject:(id)object;
+ (void)setSeparator:(NSNumber *)separator forObject:(id)object;
@end
