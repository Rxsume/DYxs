//
//  DKXSHDRHelpers.h
//  DYxs 全量合并第 5 批剩余部分（5c）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 1186-1634 行 HDR 工具函数区，符号一律
//  DYYY* -> DKXS*；上游的 HDR 模式迁移函数（读旧版 DYYYDisableAllHDR /
//  DYYYFilterFeedHDR 布尔键）已删除，DYxs 只读 DKXSHDRMode 一个字符串键。
//  本文件只含 static 函数，供 DKXSBatch5cModelFilter.xm 一个编译单元 import，
//  不要被第二个 .xm import（static 会各自展开一份，无害但无必要）。
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kDKXSHDRModeKey = @"DKXSHDRMode";
static NSString *const kDKXSHDRModeOff = @"关闭";
static NSString *const kDKXSHDRModeDisable = @"全局屏蔽HDR效果";
static NSString *const kDKXSHDRModeFilter = @"全局过滤HDR作品";
static char kDKXSHDRStrippedAwemeModelKey;
static char kDKXSHDRStrippedVideoModelKey;
static char kDKXSHDROnlyAwemeModelKey;
static char kDKXSHDROnlyVideoModelKey;

// DKXSHDRMode 的存法双兼容：上游 picker 存中文字符串（关闭 / 全局屏蔽HDR效果 /
// 全局过滤HDR作品），DYxs 的 DKMakeChoice 存下标（0 / 1 / 2，顺序与字符串表一致）。
// 两边都认，避免登记方式一改就导致整档 HDR 失效。
static NSInteger DKXSHDRModeValue(void) {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kDKXSHDRModeKey];
    if ([raw isKindOfClass:[NSNumber class]]) {
        return [raw integerValue];
    }
    if ([raw isKindOfClass:[NSString class]]) {
        if ([raw isEqualToString:kDKXSHDRModeDisable]) return 1;
        if ([raw isEqualToString:kDKXSHDRModeFilter]) return 2;
    }
    return 0;
}

static BOOL DKXSShouldDisableAllHDR(void) {
    return DKXSHDRModeValue() == 1;
}

static BOOL DKXSShouldFilterGlobalHDR(void) {
    return DKXSHDRModeValue() == 2;
}

static id DKXSKVCValueIfPossible(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void DKXSSetKVCValueIfPossible(id object, NSString *key, id value) {
    if (!object || key.length == 0) {
        return;
    }

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static id DKXSIvarValueIfPossible(id object, const char *ivarName) {
    if (!object || !ivarName) {
        return nil;
    }

    Class cls = object_getClass(object);
    while (cls) {
        Ivar ivar = class_getInstanceVariable(cls, ivarName);
        if (ivar) {
            return object_getIvar(object, ivar);
        }
        cls = class_getSuperclass(cls);
    }

    return nil;
}

static id DKXSValuePreferringIvar(id object, const char *ivarName, NSString *key) {
    id ivarValue = DKXSIvarValueIfPossible(object, ivarName);
    if (ivarValue) {
        return ivarValue;
    }
    return DKXSKVCValueIfPossible(object, key);
}

static NSInteger DKXSIntegerValueForKeyIfPossible(id object, NSString *key, NSInteger fallback) {
    id value = DKXSKVCValueIfPossible(object, key);
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

static BOOL DKXSStringValueLooksHDR(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *lowercaseValue = [(NSString *)value lowercaseString];
    return [lowercaseValue containsString:@"hdr"] ||
           [lowercaseValue containsString:@"hlg"] ||
           [lowercaseValue containsString:@"dolby"] ||
           [lowercaseValue containsString:@"vivid"] ||
           [lowercaseValue isEqualToString:@"pq"] ||
           [lowercaseValue containsString:@"_pq"] ||
           [lowercaseValue containsString:@"pq_"];
}

static BOOL DKXSRawBitrateDictionaryLooksHDR(NSDictionary *dictionary);

static BOOL DKXSBitrateModelLooksHDR(id bitrateModel) {
    if (!bitrateModel) {
        return NO;
    }

    if ([bitrateModel isKindOfClass:[NSDictionary class]]) {
        return DKXSRawBitrateDictionaryLooksHDR((NSDictionary *)bitrateModel);
    }

    id hdrTypeValue = DKXSKVCValueIfPossible(bitrateModel, @"hdrType");
    id hdrBitValue = DKXSKVCValueIfPossible(bitrateModel, @"hdrBit");
    NSInteger hdrType = DKXSIntegerValueForKeyIfPossible(bitrateModel, @"hdrType", 0);
    NSInteger hdrBit = DKXSIntegerValueForKeyIfPossible(bitrateModel, @"hdrBit", 0);
    BOOL hasHdrType = DKXSIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrType", 0) > 0;
    BOOL hasHdrBit = DKXSIntegerValueForKeyIfPossible(bitrateModel, @"hasHdrBit", 0) > 0;

    return hdrType > 0 ||
           hdrBit >= 10 ||
           hasHdrType ||
           hasHdrBit ||
           DKXSStringValueLooksHDR(hdrTypeValue) ||
           DKXSStringValueLooksHDR(hdrBitValue);
}

static BOOL DKXSStringKeyLooksVideoBitrateList(NSString *key) {
    NSString *lowercaseKey = key.lowercaseString;
    if (lowercaseKey.length == 0 || [lowercaseKey containsString:@"audio"]) {
        return NO;
    }

    return [lowercaseKey containsString:@"bit_rate"] ||
           [lowercaseKey containsString:@"bitrate"] ||
           [lowercaseKey containsString:@"bit_rate_model"] ||
           [lowercaseKey containsString:@"bitratemodel"];
}

static BOOL DKXSRawBitrateDictionaryLooksHDR(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    for (id rawKey in dictionary) {
        id value = dictionary[rawKey];
        NSString *key = [[rawKey description] lowercaseString];
        NSInteger numericValue = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;

        if (([key isEqualToString:@"hdr_type"] ||
             [key isEqualToString:@"hdrtype"] ||
             [key isEqualToString:@"videohdrtype"] ||
             [key isEqualToString:@"video_hdr_type"] ||
             [key isEqualToString:@"source_hdr_type"]) && numericValue > 0) {
            return YES;
        }

        if (([key isEqualToString:@"hdr_bit"] ||
             [key isEqualToString:@"hdrbit"] ||
             [key isEqualToString:@"bit_depth"] ||
             [key isEqualToString:@"bitdepth"]) && numericValue >= 10) {
            return YES;
        }

        if (([key isEqualToString:@"is_source_hdr"] ||
             [key isEqualToString:@"source_hdr"] ||
             [key isEqualToString:@"is_hdr"] ||
             [key isEqualToString:@"ishdr"] ||
             [key isEqualToString:@"has_hdr"] ||
             [key isEqualToString:@"hashdr"] ||
             [key isEqualToString:@"has_filter_hdr"] ||
             [key isEqualToString:@"filter_hdr"] ||
             [key isEqualToString:@"has_hdr_type"] ||
             [key isEqualToString:@"hashdrtype"] ||
             [key isEqualToString:@"has_hdr_bit"] ||
             [key isEqualToString:@"hashdrbit"]) && numericValue > 0) {
            return YES;
        }

        if (DKXSStringValueLooksHDR(value)) {
            return YES;
        }
    }

    return NO;
}

static void DKXSCollectRawBitrateHDRStatus(id object, NSUInteger depth, BOOL *foundHDRBitrate, BOOL *foundSDRBitrate) {
    if (!object || depth > 8 || (foundSDRBitrate && *foundSDRBitrate)) {
        return;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id rawKey in dictionary) {
            id value = dictionary[rawKey];
            NSString *key = [rawKey description];

            if (DKXSStringKeyLooksVideoBitrateList(key) && [value isKindOfClass:[NSArray class]]) {
                for (id entry in (NSArray *)value) {
                    if (![entry isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }

                    if (DKXSRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
                        if (foundHDRBitrate) {
                            *foundHDRBitrate = YES;
                        }
                    } else if (foundSDRBitrate) {
                        *foundSDRBitrate = YES;
                        return;
                    }
                }
                continue;
            }

            if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                DKXSCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            DKXSCollectRawBitrateHDRStatus(value, depth + 1, foundHDRBitrate, foundSDRBitrate);
        }
    }
}

static BOOL DKXSRawObjectHasOnlyHDRBitrateModels(id object) {
    BOOL foundHDRBitrate = NO;
    BOOL foundSDRBitrate = NO;
    DKXSCollectRawBitrateHDRStatus(object, 0, &foundHDRBitrate, &foundSDRBitrate);
    return foundHDRBitrate && !foundSDRBitrate;
}

static BOOL DKXSVideoModelHasOnlyHDRBitrateModels(id video) {
    if (!video) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(video, &kDKXSHDROnlyVideoModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    NSMutableArray *models = [NSMutableArray array];
    NSArray *bitrateModels = DKXSValuePreferringIvar(video, "_bitrateModels", @"bitrateModels");
    if ([bitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateModels];
    }

    NSArray *manualBitrateModels = DKXSValuePreferringIvar(video, "_manualBitrateModels", @"manualBitrateModels");
    if ([manualBitrateModels isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:manualBitrateModels];
    }

    NSArray *bitrateRawData = DKXSValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    if ([bitrateRawData isKindOfClass:[NSArray class]]) {
        [models addObjectsFromArray:bitrateRawData];
    }

    if (models.count == 0) {
        return NO;
    }

    BOOL onlyHDR = YES;
    for (id model in models) {
        if (!DKXSBitrateModelLooksHDR(model)) {
            onlyHDR = NO;
            break;
        }
    }

    objc_setAssociatedObject(video, &kDKXSHDROnlyVideoModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return onlyHDR;
}

static BOOL DKXSAwemeModelHasOnlyHDRBitrateModels(id aweme) {
    if (!aweme) {
        return NO;
    }

    NSNumber *cachedResult = objc_getAssociatedObject(aweme, &kDKXSHDROnlyAwemeModelKey);
    if (cachedResult) {
        return cachedResult.boolValue;
    }

    BOOL onlyHDR = NO;
    BOOL shouldCacheResult = NO;
    id video = DKXSValuePreferringIvar(aweme, "_video", @"video");
    if (video) {
        shouldCacheResult = YES;
    }
    if (DKXSVideoModelHasOnlyHDRBitrateModels(video)) {
        onlyHDR = YES;
    } else {
        NSArray *albumImages = DKXSValuePreferringIvar(aweme, "_albumImages", @"albumImages");
        if ([albumImages isKindOfClass:[NSArray class]]) {
            shouldCacheResult = shouldCacheResult || albumImages.count > 0;
            for (id imageModel in albumImages) {
                id clipVideo = DKXSValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo");
                if (DKXSVideoModelHasOnlyHDRBitrateModels(clipVideo)) {
                    onlyHDR = YES;
                    break;
                }
            }
        }
    }

    if (shouldCacheResult || onlyHDR) {
        objc_setAssociatedObject(aweme, &kDKXSHDROnlyAwemeModelKey, @(onlyHDR), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return onlyHDR;
}

static NSArray *DKXSFilteredSDRRawBitrateData(NSArray *rawData) {
    if (![rawData isKindOfClass:[NSArray class]] || rawData.count == 0) {
        return rawData;
    }

    NSMutableArray *sdrData = [NSMutableArray arrayWithCapacity:rawData.count];
    NSUInteger hdrCount = 0;
    for (id entry in rawData) {
        if ([entry isKindOfClass:[NSDictionary class]] && DKXSRawBitrateDictionaryLooksHDR((NSDictionary *)entry)) {
            hdrCount++;
            continue;
        }
        [sdrData addObject:entry];
    }

    if (hdrCount == 0 || sdrData.count == 0) {
        return rawData;
    }

    return [sdrData copy];
}

static NSArray *DKXSFilteredSDRBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]] || models.count == 0) {
        return models;
    }

    NSMutableArray *sdrModels = [NSMutableArray arrayWithCapacity:models.count];
    NSUInteger hdrCount = 0;
    for (id model in models) {
        if (DKXSBitrateModelLooksHDR(model)) {
            hdrCount++;
            continue;
        }
        [sdrModels addObject:model];
    }

    // 只有 HDR 档的作品在模型层过滤；这里不清空列表，避免播放器拿不到可播档导致有声黑屏。
    if (hdrCount == 0 || sdrModels.count == 0) {
        return models;
    }

    return [sdrModels copy];
}

static void DKXSStripHDRHintsFromBitrateModels(NSArray *models) {
    if (![models isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id model in models) {
        DKXSSetKVCValueIfPossible(model, @"hdrType", @0);
        DKXSSetKVCValueIfPossible(model, @"hdrBit", @8);
        DKXSSetKVCValueIfPossible(model, @"hasHdrType", @NO);
        DKXSSetKVCValueIfPossible(model, @"hasHdrBit", @NO);
    }
}

static void DKXSStripHDRHintsFromVideoModel(id video) {
    if (!DKXSShouldDisableAllHDR() || !video) {
        return;
    }

    if (objc_getAssociatedObject(video, &kDKXSHDRStrippedVideoModelKey)) {
        return;
    }
    objc_setAssociatedObject(video, &kDKXSHDRStrippedVideoModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([video respondsToSelector:@selector(setIsSourceHDR:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(video, @selector(setIsSourceHDR:), 0);
    }
    if ([video respondsToSelector:@selector(setHasFilterHDR:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(video, @selector(setHasFilterHDR:), NO);
    }

    NSArray *bitrateModels = DKXSKVCValueIfPossible(video, @"bitrateModels");
    NSArray *filteredBitrateModels = DKXSFilteredSDRBitrateModels(bitrateModels);
    if (filteredBitrateModels && filteredBitrateModels != bitrateModels) {
        DKXSSetKVCValueIfPossible(video, @"bitrateModels", filteredBitrateModels);
        bitrateModels = filteredBitrateModels;
    }
    DKXSStripHDRHintsFromBitrateModels(bitrateModels);

    NSArray *manualBitrateModels = DKXSKVCValueIfPossible(video, @"manualBitrateModels");
    NSArray *filteredManualBitrateModels = DKXSFilteredSDRBitrateModels(manualBitrateModels);
    if (filteredManualBitrateModels && filteredManualBitrateModels != manualBitrateModels) {
        DKXSSetKVCValueIfPossible(video, @"manualBitrateModels", filteredManualBitrateModels);
        manualBitrateModels = filteredManualBitrateModels;
    }
    DKXSStripHDRHintsFromBitrateModels(manualBitrateModels);

    NSArray *bitrateRawData = DKXSValuePreferringIvar(video, "_bitrateRawData", @"bitrateRawData");
    NSArray *filteredBitrateRawData = DKXSFilteredSDRRawBitrateData(bitrateRawData);
    if (filteredBitrateRawData && filteredBitrateRawData != bitrateRawData) {
        DKXSSetKVCValueIfPossible(video, @"bitrateRawData", filteredBitrateRawData);
    }
}

static void DKXSStripHDRHintsFromAwemeModel(id aweme) {
    if (!DKXSShouldDisableAllHDR() || !aweme) {
        return;
    }

    if (objc_getAssociatedObject(aweme, &kDKXSHDRStrippedAwemeModelKey)) {
        return;
    }
    objc_setAssociatedObject(aweme, &kDKXSHDRStrippedAwemeModelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id video = DKXSValuePreferringIvar(aweme, "_video", @"video");
    DKXSStripHDRHintsFromVideoModel(video);

    NSArray *albumImages = DKXSValuePreferringIvar(aweme, "_albumImages", @"albumImages");
    if ([albumImages isKindOfClass:[NSArray class]]) {
        for (id imageModel in albumImages) {
            DKXSStripHDRHintsFromVideoModel(DKXSValuePreferringIvar(imageModel, "_clipVideo", @"clipVideo"));
        }
    }
}

