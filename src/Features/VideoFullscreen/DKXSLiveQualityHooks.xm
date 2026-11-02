//
//  DKXSLiveQualityHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm「调整直播默认清晰度功能」
//  （%hook HTSLiveStreamQualityFragment setupStreamQuality:）。
//  逻辑原样移植，仅改名与日志前缀；键 DKXSLiveQuality 按设置登记存下标，
//  本文件把下标换算成上游的画质名字符串（下标 0 = 自动，跳过）。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders，只给最小接口声明。
//  冲突核查：DYxs src 里没有任何文件 hook 本类本方法，零冲突。
//

#import <UIKit/UIKit.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

@interface HTSLiveStreamQualityFragment : NSObject
@property (nonatomic, strong) NSArray *streamQualityArray;
- (NSArray *)getQualities;
- (void)setResolutionWithIndex:(NSInteger)index isManual:(BOOL)isManual beginChange:(id)beginChange completion:(id)completion;
@end

static NSArray<NSString *> *dkxs_qualityRank = nil;

static NSString *DKXSLivePreferredQuality(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:@"DKXSLiveQuality"];
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSArray<NSString *> *names = @[ @"自动", @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清" ];
        NSInteger index = [(NSNumber *)value integerValue];
        if (index >= 0 && index < (NSInteger)names.count) {
            return names[index];
        }
        return nil;
    }
    return nil;
}

%hook HTSLiveStreamQualityFragment

- (void)setupStreamQuality:(id)arg1 {
    %orig;

    NSString *preferredQuality = DKXSLivePreferredQuality();
    if (!preferredQuality || [preferredQuality isEqualToString:@"自动"]) {
        NSLog(@"[DKXS] Live quality auto - skipping hook");
        return;
    }

    BOOL preferLower = YES;
    NSLog(@"[DKXS] preferredQuality=%@ preferLower=%@", preferredQuality, @(preferLower));

    NSArray *qualities = self.streamQualityArray;
    if (!qualities || qualities.count == 0) {
        qualities = [self getQualities];
    }
    if (!qualities || qualities.count == 0) {
        return;
    }

    if (!dkxs_qualityRank) {
        dkxs_qualityRank = @[ @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清" ];
    }
    NSArray *orderedNames = dkxs_qualityRank;

    NSMutableDictionary<NSString *, NSNumber *> *nameToIndex = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *availableNames = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rankArray = [NSMutableArray array];
    for (NSInteger i = 0; i < qualities.count; i++) {
        id q = qualities[i];
        NSString *name = nil;
        if ([q respondsToSelector:@selector(name)]) {
            name = [q name];
        } else {
            name = [q valueForKey:@"name"];
        }
        if (name) {
            [availableNames addObject:name];
            nameToIndex[name] = @(i);
            NSInteger rank = [orderedNames indexOfObject:name];
            if (rank != NSNotFound) {
                [rankArray addObject:@(rank)];
            }
        }
    }
    NSLog(@"[DKXS] available qualities: %@", availableNames);

    BOOL qualityDesc = YES;
    BOOL qualityAsc = YES;
    for (NSInteger i = 1; i < rankArray.count; i++) {
        NSInteger prev = rankArray[i - 1].integerValue;
        NSInteger curr = rankArray[i].integerValue;
        if (curr < prev) {
            qualityDesc = NO;
        }
        if (curr > prev) {
            qualityAsc = NO;
        }
    }

    NSInteger count = availableNames.count;
    NSInteger (^convertIndex)(NSInteger) = ^NSInteger(NSInteger idx) {
      if (qualityAsc && !qualityDesc) {
          return count - 1 - idx;
      }
      return idx;
    };

    NSArray *searchOrder = orderedNames;

    NSNumber *indexToUse = nameToIndex[preferredQuality];
    if (indexToUse) {
        NSInteger finalIdx = convertIndex(indexToUse.integerValue);
        NSLog(@"[DKXS] exact quality %@ found at index %ld", preferredQuality, (long)finalIdx);
        [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
        return;
    }

    NSInteger targetPos = [orderedNames indexOfObject:preferredQuality];
    if (targetPos == NSNotFound) {
        NSLog(@"[DKXS] preferred quality %@ not in list", preferredQuality);
        return;
    }

    NSInteger step = preferLower ? 1 : -1;
    BOOL applied = NO;
    for (NSInteger pos = targetPos + step; pos >= 0 && pos < searchOrder.count; pos += step) {
        NSString *candidate = searchOrder[pos];
        NSNumber *idx = nameToIndex[candidate];
        if (idx) {
            NSInteger finalIdx = convertIndex(idx.integerValue);
            NSLog(@"[DKXS] fallback quality %@ at index %ld", candidate, (long)finalIdx);
            [self setResolutionWithIndex:finalIdx isManual:YES beginChange:nil completion:nil];
            applied = YES;
            break;
        }
    }
    if (!applied) {
        NSLog(@"[DKXS] no suitable fallback quality found");
    }
}

%end

%ctor {
    %init;
}
