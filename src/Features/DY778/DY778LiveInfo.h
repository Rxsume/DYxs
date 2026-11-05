//
//  DY778LiveInfo.h
//  DYxs — 移植自 jijiang2333/DY778 1.0-3（b41e81b）Sources/DY778LiveInfo.h。
//  改动：上游头文件 import 的 DY778Enhancements.h 是 DY778 自身的总入口
//  （还声明 Radar/Confirm/Spark 等未并入 DYxs 的模块），DYxs 不需要它，
//  改为直接 import DY778Core.h + DY778LiveInfoPolicy.h；其余声明与上游一致。
//  注意：直播间开播时长悬浮（上游 DY778LiveClock.m）不在此移植：DYxs 已有
//  等价实现 DKXSLiveDuration.xm（可拖动悬浮窗 + 1 秒 ticker + 位置持久化），
//  不做第二份；仅把 HTSLiveRoomAPI 取开播时间的网络兜底补进 DKXSLiveDuration.xm，
//  复用本文件的 DY778LiveRoomIdentifier / DY778LiveRoomStart /
//  DY778LiveRoomAPIAvailable。DY778InstallLiveInfoHooks 因此只装推荐页预览
//  hooks（DY778InstallPreviewHooks），不装 LiveClock。
//

#import "DY778Core.h"
#import "DY778LiveInfoPolicy.h"

FOUNDATION_EXPORT NSString *DY778LiveRoomIdentifier(id room);
FOUNDATION_EXPORT double DY778LiveRoomStart(id room, NSString *roomID, NSUInteger depth);
FOUNDATION_EXPORT NSString *DY778LiveElapsedText(double start);
FOUNDATION_EXPORT NSString *DY778LiveElapsedDigits(double start);
FOUNDATION_EXPORT void DY778InstallPreviewHooks(void);
FOUNDATION_EXPORT void DY778InstallLiveInfoHooks(void);
FOUNDATION_EXPORT BOOL DY778LiveRoomAPIAvailable(Class cls);

@interface DY778LiveCapsule : UIView
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UIImageView *symbol;
@property(nonatomic) BOOL clock;
- (void)setViewerCountString:(NSString *)text;
- (void)setElapsedString:(NSString *)text;
@end
