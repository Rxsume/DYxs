// 移植来源：Wtrwx/DYYY 的 DYYYFeatureUI.m。
#import "DKXSFeatureUI.h"
#import <objc/runtime.h>
@implementation DKXSFeatureUI
+ (id)value:(id)object key:(NSString *)key { @try { return [object valueForKey:key]; } @catch (__unused NSException *e) { return nil; } }
+ (void)setValue:(id)value object:(id)object key:(NSString *)key { @try { [object setValue:value forKey:key]; } @catch (__unused NSException *e) {} }
+ (id)ivar:(id)object name:(const char *)name { Ivar ivar = object ? class_getInstanceVariable([object class],name) : NULL; return ivar && ivar_getTypeEncoding(ivar)[0] == '@' ? object_getIvar(object,ivar) : nil; }
@end
