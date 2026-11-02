//
//  DKXSFloatSpeedButton.h
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatSpeedButton.h；类名 FloatingSpeedButton -> DKXSFloatSpeedButton，全局符号与函数一律 DKXS 前缀。
//
#import <UIKit/UIKit.h>

@interface DKXSFloatSpeedButton : UIButton
@property(nonatomic, assign) CGPoint lastLocation;
@property(nonatomic, weak) id interactionController;
@property(nonatomic, assign) BOOL isLocked;
@property(nonatomic, assign) BOOL justToggledLock;
@property(nonatomic, assign) BOOL originalLockState;
@property(nonatomic, assign) BOOL isResponding;
@property(nonatomic, strong) NSTimer *statusCheckTimer;
@property(nonatomic, strong) NSTimer *fadeTimer;
@property(nonatomic, assign) CGFloat originalAlpha;
+ (void)reloadConfiguration;
+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller;
- (void)saveButtonPosition;
- (void)loadSavedPosition;
- (void)resetButtonState;
- (void)toggleLockState;
- (void)resetFadeTimer;
@property(nonatomic, strong) NSTimer *autoHideTimer;
@property(nonatomic, strong) UIView *edgeIndicatorView;
@property(nonatomic, assign) BOOL isEdgeHidden;
@property(nonatomic, assign) BOOL dkxsEdgeHiddenByClearMode;
@property(nonatomic, assign) BOOL dkxsJustRestoredFromEdgeHidden;
- (void)resetToDefaultPosition;
- (void)dkxs_schedulePresentationTimersIfNeeded;
- (void)dkxs_restoreFromEdgeHidden;
- (void)dkxs_hideEdgeIndicator;
- (void)dkxs_showEdgeIndicator;
@end

#ifdef __cplusplus
extern "C" {
#endif

extern DKXSFloatSpeedButton *dkxsSpeedButton;
extern BOOL dkxsFloatSpeedButtonEnabled;
extern BOOL dkxsShowSpeedX;
extern CGFloat dkxsSpeedButtonSize;

extern NSArray *DKXSGetSpeedOptions(void);
extern NSString *DKXSDefaultSpeedSettingsString(void);
extern BOOL DKXSNormalizeSpeedSettingsForRequiredSpeeds(void);

extern DKXSFloatSpeedButton *DKXSGetSpeedButton(void);
extern NSArray *DKXSFindViewControllersInHierarchy(UIViewController *rootViewController);
extern float DKXSGetCurrentSpeed(void);
extern NSInteger DKXSGetCurrentSpeedIndex(void);
extern void DKXSSetCurrentSpeedIndex(NSInteger index);
extern BOOL DKXSSetCurrentSpeedValue(float speed);
extern void DKXSUpdateSpeedButtonUI(void);
extern id DKXSCurrentSpeedInteractionController(void);

#ifdef __cplusplus
}
#endif
