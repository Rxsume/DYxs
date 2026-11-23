#import <Foundation/Foundation.h>

// DY778 1.0-8 模块 1 移植：游客身份（请求层去 token + 注入游客 TTWID）与
// 直播身份（进房/退房过程 hook）。hook 目标见
// ~/workspace/plugin-merge/DY778/spec-module1-livetools-guest.md。
// 上游另有独立的 DY778InstallLiveIdentityHooks，本模块为减少入口数量，
// 把进房/退房过程 hook 并入本次安装（见 DY778LiveGuest.m 末尾）。
FOUNDATION_EXPORT void DY778InstallLiveGuestHooks(void);
