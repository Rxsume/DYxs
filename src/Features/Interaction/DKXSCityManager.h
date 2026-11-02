//
//  DKXSCityManager.h
//  DYxs 全量合并第 5 批剩余部分（5e）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 CityManager.h（属地码表 + Geonames 国外解析），
//  类名 CityManager -> DKXSCityManager；数据表原样保留。
//
#import <Foundation/Foundation.h>

@interface DKXSCityManager : NSObject

@property(nonatomic, strong) NSDictionary *cityCodeMap;
@property(nonatomic, strong) NSDictionary *countryCodeMap;

+ (instancetype)sharedInstance;
- (NSString *)getCityNameWithCode:(NSString *)code;
- (NSString *)getProvinceNameWithCode:(NSString *)code;
- (NSString *)getCountryNameWithCode:(NSString *)code;
- (void)loadCityData;
- (void)loadCountryData;
+ (void)fetchLocationWithGeonameId:(NSString *)geonameId completionHandler:(void (^)(NSDictionary *locationInfo, NSError *error))completionHandler;
@end
