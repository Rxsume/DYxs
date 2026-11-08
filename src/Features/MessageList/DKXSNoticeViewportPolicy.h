// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeViewportPolicy.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>
// 配对原生 topSafeArea/headerHeight，保留等量空白，避免直接改嵌套滚动偏移。
@interface DKXSNoticeViewportPolicy : NSObject
- (double)topForNative:(double)top enabled:(BOOL)enabled;
- (double)headerForNative:(double)height enabled:(BOOL)enabled;
- (void)beginAppearance;
- (BOOL)reservationMatchesContainerTop:(double)top headerHeight:(double)height pageTop:(double)page;
- (BOOL)validateContainerTop:(double)top headerHeight:(double)height pageTop:(double)page;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) BOOL reservationRejected;
@property (nonatomic, readonly) double nativeTop;
@property (nonatomic, readonly) double nativeHeader;
@property (nonatomic, readonly) double requestedHeader;
@end
