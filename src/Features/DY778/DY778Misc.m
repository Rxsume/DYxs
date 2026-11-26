#import "DY778Misc.h"
#import "DY778DrawReminder.h"
#import "DY778CommentExpand.h"
#import "DY778ListClear.h"
#import "DY778LiveAppearance.h"

// DY778 1.0-8 模块 4 总入口（规格 §1）。
// 原版三个安装器挂在 _DY778PresentEditHistory 尾部，DYxs 侧按
// 模块 1/2 的约定在 DY778Entry 注册，不照抄触发位置。
// 外观无安装函数，走设置页调用。备份已于 0.6.9.45 去重删除（与 DYxs 本体备份重复）。
void DY778InstallMiscHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallMiscHooks(); }); return; }
    // 抽奖提醒不是 hook 安装器：只 dispatch_async 调 DrawCenter tick。
    DY778InstallDrawReminders();
    // 评论展开：主线程门控 + 全局 once 守卫（内部）。
    DY778InstallCommentExpandHooks();
    // 清理关注：先装 ListNative，再装 UI 刷新 hook（内部）。
    DY778InstallListClearHooks();
}
