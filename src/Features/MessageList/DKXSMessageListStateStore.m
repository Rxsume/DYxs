// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListStateStore.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListStateStore.h"
#import <objc/runtime.h>
static char kDKXSMessageListViewportKey;
static char kDKXSMessageListSeparatorKey;
@implementation DKXSMessageListStateStore
+ (id)viewportForObject:(id)object {return objc_getAssociatedObject(object,&kDKXSMessageListViewportKey);}
+ (void)setViewport:(id)viewport forObject:(id)object {if(object)objc_setAssociatedObject(object,&kDKXSMessageListViewportKey,viewport,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
+ (NSNumber *)separatorForObject:(id)object {id value=objc_getAssociatedObject(object,&kDKXSMessageListSeparatorKey);return [value isKindOfClass:NSNumber.class]?value:nil;}
+ (void)setSeparator:(NSNumber *)separator forObject:(id)object {if(object && (!separator || [separator isKindOfClass:NSNumber.class]))objc_setAssociatedObject(object,&kDKXSMessageListSeparatorKey,separator,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
@end
