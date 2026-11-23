#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 4 移植：直播外观编辑（LiveAppearance）。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md §7
//
// 无独立安装函数，由设置页打开编辑器。
// 值模型（反汇编逐行核对，全部实锤）：结构体 {?=qqd} = 两个 long long
// + 一个 double：alignment（long long）、order（long long）、
// scale（double）。默认 {alignment=1, order=0, scale=1.0}；
// scale 夹取 [0.75, 1.5]；胶囊基宽 294.0、高 28×scale。
// 枚举映射是高置信度静态推断（须运行时以 StoredValue 回读验证）：
// alignment 0=left、1=center（默认）、2=right；
// order 0=viewersFirst（默认）、1=durationFirst。
// 持久化键 liveInfo.cardAppearance（字典 {alignment, order, scale}）。
//
// 应用点（规格 §7.4）：DY778PreviewPreviewState layoutBadgeInView:
// 是直播间胶囊的渲染点；模块 4 不 hook 该类，只读写
// liveInfo.cardAppearance。DYxs 侧模块 1 的 DY778LivePreview 已有
// 自己的胶囊布局，合流点在 DY778LivePreview.m 的
// layoutBadgeInView:（以外观值为准：对齐/顺序/缩放），见 .m 末尾
// 的说明与 DY778LiveAppearanceLayoutX。

typedef struct {
    long long alignment;
    long long order;
    double scale;
} DY778LiveAppearance;

// 纯函数（规格 §7.2，逐行核对）。
FOUNDATION_EXPORT DY778LiveAppearance DY778LiveAppearanceDefault(void);
FOUNDATION_EXPORT double DY778LiveAppearanceClampScale(double value);
FOUNDATION_EXPORT DY778LiveAppearance DY778LiveAppearanceNormalize(DY778LiveAppearance value);
FOUNDATION_EXPORT DY778LiveAppearance DY778LiveAppearanceFromStoredValue(NSDictionary *stored);
FOUNDATION_EXPORT NSDictionary *DY778LiveAppearanceStoredValue(DY778LiveAppearance value);
// 胶囊尺寸：高 = 28×scale；宽 = min(294×scale, 33×scale +
// max(18×scale, ceil(文本宽)))。
FOUNDATION_EXPORT CGSize DY778LiveAppearanceCapsuleSize(CGFloat textWidth, double scale);
// 按（alignment, order, scale）算各子视图 frame；scale 非法时返回零布局。
FOUNDATION_EXPORT void DY778LiveAppearanceComputeLayout(DY778LiveAppearance value, CGRect available, CGRect anchor,
                                                       CGSize viewersSize, CGSize durationSize,
                                                       CGRect *viewersFrame, CGRect *durationFrame);
// 当前外观：DY778Preferences objectForKey:@"liveInfo.cardAppearance"
// → FromStoredValue。
FOUNDATION_EXPORT DY778LiveAppearance DY778LiveAppearanceCurrent(void);
// 按对齐算胶囊的 x（供 DY778LivePreview.m 合流用）。
FOUNDATION_EXPORT CGFloat DY778LiveAppearanceLayoutX(long long alignment, CGRect available, CGFloat anchorMidX, CGFloat width);
// 保存当前外观。
FOUNDATION_EXPORT void DY778LiveAppearanceSave(DY778LiveAppearance value);

// DY778LiveAppearanceDraft（7 方法，规格 §7.3）。
@interface DY778LiveAppearanceDraft : NSObject
@property(nonatomic) DY778LiveAppearance appearance;
@property(nonatomic, readonly) BOOL finished;
- (instancetype)initWithStoredValue:(NSDictionary *)stored;
- (BOOL)isFinished;
- (void)commit;
- (void)cancel;
@end

// DY778LiveAppearancePreview（11 方法，规格 §7.3）。
@interface DY778LiveAppearancePreview : UIView
@property(nonatomic) DY778LiveAppearance appearance;
@property(nonatomic, strong) UIView *group;
@property(nonatomic, strong) UILabel *viewers;
@property(nonatomic, strong) UILabel *duration;
- (void)setAppearance:(DY778LiveAppearance)appearance;
@end

// DY778LiveAppearanceEditor（27 方法，规格 §7.3）。
@interface DY778LiveAppearanceEditor : UITableViewController
@property(nonatomic, strong) DY778LiveAppearanceDraft *draft;
@property(nonatomic, strong) DY778LiveAppearancePreview *preview;
@property(nonatomic, strong) UISegmentedControl *alignmentControl;
@property(nonatomic, strong) UISegmentedControl *orderControl;
@property(nonatomic, strong) UISlider *scaleControl;
@property(nonatomic, strong) UILabel *scaleLabel;
- (void)refreshPreview;
- (void)changeAppearance:(id)sender;
- (void)saveEditing;
@end

// 设置页入口：[DY778LiveAppearanceEditor new] + PresentController
// （规格 §7.1，_DY778PresentLiveAppearanceEditor）。
FOUNDATION_EXPORT void DY778PresentLiveAppearanceEditor(UIViewController *presenter);
