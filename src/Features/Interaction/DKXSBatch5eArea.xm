//
//  DKXSBatch5eArea.xm
//  DYxs 全量合并第 5 批剩余部分（5e）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 第 3599-3785 行（AWEPlayInteractionTimestampElement
//  的 timestampLabel）+ CityManager（本批 DKXSCityManager.h/.m），
//  符号一律 DYYY* -> DKXS*。DYxs 现有代码未 hook 该类，无撞点。
//
//  与上游的差异（主 agent 复核必读）：
//  1. 颜色：上游 DYYYUtils applyColorSettingsToLabel 是整套 scheme 引擎
//     （渐变、描边、阴影、缓存），本文件只做最小版：十六进制填纯色；
//     DKXSEnableRandomGradient 开时取随机色相纯色（上游是随机渐变，
//     不是纯色）；不填时白色。不要拿渐变效果当验收用例。
//  2. 上游同 hook 里的 DYYYBoldTimestamp（时间加粗）未登记、未移植，
//     不属于 5e 清单；如需加粗可另起一键。
//  3. model / cityCode / region 一律 valueForKey + respondsToSelector 取，
//     不 import DouyinHeaders；40.8.0 若改了字段名，属地会退到“未知地区”。
//  4. 国外解析走 Geonames（secure.geonames.org），需要用户填
//     DKXSGeonamesUsername；不填时国外码只走本地国家码表 fallback。
//  5. 属地上移：上游用 DYYYNicknameScale 是否填写来门控（填了才应用
//     DKXSIPLabelVerticalOffset，缺省 -3）；本文件原样保留该门控关系，
//     不要把它改成独立开关。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DKXSCityManager.h"

static UIColor *DKXSAreaColorFromHex(NSString *hex) {
    if (!hex || hex.length == 0) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length == 3) {
        unichar r = [s characterAtIndex:0], g = [s characterAtIndex:1], b = [s characterAtIndex:2];
        s = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    } else if (s.length == 8) {
        s = [s substringFromIndex:2];
    }
    if (s.length != 6) return nil;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

static id DKXSAreaSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

%hook AWEPlayInteractionTimestampElement

- (id)timestampLabel {
    UILabel *label = %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableArea"]) {
        return label;
    }

    NSString *labelColorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSLabelColor"];
    BOOL randomGradient = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableRandomGradient"];
    UIColor *labelColor = nil;
    if (randomGradient) {
        labelColor = [UIColor colorWithHue:(arc4random_uniform(256) / 255.0) saturation:0.8 brightness:0.9 alpha:1.0];
    } else {
        labelColor = DKXSAreaColorFromHex(labelColorHex) ?: [UIColor whiteColor];
    }

    id model = DKXSAreaSafeValue(self, @"model");
    NSString *cityCode = DKXSAreaSafeValue(model, @"cityCode");
    NSString *regionCode = nil;
    if ([model respondsToSelector:@selector(region)]) {
        regionCode = DKXSAreaSafeValue(model, @"region");
    }
    if (cityCode && ([cityCode isEqualToString:@"0"] || [cityCode integerValue] == 0)) {
        cityCode = nil;
    }

    static NSCache *locationCache;
    static NSMutableSet *inFlight;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locationCache = [[NSCache alloc] init];
        locationCache.countLimit = 100;
        inFlight = [[NSMutableSet alloc] init];
    });

    void (^updateLabelWithLocation)(UILabel *, NSString *) = ^(UILabel *lbl, NSString *location) {
        if (location.length == 0) return;
        NSString *currentText = lbl.text ?: @"";
        if ([currentText containsString:location]) return;
        if ([currentText containsString:@"IP属地："]) {
            NSRange range = [currentText rangeOfString:@"IP属地："];
            NSString *baseText = [currentText substringToIndex:range.location];
            lbl.text = [NSString stringWithFormat:@"%@IP属地：%@", baseText, location];
        } else if (currentText.length > 0) {
            lbl.text = [NSString stringWithFormat:@"%@  IP属地：%@", currentText, location];
        }
        lbl.textColor = labelColor;
    };

    void (^applyIPOffset)(UILabel *) = ^(UILabel *lbl) {
        NSString *ipScaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSNicknameScale"];
        if (ipScaleValue.length > 0) {
            CGFloat offset = [[NSUserDefaults standardUserDefaults] floatForKey:@"DKXSIPLabelVerticalOffset"];
            if (offset > 0) {
                lbl.transform = CGAffineTransformMakeTranslation(0, -offset);
            } else {
                lbl.transform = CGAffineTransformMakeTranslation(0, -3);
            }
        }
    };

    if (cityCode.length == 0 && regionCode.length == 0) {
        updateLabelWithLocation(label, @"未知地区");
        return label;
    }

    NSString *cacheKey = cityCode.length > 0 ? cityCode : regionCode;
    NSString *cachedLocation = [locationCache objectForKey:cacheKey];
    if (cachedLocation) {
        updateLabelWithLocation(label, cachedLocation);
        applyIPOffset(label);
        return label;
    }

    NSString *displayLocation = nil;
    if (cityCode.length > 0) {
        displayLocation = [[DKXSCityManager sharedInstance] getCityNameWithCode:cityCode];
        if (!displayLocation) {
            @synchronized(inFlight) {
                if ([inFlight containsObject:cityCode]) {
                    return label;
                }
                [inFlight addObject:cityCode];
            }
            [DKXSCityManager fetchLocationWithGeonameId:cityCode completionHandler:^(NSDictionary *locationInfo, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized(inFlight) {
                        [inFlight removeObject:cityCode];
                    }
                    NSString *apiLocation = nil;
                    NSString *localName = locationInfo[@"name"];
                    NSString *adminName1 = locationInfo[@"adminName1"];
                    NSString *countryName = locationInfo[@"countryName"];
                    if (![localName isKindOfClass:[NSString class]]) localName = nil;
                    if (![adminName1 isKindOfClass:[NSString class]]) adminName1 = nil;
                    if (![countryName isKindOfClass:[NSString class]]) countryName = nil;
                    if (countryName.length > 0) {
                        if (adminName1.length > 0 && localName.length > 0 && ![countryName isEqualToString:localName]) {
                            if ([adminName1 isEqualToString:localName]) {
                                apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                            } else {
                                apiLocation = [NSString stringWithFormat:@"%@ %@ %@", countryName, adminName1, localName];
                            }
                        } else if (localName.length > 0 && ![countryName isEqualToString:localName]) {
                            apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, localName];
                        } else if (adminName1.length > 0 && ![countryName isEqualToString:adminName1]) {
                            apiLocation = [NSString stringWithFormat:@"%@ %@", countryName, adminName1];
                        } else {
                            apiLocation = countryName;
                        }
                    } else if (localName.length > 0) {
                        apiLocation = localName;
                    } else if (adminName1.length > 0) {
                        apiLocation = adminName1;
                    }
                    if (apiLocation.length > 0) {
                        [locationCache setObject:apiLocation forKey:cacheKey];
                        updateLabelWithLocation(label, apiLocation);
                    } else if (regionCode.length > 0) {
                        NSString *fallbackCountry = [[DKXSCityManager sharedInstance] getCountryNameWithCode:regionCode];
                        updateLabelWithLocation(label, fallbackCountry);
                    }
                });
            }];
            return label;
        }
    }

    if (!displayLocation && !cityCode && regionCode.length > 0) {
        displayLocation = [[DKXSCityManager sharedInstance] getCountryNameWithCode:regionCode];
    }
    if (!displayLocation) {
        displayLocation = @"未知地区";
        updateLabelWithLocation(label, displayLocation);
        return label;
    }
    [locationCache setObject:displayLocation forKey:cacheKey];
    updateLabelWithLocation(label, displayLocation);
    applyIPOffset(label);
    return label;
}

+ (BOOL)shouldActiveWithData:(id)arg1 context:(id)arg2 {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableArea"];
}

%end
