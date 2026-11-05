//
//  DKXSBatch5cFilter.xm
//  DYxs 全量合并第 5 批剩余部分（5c）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 8327-8540 行（AWEHotListDataController
//  的 transferAwemeListIfNeededWithArray: 两阶段过滤），符号一律 DYYY* -> DKXS*。
//
//  撞点与分工（主 agent 复核必读）：
//  DYxs 的 DKRecommendationFilter.xm 已 hook 同一方法（DKFilterHotTransfer 组，
//  走 %orig 链）。Logos 允许多个文件 hook 同一方法、按 %orig 链串联，
//  因此本文件独立成 hook、不改 DKRecommendationFilter.xm；两套过滤都是
//  “删作品”，串联后效果是并集。DYxs 已有的 removeLive/removeMusic/
//  removeAds/lowLikes 与本文件部分重叠（见 REPORT），开两边不会出错，
//  只会重复删同一批作品。
//  上游 transfer 里的广告分支未搬：DYxs 的 removeAds 已在同一链路上做广告过滤。
//  上游“不要同时开过多过滤”的延迟提示在 DYYY.xm 里没有对应实现，未搬。
//
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL DKXSFilterGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static NSInteger DKXSFilterGetInteger(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:key];
}

static id DKXSFilterSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL DKXSFilterSafeBool(id object, NSString *key) {
    id v = DKXSFilterSafeValue(object, key);
    if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    return NO;
}

// 上游 dyyy_numberValueForLowLikesFilter：把 "1.2万赞"、"3k"、"1,234" 这类
// 文案解析成数字；解析失败返回 nil（字段缺失时放行，不过滤）。
static NSNumber *DKXSFilterNumberFromLowLikesText(id rawValue) {
    if ([rawValue isKindOfClass:[NSNumber class]]) return rawValue;
    if (![rawValue isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    NSString *normalized = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"," withString:@""];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"+" withString:@""];
    if ([normalized hasSuffix:@"赞"]) normalized = [normalized substringToIndex:normalized.length - 1];
    double multiplier = 1.0;
    NSString *lower = [normalized lowercaseString];
    if ([normalized hasSuffix:@"亿"]) {
        multiplier = 100000000.0;
        normalized = [normalized substringToIndex:normalized.length - 1];
    } else if ([normalized hasSuffix:@"万"] || [lower hasSuffix:@"w"]) {
        multiplier = 10000.0;
        normalized = [normalized substringToIndex:normalized.length - 1];
    } else if ([normalized hasSuffix:@"千"] || [lower hasSuffix:@"k"]) {
        multiplier = 1000.0;
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    NSScanner *scanner = [NSScanner scannerWithString:normalized];
    double d = 0;
    if ([scanner scanDouble:&d] && scanner.isAtEnd) return @((long long)llround(d * multiplier));
    return nil;
}

// 上游 dyyy_resolvedDiggCountForAweme：按多个 keyPath 依次取点赞数。
static NSNumber *DKXSFilterResolvedDiggCount(id aweme) {
    if (!aweme) return nil;
    static NSArray<NSString *> *keyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyPaths = @[
            @"statistics.diggCount", @"statistics.digg_count",
            @"diggCount", @"digg_count",
            @"feedSequenceExtendFeature.digg_count", @"feedSequenceExtendFeature.diggCount",
            @"recommendFeedExtendFeature.digg_count", @"recommendFeedExtendFeature.diggCount"
        ];
    });
    for (NSString *keyPath in keyPaths) {
        id rawValue = nil;
        @try {
            rawValue = [aweme valueForKeyPath:keyPath];
        } @catch (__unused NSException *exception) {
        }
        NSNumber *resolved = DKXSFilterNumberFromLowLikesText(rawValue);
        if (resolved) return resolved;
    }
    return nil;
}

%hook AWEHotListDataController

- (id)transferAwemeListIfNeededWithArray:(id)arg1 isInitFetch:(BOOL)arg2 {
    NSArray *orig = %orig;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) {
        return orig;
    }

    NSInteger daysThreshold = DKXSFilterGetInteger(@"DKXSFilterTimeLimit");
    BOOL skipFriendsVideo = DKXSFilterGetBool(@"DKXSSkipFriendsVideo");
    BOOL skipLive = DKXSFilterGetBool(@"DKXSSkipLive");
    NSInteger minLikesThreshold = DKXSFilterGetInteger(@"DKXSFilterLowLikes");
    BOOL skipPhotoText = DKXSFilterGetBool(@"DKXSSkipPhotoText");
    BOOL skipPhoto = DKXSFilterGetBool(@"DKXSSkipPhoto");
    BOOL skipMusic = DKXSFilterGetBool(@"DKXSSkipMusic");
    BOOL skipHotSpot = DKXSFilterGetBool(@"DKXSSkipHotSpot");
    BOOL skipAIInteraction = DKXSFilterGetBool(@"DKXSSkipAIInteraction");
    // 注意：上游键名是 DYYYSkipLive / DYYYSkipHotSpot / DYYYSkipAIInteraction；
    // DKXS 版键名按“Skip -> Filter”统一成 DKXSSkipLive 等，见 REPORT 键表。
    // （上游另有 DYYYSkipAllLive 键，只在模型级 contentFilter 里用，本文件不用。）
    if (!skipFriendsVideo && !skipLive && !skipPhotoText && !skipPhoto && !skipMusic &&
        !skipHotSpot && !skipAIInteraction && daysThreshold <= 0 && minLikesThreshold <= 0) {
        return orig;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval thresholdInSeconds = MAX(daysThreshold, 0) * 86400.0;
    Class awemeModelClass = NSClassFromString(@"AWEAwemeModel");

    NSMutableArray *baseFiltered = [NSMutableArray arrayWithCapacity:orig.count];
    for (id obj in orig) {
        if (!awemeModelClass || ![obj isKindOfClass:awemeModelClass]) {
            [baseFiltered addObject:obj];
            continue;
        }
        id m = obj;
        NSString *refer = DKXSFilterSafeValue(m, @"referString");
        BOOL isRecommend = [refer isEqualToString:@"homepage_hot"];

        if (skipFriendsVideo && [refer isEqualToString:@"homepage_hot"] &&
            DKXSFilterSafeBool(m, @"isFamiliarItem")) continue;
        if (skipLive && DKXSFilterSafeValue(m, @"cellRoom") != nil) continue;
        // 上游 5e9a5c0 的推广卡判断：除 hotSpotLynxCardModel 外，推荐页的 dCardModel（POI 动态卡）也算推广卡。
        if (skipHotSpot && (DKXSFilterSafeValue(m, @"hotSpotLynxCardModel") != nil ||
            (isRecommend && DKXSFilterSafeValue(m, @"dCardModel") != nil))) continue;
        if (skipPhotoText && DKXSFilterSafeBool(m, @"isNewTextMode") && isRecommend) continue;
        if (skipPhoto && [DKXSFilterSafeValue(m, @"awemeType") integerValue] == 68 && isRecommend) continue;
        if (skipMusic && isRecommend && DKXSFilterSafeValue(m, @"musicCard") != nil) continue;
        if (skipAIInteraction && [DKXSFilterSafeValue(m, @"awemeType") integerValue] == 162 && isRecommend) continue;

        if (daysThreshold > 0) {
            NSTimeInterval vTs = [DKXSFilterSafeValue(m, @"createTime") doubleValue];
            if (vTs > 1e12) vTs /= 1000.0;
            if (vTs > 0 && (now - vTs) > thresholdInSeconds) continue;
        }

        [baseFiltered addObject:obj];
    }

    if (minLikesThreshold <= 0 || baseFiltered.count == 0) {
        return [baseFiltered copy];
    }

    NSMutableArray *lowLikesFiltered = [NSMutableArray arrayWithCapacity:baseFiltered.count];
    for (id obj in baseFiltered) {
        if (!awemeModelClass || ![obj isKindOfClass:awemeModelClass]) {
            [lowLikesFiltered addObject:obj];
            continue;
        }
        NSNumber *digg = DKXSFilterResolvedDiggCount(obj);
        if (!digg) {
            [lowLikesFiltered addObject:obj];
            continue;
        }
        if (digg.integerValue < minLikesThreshold) continue;
        [lowLikesFiltered addObject:obj];
    }
    return [lowLikesFiltered copy];
}

%end
