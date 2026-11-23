#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 4 移植：备份恢复 + 抽奖提醒 + 评论展开 +
// 清理关注 + 直播外观编辑。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md
// 版本：DYxs 0.6.9.36。
//
// 安装入口（规格 §1）：原版三个安装器挂在 _DY778PresentEditHistory
// 尾部，DYxs 侧按模块 1/2 的约定在 DY778Entry 注册，不照抄触发位置。
// DrawReminders 不是 hook 安装器（只 dispatch_async 调 DrawCenter
// tick）；CommentExpand 有全局 once 守卫 + 主线程门控；ListClear 先
// 装 ListNative 再装 4 个 UI 刷新 hook（第 4 个 setTitle:forState:
// 归属未解析，DYxs 侧不安装，见 DY778ListClear.m）。
// 备份与外观无安装函数，走设置页调用。
FOUNDATION_EXPORT void DY778InstallMiscHooks(void);

// 各子安装器（内部用，供 DY778Misc.m 调度；单元复用时可单独调）。
FOUNDATION_EXPORT void DY778InstallDrawReminders(void);
FOUNDATION_EXPORT void DY778InstallCommentExpandHooks(void);
FOUNDATION_EXPORT void DY778InstallListClearHooks(void);
FOUNDATION_EXPORT void DY778InstallListNativeHooks(void);
