//
//  DKXSBatch5eQuality.xm
//  DYxs 全量合并第 5 批剩余部分（5e）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 1024-1118 行（AWEVideoModel 的
//  playURL 与 bitrateModels），符号一律 DYYY* -> DKXS*。
//  HDR 工具函数来自本批的 DKXSHDRHelpers.h（须同批上传）。
//  DYxs 现有代码未 hook AWEVideoModel 的这两个方法，无撞点；
//  注意 5c 模型文件 hook 的是 AWEAwemeModel（不同类），不冲突。
//
//  上游原样：开“提高视频画质”时，bitrateModels 直接返回只含最高比特率
//  模型的单元素数组（不是排序）；playURL 则返回该模型的 playAddr。
//  两处都只认 AWEVideoBSModel 的 bitrate 字段，其他模型类型跳过。
//
#import <UIKit/UIKit.h>
#import "DKXSHDRHelpers.h"

%hook AWEVideoModel

- (id)playURL {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableVideoHighestQuality"]) {
        return %orig;
    }
    NSArray *bitrateModels = [self bitrateModels];
    if (!bitrateModels || bitrateModels.count == 0) {
        return %orig;
    }
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;
    for (id model in bitrateModels) {
        NSInteger bitrate = 0;
        BOOL validModel = NO;
        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = nil;
            @try {
                bitrateValue = [model bitrate];
            } @catch (__unused NSException *exception) {
            }
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }
        if (validModel && bitrate > highestBitrate) {
            highestBitrate = bitrate;
            highestBitrateModel = model;
        }
    }
    if (highestBitrateModel) {
        id playAddr = nil;
        @try {
            playAddr = [highestBitrateModel valueForKey:@"playAddr"];
        } @catch (__unused NSException *exception) {
        }
        if (playAddr && [playAddr isKindOfClass:NSClassFromString(@"AWEURLModel")]) {
            return playAddr;
        }
    }
    return %orig;
}

- (NSArray *)bitrateModels {
    NSArray *originalModels = %orig;
    if (DKXSShouldDisableAllHDR()) {
        NSArray *filteredModels = DKXSFilteredSDRBitrateModels(originalModels);
        DKXSStripHDRHintsFromBitrateModels(filteredModels);
        originalModels = filteredModels;
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableVideoHighestQuality"]) {
        return originalModels;
    }
    if (originalModels.count == 0) {
        return originalModels;
    }
    id highestBitrateModel = nil;
    NSInteger highestBitrate = 0;
    for (id model in originalModels) {
        NSInteger bitrate = 0;
        BOOL validModel = NO;
        if ([model isKindOfClass:NSClassFromString(@"AWEVideoBSModel")]) {
            id bitrateValue = nil;
            @try {
                bitrateValue = [model bitrate];
            } @catch (__unused NSException *exception) {
            }
            if (bitrateValue) {
                bitrate = [bitrateValue integerValue];
                validModel = YES;
            }
        }
        if (validModel) {
            if (bitrate > highestBitrate) {
                highestBitrate = bitrate;
                highestBitrateModel = model;
            }
        }
    }
    if (highestBitrateModel) {
        return @[ highestBitrateModel ];
    }
    return originalModels;
}

- (void)setBitrateModels:(NSArray *)bitrateModels {
    if (DKXSShouldDisableAllHDR()) {
        NSArray *filteredModels = DKXSFilteredSDRBitrateModels(bitrateModels);
        DKXSStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (void)setManualBitrateModels:(NSArray *)manualBitrateModels {
    if (DKXSShouldDisableAllHDR()) {
        NSArray *filteredModels = DKXSFilteredSDRBitrateModels(manualBitrateModels);
        DKXSStripHDRHintsFromBitrateModels(filteredModels);
        %orig(filteredModels);
        return;
    }
    %orig;
}

- (NSArray *)manualBitrateModels {
    NSArray *models = %orig;
    if (DKXSShouldDisableAllHDR()) {
        models = DKXSFilteredSDRBitrateModels(models);
        DKXSStripHDRHintsFromBitrateModels(models);
    }
    return models;
}

%end
