//
//  DKInteractionCollapse.h
//  DYxs
//
//  右侧互动区随底栏动态收缩：底栏收成圆键时右侧点赞/评论/收藏/分享栈一起滑出隐藏，
//  底栏展开时回来。状态由 DKGlassTabBar 同步，布局期落定走元素栈统一入口。
//

#ifndef DKInteractionCollapse_h
#define DKInteractionCollapse_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 底栏收缩状态变化时同步右侧栈（带动画）。由 DKGlassTabBarSetCollapsed 与
/// DKGlassTabBarPlatterDidShow 调用。
void DKInteractionCollapseSetCollapsed(BOOL collapsed);

/// 元素栈布局入口调用（在缩放应用之后）：登记右侧栈，收缩中时按当前状态落定。
void DKInteractionCollapseApplyStack(UIView *stack);

#ifdef __cplusplus
}
#endif

#endif /* DKInteractionCollapse_h */
