//
//  DKXSCommentBlurCoordinator.h
//  DYxs（第 4 批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYYCommentBlurCoordinator.h。
//  改名：DYYYCommentBlurCoordinator -> DKXSCommentBlurCoordinator。
//  跟随实际评论面板更新材质，并在关闭开关时恢复原生背景。
//  applyBlurEffectToView 是上游 DYYYUtils 的同名方法的移植版，公开出来
//  供毛玻璃接线片段（DKXSCommentBlurWiring.merge）复用。
//
#import <UIKit/UIKit.h>

@interface DKXSCommentBlurCoordinator : NSObject
+ (void)layoutListView:(UIView *)view;
+ (void)layoutTextView:(UIView *)view;
+ (UIColor *)backgroundColorForTextView:(UIView *)view proposed:(UIColor *)color;
+ (BOOL)opaqueForTextView:(UIView *)view proposed:(BOOL)opaque;
+ (void)layoutController:(UIViewController *)controller;
+ (void)layoutDanmuBackground:(UIView *)container controller:(UIViewController *)controller enabled:(BOOL)enabled;
+ (void)applyBlurEffectToView:(UIView *)view transparency:(CGFloat)transparency blurViewTag:(NSInteger)tag;
@end
