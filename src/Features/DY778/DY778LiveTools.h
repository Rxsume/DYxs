#import <Foundation/Foundation.h>

// DY778 1.0-8 模块 1 移植：直播间工具（隐身进直播间、定时弹幕、礼物风控）。
// hook 目标见 ~/workspace/plugin-merge/DY778/spec-module1-livetools-guest.md
// 与 /tmp/dy778-108/livetools-hooks.txt（36 个 hook，反汇编实锤）。
FOUNDATION_EXPORT void DY778InstallLiveToolsHooks(void);

// 跨文件房间状态：进房/退房时由 LiveTools 与 LiveGuest 的 hook 调用，
// 用于定时弹幕的房间一致性校验与停止。
FOUNDATION_EXPORT void DY778LiveToolsRoomDidEnter(NSString *roomID);
FOUNDATION_EXPORT void DY778LiveToolsRoomDidExit(void);
