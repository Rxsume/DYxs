#import <Foundation/Foundation.h>

// DY778 1.0-8 模块 1 移植：游客身份（请求层去 token + 注入游客 TTWID）与
// 直播身份（进房/退房过程 hook）。hook 目标见
// ~/workspace/plugin-merge/DY778/spec-module1-livetools-guest.md。
// 上游另有独立的 DY778InstallLiveIdentityHooks，本模块为减少入口数量，
// 把进房/退房过程 hook 并入本次安装（见 DY778LiveGuest.m 末尾）。
FOUNDATION_EXPORT void DY778InstallLiveGuestHooks(void);

// DY778 1.1-2 身份范围（DY778LiveIdentityScope 移植，2026-11-27）：
// 身份按 roomID 在进房时绑定——当前房间沿用进入时身份，切后台/下拉
// 状态栏/查看主页/回复私信/小窗不重定；手动切换隐身开关或真正换房
// （不同 roomID）后才重新确定。账号身份房间继续执行已开启的红包/
// 福袋/超级福袋/定时弹幕，游客及切换中暂停，开关本身保留。
// DY778LiveIdentityGuestActive 是全模块统一的「当前是否游客身份」判定：
// 在房内用该房绑定值，房外回退 liveTools.stealth 开关。
FOUNDATION_EXPORT BOOL DY778LiveIdentityGuestActive(void);
FOUNDATION_EXPORT void DY778LiveIdentityRoomEntered(NSString *roomID);
FOUNDATION_EXPORT void DY778LiveIdentityRoomExited(void);
FOUNDATION_EXPORT NSString *DY778LiveIdentityCurrentRoomID(void);
