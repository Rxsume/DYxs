//
//  DKXSBatch5cModelFilter.xm
//  DYxs 全量合并第 5 批剩余部分（5c）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 8543-8900 行（AWEAwemeModel 的
//  initWithDictionary: 模型级过滤 + HDR 剥离）与第 1015-1185 行的
//  enableHDR / bitrateModels 钩子，符号一律 DYYY* -> DKXS*。
//  HDR 工具函数在 DKXSHDRHelpers.h（同一批 staging，只被本文件 import）。
//
//  与上游的差异（主 agent 复核必读）：
//  1. 广告分支未搬：init 里的 DYYYNoAds 分支（isAdvertisement 判定）不做，
//     因为 DYxs 的 DKContentFilter removeAds 已在转换/缓存链路上过滤广告；
//     本文件的模型级过滤只做朋友/热点/直播/图文/图集/音乐/AI/关键词/用户/
//     拍同款 + HDR 两档。不要另登记 DKXSNoAds，避免与 removeAds 造两个
//     作用重叠的开关。
//  2. contentFilter 里的 shouldFilterTime / shouldFilterLowLikes 在上游就是
//     只声明不赋值（恒 NO），时限与低赞只在 transfer 钩子生效；本文件原样
//     保留该行为，不“修复”它。
//  3. 用户过滤只按短 ID 匹配：上游解析了“昵称-短ID”里的昵称但从未用它比较，
//     本文件原样只比短 ID；昵称里带 "-" 的条目按上游规则取最后一段为 ID。
//  4. 关键词/用户列表复用第 4 批已有的 DKXSFilterKeywords / DKXSFilterUsers
//     键（上游长按面板“过滤”与推荐过滤共用同一批 DYYYFilter* 键，
//     本移植保持共用，不另建键）；DKXSFilterProp（拍同款）是新键。
//  5. HDR 的图层/金属层/AVPlayerItem 元数据剥离钩子（上游第 1575-1800 行
//     一带）未搬，只搬模型级：init 过滤、setVideo/setAlbumImages 剥离、
//     awe_enableHDR、bitrateModels 过滤、播放器 enableHDR。真机若发现
//     HDR 仍从图层漏出，再补那批钩子。
//
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "DKXSHDRHelpers.h"

// 最小接口声明：本文件 %hook AWEAwemeModel，并调用同文件 %new 的三个 DKXS 方法；
// 只声明调用处用到的成员（基类按抖音模型惯例为 NSObject），不 import DouyinHeaders。
@interface AWEAwemeModel : NSObject
- (BOOL)dkxs_shouldExcludeFromGlobalHDRFilter;
- (BOOL)dkxs_containsHDRMetadataInObject:(id)object depth:(NSUInteger)depth;
- (BOOL)dkxs_contentFilter;
@end

static BOOL DKXSModelGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static id DKXSModelSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

%hook AWEAwemeModel

- (id)initWithDictionary:(id)arg1 error:(id *)arg2 {
    id orig = %orig;
    if (orig) {
        BOOL shouldDisableHDR = DKXSShouldDisableAllHDR();
        BOOL shouldFilterOnlyHDRSource = NO;
        if (shouldDisableHDR && ![self dkxs_shouldExcludeFromGlobalHDRFilter]) {
            shouldFilterOnlyHDRSource = DKXSAwemeModelHasOnlyHDRBitrateModels(self);
            if (!shouldFilterOnlyHDRSource) {
                shouldFilterOnlyHDRSource = DKXSRawObjectHasOnlyHDRBitrateModels(arg1);
                if (shouldFilterOnlyHDRSource) {
                    objc_setAssociatedObject(self, &kDKXSHDROnlyAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        BOOL shouldFilter = [self dkxs_contentFilter];
        if (!shouldFilter && shouldFilterOnlyHDRSource) {
            shouldFilter = YES;
        }
        if (!shouldFilter && DKXSShouldFilterGlobalHDR() &&
            ![self dkxs_shouldExcludeFromGlobalHDRFilter] &&
            [self dkxs_containsHDRMetadataInObject:arg1 depth:0]) {
            shouldFilter = YES;
        }
        if (shouldFilter) {
            return nil;
        }
        if (shouldDisableHDR) {
            DKXSStripHDRHintsFromAwemeModel(self);
        }
    }
    return orig;
}

- (void)setVideo:(id)video {
    DKXSStripHDRHintsFromVideoModel(video);
    %orig;
}

- (void)setAlbumImages:(id)albumImages {
    if (DKXSShouldDisableAllHDR()) {
        for (id imageModel in albumImages) {
            DKXSStripHDRHintsFromVideoModel(DKXSValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
    %orig;
}

- (BOOL)awe_enableHDR {
    if (DKXSShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}

- (id)awe_HDRValueFor:(long long)value enableHDR:(BOOL)enableHDR {
    return %orig(value, DKXSShouldDisableAllHDR() ? NO : enableHDR);
}

%new
- (BOOL)dkxs_shouldExcludeFromGlobalHDRFilter {
    NSString *referString = [[DKXSModelSafeValue(self, @"referString") lowercaseString] ?: @"" copy];
    if (referString.length == 0) {
        return NO;
    }
    return [referString isEqualToString:@"chat"] ||
           [referString containsString:@"chat_room"] ||
           [referString containsString:@"message"] ||
           [referString containsString:@"forward"] ||
           [referString containsString:@"private"] ||
           [referString containsString:@"share"] ||
           [referString hasPrefix:@"im_"] ||
           [referString containsString:@"_im_"];
}

%new
- (BOOL)dkxs_containsHDRMetadataInObject:(id)object depth:(NSUInteger)depth {
    if (!object || depth > 8) {
        return NO;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [[rawKey description] lowercaseString];
            NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
            if (([key isEqualToString:@"is_source_hdr"] || [key isEqualToString:@"has_filter_hdr"]) && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_type"] && numericValue > 0) {
                return YES;
            }
            if ([key isEqualToString:@"hdr_bit"] && numericValue >= 10) {
                return YES;
            }
            if (([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) &&
                [self dkxs_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            if ([self dkxs_containsHDRMetadataInObject:value depth:depth + 1]) {
                return YES;
            }
        }
    }
    return NO;
}

// 上游 %new contentFilter：模型级推荐过滤。注意本方法名是 DKXS 侧新增方法，
// 不属于“抖音类上的方法名保持原样”那条规则；init 钩子调它。
%new
- (BOOL)dkxs_contentFilter {
    BOOL skipAllLive = DKXSModelGetBool(@"DKXSSkipAllLive");
    BOOL skipHotSpot = DKXSModelGetBool(@"DKXSSkipHotSpot");
    BOOL skipPhoto = DKXSModelGetBool(@"DKXSSkipPhoto");
    BOOL skipPhotoText = DKXSModelGetBool(@"DKXSSkipPhotoText");
    BOOL skipMusic = DKXSModelGetBool(@"DKXSSkipMusic");
    BOOL skipAIInteraction = DKXSModelGetBool(@"DKXSSkipAIInteraction");
    BOOL filterHDR = DKXSShouldFilterGlobalHDR();

    NSString *referString = DKXSModelSafeValue(self, @"referString") ?: @"";
    NSString *videoFeedTag = DKXSModelSafeValue(self, @"videoFeedTag") ?: @"";
    BOOL isRecommendFeed = [referString isEqualToString:@"homepage_hot"];
    BOOL shouldFilterHotSpot = skipHotSpot && DKXSModelSafeValue(self, @"hotSpotLynxCardModel") != nil;
    BOOL shouldFilterAllLive = skipAllLive && [videoFeedTag isEqualToString:@"直播中"];
    BOOL shouldskipPhoto = skipPhoto && ([DKXSModelSafeValue(self, @"awemeType") integerValue] == 68) && isRecommendFeed;
    BOOL shouldskipPhotoText = skipPhotoText && [DKXSModelSafeValue(self, @"isNewTextMode") boolValue] && isRecommendFeed;
    BOOL shouldFilterFriendsVideo = DKXSModelGetBool(@"DKXSSkipFriendsVideo") && isRecommendFeed &&
        [DKXSModelSafeValue(self, @"isFamiliarItem") boolValue];
    BOOL shouldFilterMusic = skipMusic && DKXSModelSafeValue(self, @"musicCard") != nil && isRecommendFeed;
    BOOL shouldFilterAIInteraction = skipAIInteraction && ([DKXSModelSafeValue(self, @"awemeType") integerValue] == 162) && isRecommendFeed;
    BOOL shouldFilterHDR = NO;
    BOOL shouldFilterKeywords = NO;
    BOOL shouldFilterProp = NO;
    BOOL shouldFilterUser = NO;

    // 与第 4 批长按面板共用的两个列表键（逗号分隔）。
    NSString *filterKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterKeywords"];
    NSArray *keywordsList = nil;
    if (filterKeywords.length > 0) {
        keywordsList = [filterKeywords componentsSeparatedByString:@","];
    }
    NSString *filterProp = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterProp"];
    NSArray *propKeywordsList = nil;
    if (filterProp.length > 0) {
        propKeywordsList = [filterProp componentsSeparatedByString:@","];
    }
    NSString *filterUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterUsers"];

    BOOL disableHDR = DKXSShouldDisableAllHDR();

    if (isRecommendFeed && filterUsers.length > 0) {
        id author = DKXSModelSafeValue(self, @"author");
        NSString *currentShortID = DKXSModelSafeValue(author, @"shortID");
        if (currentShortID.length > 0) {
            NSArray *usersList = [filterUsers componentsSeparatedByString:@","];
            for (NSString *userInfo in usersList) {
                NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                if (components.count >= 2) {
                    NSString *userId = [components lastObject];
                    if ([userId isEqualToString:currentShortID]) {
                        shouldFilterUser = YES;
                        break;
                    }
                }
            }
        }
    }

    if (isRecommendFeed) {
        NSString *desc = DKXSModelSafeValue(self, @"descriptionString");
        if (keywordsList.count > 0 && desc.length > 0) {
            for (NSString *keyword in keywordsList) {
                NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmedKeyword.length > 0 && [desc containsString:trimmedKeyword]) {
                    shouldFilterKeywords = YES;
                    break;
                }
            }
        }
        id propGuide = DKXSModelSafeValue(self, @"propGuideV2");
        if (propKeywordsList.count > 0 && propGuide) {
            NSString *propName = DKXSModelSafeValue(propGuide, @"propName");
            if (propName.length > 0) {
                for (NSString *propKeyword in propKeywordsList) {
                    NSString *trimmedKeyword = [propKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedKeyword.length > 0 && [propName containsString:trimmedKeyword]) {
                        shouldFilterProp = YES;
                        break;
                    }
                }
            }
        }
    }

    if (disableHDR && ![self dkxs_shouldExcludeFromGlobalHDRFilter] &&
        DKXSAwemeModelHasOnlyHDRBitrateModels(self)) {
        shouldFilterHDR = YES;
    }

    if (filterHDR && ![self dkxs_shouldExcludeFromGlobalHDRFilter]) {
        id video = DKXSModelSafeValue(self, @"video");
        if (video) {
            id isSourceHDR = DKXSModelSafeValue(video, @"isSourceHDR");
            id hasFilterHDR = DKXSModelSafeValue(video, @"hasFilterHDR");
            if (([video respondsToSelector:@selector(isSourceHDR)] &&
                 [isSourceHDR respondsToSelector:@selector(integerValue)] && [isSourceHDR integerValue] > 0) ||
                ([video respondsToSelector:@selector(hasFilterHDR)] &&
                 [hasFilterHDR respondsToSelector:@selector(boolValue)] && [hasFilterHDR boolValue])) {
                shouldFilterHDR = YES;
            } else {
                NSArray *bitrateModels = DKXSModelSafeValue(video, @"bitrateModels");
                for (id bitrateModel in bitrateModels) {
                    @try {
                        NSNumber *hdrType = [bitrateModel valueForKey:@"hdrType"];
                        NSNumber *hdrBit = [bitrateModel valueForKey:@"hdrBit"];
                        if ((hdrType && [hdrType integerValue] > 0) ||
                            (!hdrType && hdrBit && [hdrBit integerValue] >= 10)) {
                            shouldFilterHDR = YES;
                            break;
                        }
                    } @catch (__unused NSException *exception) {
                    }
                }
            }
        }
    }

    return shouldFilterAllLive || shouldFilterHotSpot || shouldFilterFriendsVideo || shouldFilterMusic ||
           shouldFilterHDR || shouldFilterKeywords || shouldFilterProp || shouldFilterUser ||
           shouldskipPhoto || shouldskipPhotoText;
}

%end

// 播放器全局 HDR 开关：屏蔽档时直接关 HDR。
%hook AWEDPlayerFeedPlayerViewController
- (BOOL)enableHDR {
    if (DKXSShouldDisableAllHDR()) {
        return NO;
    }
    return %orig;
}
%end
