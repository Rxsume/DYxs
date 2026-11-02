//
//  DKXSCommentBlurHooks.xm
//  DYxs（第 4 批 staging，尚未并入 DYxs 源码）
//
//  移植来源：上游 DYYY.xm 里 DYYYFullscreenCommentGroup 组的毛玻璃驱动部分。
//  只保留毛玻璃驱动：Swift 评论内层控制器每次布局时调协调器；
//  上游同组里的 Fullscreen/Floating 同步调用不在本批（Fullscreen 是第 6 批，
//  Floating 已在第 2 批由接线文件处理），故不搬。
//  冲突核查：DYxs src 里没有任何文件 hook 本类（见 REPORT.md），可独立编译。
//  类名解析沿用上游 %group + %ctor 的做法：运行时先用点分名查类，
//  查不到则不装 hook（40.8.0 若改名，静默不生效，不报错）。
//
#import <UIKit/UIKit.h>
#import "DKXSCommentBlurCoordinator.h"

%group DKXSCommentBlurGroup

%hook AWECommentPanelContainerSwiftImpl_CommentContainerInnerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSCommentBlurCoordinator layoutController:self];
}

%end

%end

%ctor {
    Class innerClass = objc_getClass("AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (innerClass && [innerClass isSubclassOfClass:[UIViewController class]]) {
        %init(DKXSCommentBlurGroup, AWECommentPanelContainerSwiftImpl_CommentContainerInnerViewController = innerClass);
    }
}
