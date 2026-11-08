// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeViewportPolicy.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSNoticeViewportPolicy.h"
#import <math.h>
@interface DKXSNoticeViewportPolicy ()
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL hasTop;
@property (nonatomic) BOOL hasHeader;
@property (nonatomic) BOOL ownedHeader;
@property (nonatomic) double ownedHeaderHeight;
@property (nonatomic, readwrite) BOOL reservationRejected;
@property (nonatomic, readwrite) double nativeTop;
@property (nonatomic, readwrite) double nativeHeader;
@property (nonatomic, readwrite) double requestedHeader;
@end
@implementation DKXSNoticeViewportPolicy
- (BOOL)active {return !self.reservationRejected && self.enabled && self.hasTop && self.hasHeader && self.nativeTop>=32 && self.nativeTop<=180 && self.nativeHeader>=0 && self.nativeHeader<=1;}
- (void)beginAppearance {self.reservationRejected=NO;}
- (BOOL)reservationMatchesContainerTop:(double)top headerHeight:(double)height pageTop:(double)page {
    return self.active && isfinite(top) && isfinite(height) && isfinite(page) && fabs(top)<0.5 && fabs(height-self.requestedHeader)<0.5 && page>=self.requestedHeader-0.5;
}
- (BOOL)validateContainerTop:(double)top headerHeight:(double)height pageTop:(double)page {
    if([self reservationMatchesContainerTop:top headerHeight:height pageTop:page])return YES;
    if(self.active)self.reservationRejected=YES;
    return NO;
}
- (double)topForNative:(double)top enabled:(BOOL)enabled {
    self.enabled=enabled;self.hasTop=isfinite(top);self.nativeTop=top;
    return self.active?0:top;
}
- (double)headerForNative:(double)height enabled:(BOOL)enabled {
    self.enabled=enabled;
    // 原生可能从已布局的 Header.frame 反读高度；撤掉自己的增量再计算。
    BOOL readsOwned=self.ownedHeader && isfinite(height) && fabs(height-self.ownedHeaderHeight)<0.5;
    double base=readsOwned?self.nativeHeader:height;
    self.hasHeader=isfinite(base);self.nativeHeader=base;
    self.requestedHeader=self.active?base+self.nativeTop:base;
    if(self.active){self.ownedHeader=YES;self.ownedHeaderHeight=self.requestedHeader;}
    else if(!readsOwned)self.ownedHeader=NO;
    return self.requestedHeader;
}
@end
