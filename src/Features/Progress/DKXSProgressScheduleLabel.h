//
//  DKXSProgressScheduleLabel.h
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//  进度时长标签（上游 DYYYShowScheduleDisplay 一组）的读数 helper。
//  上游来源：DYYY.xm 里 AWEFeedProgressSlider 的 dyyy_* 方法与
//  DYYYSettings.xm 视频播放分类（DYYYShowScheduleDisplay、DYYYScheduleStyle、
//  DYYYProgressLabelColor、DYYYTimelineVerticalPosition、DYYYHideVideoProgress）。
//  改名：设置键 DYYY* → DKXS*；方法名 dyyy_* → dkxs_*（%new 方法是新增方法，
//  不属于“抖音类上的方法名保持原样”那条规则）。
//

#ifndef DKXSProgressScheduleLabel_h
#define DKXSProgressScheduleLabel_h

#import <UIKit/UIKit.h>

// 以下 C 函数在 DKXSProgressScheduleLabel.m（ObjC）中定义，供 .xm（ObjC++）调用：
// 用 extern "C" 声明，避免 C++ 名称修饰导致链接时找不到 C 符号。
#ifdef __cplusplus
extern "C" {
#endif

/// 显示进度时长总开关（DKXSShowScheduleDisplay，默认关）。
BOOL DKXSProgressScheduleOn(void);

/// 隐藏视频进度开关（DKXSHideVideoProgress，默认关）。
BOOL DKXSHideVideoProgressOn(void);

/// 进度时长样式：把 DKXSScheduleStyle 的下标换算回上游比对用的中文字符串。
/// 选项顺序固定（与 DKXSBatch5Settings.xm 的 DKMakeChoice 顺序一致）：
/// 0 进度条两侧上下、1 进度条左侧剩余、2 进度条左侧完整、3 进度条右侧剩余、4 进度条右侧完整。
/// 下标越界或未设置时返回 nil，调用方按上游默认行为处理（两侧都显示：左=当前、右=总长）。
/// 兼容：若存的是字符串（理论上 DKMakeChoice 不会存字符串），原样返回。
NSString *DKXSProgressScheduleStyleString(void);

/// 进度标签颜色：解析 DKXSProgressLabelColor 的十六进制文本。
/// 支持 #RGB、#RRGGBB、#AARRGGBB（八位忽略前两位透明度，与 DYxs 弹幕十六进制入口同款口径）。
/// 为空或解析失败时返回 nil，调用方按上游 fallback 用白色。
UIColor *DKXSProgressLabelColor(void);

/// 进度纵轴位置：读 DKXSTimelineVerticalPosition 的文本并取 floatValue。
/// 上游原样：缺省 -12.5；配置为 0 时仍取 -12.5（上游 `if (configuredOffset != 0)` 的行为，0 写不进去）。
CGFloat DKXSProgressVerticalOffset(void);

#ifdef __cplusplus
}
#endif

#endif
