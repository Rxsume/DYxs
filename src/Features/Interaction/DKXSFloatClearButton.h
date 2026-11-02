//
//  DKXSFloatClearButton.h
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatClearButton.h；类名 HideUIButton -> DKXSHideUIButton，全局符号与函数一律 DKXS 前缀。
//
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

@class DKXSHideUIButton;

extern DKXSHideUIButton *dkxsHideButton;
extern BOOL dkxsIsPerformingFloatClearOperation;
extern NSArray *dkxsTargetClassNames;
extern char dkxsClearOriginalAlphaKey;

BOOL DKXSIsDynamicAlphaView(UIView *view);
void DKXSApplyClearTargetViewHiddenState(UIView *view);
void DKXSRestoreClearTargetViewStateIfNeeded(UIView *view);

UIWindow *DKXSGetKeyWindow(void);

void DKXSInitTargetClassNames(void);
void DKXSReloadClearButtonConfiguration(void);
void DKXSApplyFloatClearProgressStateToView(UIView *view);

#ifdef __cplusplus
}
#endif

@interface DKXSHideUIButton : UIButton
@property(nonatomic, assign) BOOL isElementsHidden;
@property(nonatomic, assign) BOOL homePurificationActive;
@property(nonatomic, assign) BOOL isLocked;
@property(nonatomic, strong) NSHashTable<UIView *> *hiddenViewsList;
- (void)registerViewForHiding:(UIView *)view;
@property(nonatomic, strong) UIImage *showIcon;
@property(nonatomic, strong) UIImage *hideIcon;
@property(nonatomic, assign) CGFloat originalAlpha;
@property(nonatomic, strong) NSTimer *checkTimer;
@property(nonatomic, strong) NSTimer *fadeTimer;
@property(nonatomic, strong) UIView *edgeIndicatorView;
- (void)resetFadeTimer;
- (void)loadSavedPosition;
- (void)resetToDefaultPosition;
- (void)hideUIElements;
- (void)findAndHideViews:(NSArray *)classNames;
- (void)safeResetState;
- (void)startPeriodicCheck;
- (UIViewController *)findViewController:(UIView *)view;
- (void)loadIcons;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
- (void)handleTap;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handleTouchDown;
- (void)handleTouchUpInside;
- (void)handleTouchUpOutside;
- (void)saveLockState;
- (void)loadLockState;
@end
