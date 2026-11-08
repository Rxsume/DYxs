#import "DKXSABTestHook.h"
#import "DKXSABTestOverridePolicy.h"
#import "DKXSConstants.h"
#import "DKXSUtils.h"
// 必须声明 AWEABTestManager 的完整接口（sharedManager / abTestData / setAbTestData），
// 否则 Logos 的 %hook 只生成 @class 前置声明，编译器会把所有对 manager 的调用报成
// “forward declaration”错误（build #37 的 8 个错误）。本文件不 import DouyinHeaders，
// 与 DKXSAwemeHeaders 无重复声明冲突。
#import "DKXSAwemeHeaders.h"
#import <objc/runtime.h>

static BOOL s_abTestBlockEnabled = NO;
static BOOL s_isApplyingFixedData = NO;
static NSDictionary *s_localABTestData = nil;
// 仅保存原生设置回调提供的布局项；本插件合成后的数据不作为原生来源。
static NSDictionary *s_nativeLayoutABTestData = nil;
static NSString *s_fileMode = nil;

// 默认远程配置地址常量
static NSString *const kDefaultRemoteConfigURL = DKXS_DEFAULT_ABTEST_URL;
static NSString *const kDKXSTabBarHeightKey = @"DKXSTabBarHeight";
static NSString *const kDKXSABTestTabBarHeightConfigKey = @"hp_tab_bar_custom_height_config";

static dispatch_once_t s_loadOnceToken;
static dispatch_queue_t s_abTestHookQueue;
static dispatch_once_t s_queueOnceToken;
static void *s_queueSpecificKey = &s_queueSpecificKey;

static dispatch_queue_t DKXSABTestQueue() {
    dispatch_once(&s_queueOnceToken, ^{
      if (!s_abTestHookQueue) {
          s_abTestHookQueue = dispatch_queue_create("com.dyyy.abtesthook.queue", DISPATCH_QUEUE_SERIAL);
          // Mark the queue with specific key for reentrancy checks
          dispatch_queue_set_specific(s_abTestHookQueue, s_queueSpecificKey, (void *)1, NULL);
      }
    });
    return s_abTestHookQueue;
}

static void DKXSQueueSync(dispatch_block_t block) {
    dispatch_queue_t queue = DKXSABTestQueue();
    if (dispatch_get_specific(s_queueSpecificKey)) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
}

static NSNumber *DKXSResolveTabBarHeightFromSettings(void) {
    NSString *heightString = [[NSUserDefaults standardUserDefaults] stringForKey:kDKXSTabBarHeightKey];
    if (heightString.length == 0) {
        return nil;
    }

    float parsedValue = 0.0f;
    NSScanner *scanner = [NSScanner scannerWithString:heightString];
    if (![scanner scanFloat:&parsedValue] || !scanner.isAtEnd || parsedValue <= 0.0f) {
        return nil;
    }
    return @(parsedValue);
}

static NSDictionary *DKXSBuildTabBarHeightConfig(NSDictionary *existingConfig, NSNumber *contentHeight) {
    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    if ([existingConfig isKindOfClass:[NSDictionary class]]) {
        [config addEntriesFromDictionary:existingConfig];
    }

    config[@"content_height"] = contentHeight;
    if (!config[@"custom_safe_area_bottom_offet"]) {
        config[@"custom_safe_area_bottom_offet"] = @0;
    }
    if (!config[@"custom_safe_area_bottom_offset_black_set"]) {
        config[@"custom_safe_area_bottom_offset_black_set"] = @[];
    }
    if (!config[@"custom_tab_bar_height_black_set"]) {
        config[@"custom_tab_bar_height_black_set"] = @[];
    }
    if (!config[@"enabled"]) {
        config[@"enabled"] = @YES;
    }
    if (!config[@"overlap_height"]) {
        config[@"overlap_height"] = @14;
    }

    return [config copy];
}

static NSDictionary *DKXSInjectTabBarHeightConfig(NSDictionary *sourceData, NSNumber *contentHeight) {
    if (!contentHeight) {
        return sourceData;
    }

    NSMutableDictionary *patchedData = [NSMutableDictionary dictionaryWithDictionary:sourceData ?: @{}];
    NSDictionary *existingConfig = nil;
    id existingConfigValue = patchedData[kDKXSABTestTabBarHeightConfigKey];
    if ([existingConfigValue isKindOfClass:[NSDictionary class]]) {
        existingConfig = (NSDictionary *)existingConfigValue;
    }
    patchedData[kDKXSABTestTabBarHeightConfigKey] = DKXSBuildTabBarHeightConfig(existingConfig, contentHeight);

    return [patchedData copy];
}

static void DKXSApplyTabBarHeightToCurrentABTestDataIfNeeded(void) {
    NSNumber *contentHeight = DKXSResolveTabBarHeightFromSettings();
    if (!contentHeight) {
        return;
    }

    AWEABTestManager *manager = [%c(AWEABTestManager) sharedManager];
    if (!manager) {
        return;
    }

    NSDictionary *currentData = [manager abTestData];
    if (currentData && ![currentData isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSDictionary *patchedData = DKXSInjectTabBarHeightConfig(currentData ?: @{}, contentHeight);
    if (currentData && [currentData isEqualToDictionary:patchedData]) {
        return;
    }

    s_isApplyingFixedData = YES;
    [manager setAbTestData:patchedData];
    s_isApplyingFixedData = NO;
    NSLog(@"[DKXS] 已通过 ABTest 注入底栏高度: %@", contentHeight);
}

@implementation DKXSABTestHook

/**
 * 判断当前是否为覆写模式
 * 通过DKXSABTestModeString判断，返回YES表示覆写模式，NO表示替换模式
 * 转换为类方法
 */
+ (BOOL)isPatchMode {
    NSString *savedMode = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSABTestModeString"];
    if (savedMode) {
        if ([savedMode isEqualToString:DKXS_REMOTE_MODE_STRING] || [[savedMode lowercaseString] isEqualToString:@"remote"]) {
            if (s_fileMode) {
                return ![[s_fileMode lowercaseString] isEqualToString:@"DKXS_MODE_REPLACE"];
            }
            return YES;
        }
        if ([savedMode isEqualToString:@"替换模式：忽略原配置，使用新数据"] || [[savedMode lowercaseString] isEqualToString:@"DKXS_MODE_REPLACE"]) {
            return NO;
        }
        return YES;
    }
    if (s_fileMode) {
        return ![[s_fileMode lowercaseString] isEqualToString:@"DKXS_MODE_REPLACE"];
    }
    return YES;
}

/**
 * 获取本地文件是否已加载的状态
 * 使用 dispatch_sync 在队列上同步读取 s_localABTestData 的状态
 */
+ (BOOL)isLocalConfigLoaded {
    __block BOOL loaded = NO;
    DKXSQueueSync(^{
      loaded = (s_localABTestData != nil);
    });
    return loaded;
}

/**
 * 当前是否处于远程模式
 */
+ (BOOL)isRemoteMode {
    NSString *savedMode = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSABTestModeString"];
    if (savedMode) {
        return [savedMode isEqualToString:DKXS_REMOTE_MODE_STRING] || [[savedMode lowercaseString] isEqualToString:@"remote"];
    }
    return NO;
}

/**
 * 获取禁止下发配置的状态
 * 使用 dispatch_sync 在队列上同步读取状态
 */
+ (BOOL)isABTestBlockEnabled {
    __block BOOL enabled = NO;
    DKXSQueueSync(^{
      enabled = s_abTestBlockEnabled;
    });
    return enabled;
}

/**
 * 设置禁止下发配置的状态
 * 使用 dispatch_async 在队列上异步设置状态
 */
+ (void)setABTestBlockEnabled:(BOOL)enabled {
    dispatch_async(DKXSABTestQueue(), ^{
      s_abTestBlockEnabled = enabled;
    });
}

/**
 * 清除本地加载的ABTest数据，为下次调用 loadLocalABTestConfig 做准备
 * 使用 dispatch_async 在队列上异步清除数据
 */
+ (void)cleanLocalABTestData {
    dispatch_async(DKXSABTestQueue(), ^{
      s_localABTestData = nil;
      s_loadOnceToken = 0;
      NSLog(@"[DKXS] 本地ABTest配置已清除");
    });
}

/**
 * 加载本地ABTest配置文件
 * 只加载文件和处理数据，不负责应用
 * 使用 dispatch_once 确保只加载一次
 * 整个加载过程在队列上异步执行
 */
+ (void)loadLocalABTestConfig {
    dispatch_async(DKXSABTestQueue(), ^{
      dispatch_once(&s_loadOnceToken, ^{
        // 获取存储路径
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DKXS"];
        NSString *jsonFilePath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

        // 确保目录存在
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:dyyyFolderPath]) {
            NSError *error = nil;
            [fileManager createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"[DKXS] 创建DKXS目录失败: %@", error.localizedDescription);
            }
        }

        // 读取本地配置文件
        NSError *error = nil;
        NSData *jsonData = [NSData dataWithContentsOfFile:jsonFilePath options:0 error:&error];

        if (jsonData) {
            NSDictionary *loadedData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            if (loadedData && !error) {
                id modeValue = loadedData[@"mode"];
                s_fileMode = nil;
                if ([modeValue isKindOfClass:[NSString class]]) {
                    s_fileMode = [modeValue lowercaseString];
                }
                NSDictionary *actualData = loadedData[@"data"];
                if (!actualData) {
                    NSMutableDictionary *tmp = [loadedData mutableCopy];
                    [tmp removeObjectForKey:@"mode"];
                    actualData = [tmp copy];
                }
                s_localABTestData = [actualData copy];
                NSLog(@"[DKXS] ABTest本地配置已从文件加载成功");
                return;
            } else {
                NSLog(@"[DKXS] ABTest本地配置解析失败: %@", error.localizedDescription);
            }
        } else {
            NSLog(@"[DKXS] ABTest本地配置文件不存在或无法读取");
        }

        // 加载失败时的处理
        s_localABTestData = nil;
      });
    });
}

/**
 * 应用本地ABTest配置数据 (负责根据模式处理并应用到 Manager)
 * 包含是否应该应用的条件判断
 * 整个应用过程在队列上异步执行
 */
+ (void)applyFixedABTestData {
    dispatch_async(DKXSABTestQueue(), ^{
      if (!s_abTestBlockEnabled || !s_localABTestData) {
          NSLog(@"[DKXS] 不满足应用本地配置的条件 (禁止下发=%@, 数据是否为空=%@)", s_abTestBlockEnabled ? @"开启" : @"关闭", s_localABTestData ? @"否" : @"是");
          s_isApplyingFixedData = NO; // 确保标志关闭
          return;
      }

      AWEABTestManager *manager = [%c(AWEABTestManager) sharedManager];
      if (!manager) {
          NSLog(@"[DKXS] 无法应用本地配置：AWEABTestManager 实例不可用");
          s_isApplyingFixedData = NO; // 确保标志关闭
          return;
      }

      BOOL usingPatchMode = [self isPatchMode];
      // 首页单双列相关项沿用抖音当前配置；本地或远程增强文件均不再覆盖。
      NSDictionary *dataToApply = [DKXSABTestOverridePolicy configurationForNative:[manager abTestData]
          originalLayout:s_nativeLayoutABTestData overrides:s_localABTestData patchMode:usingPatchMode];

      NSNumber *contentHeight = DKXSResolveTabBarHeightFromSettings();
      if (contentHeight) {
          dataToApply = DKXSInjectTabBarHeightConfig(dataToApply ?: @{}, contentHeight);
      }

      // 设置状态标志，表明接下来对 setAbTestData: 的调用是来自我们 Hook 的应用逻辑
      s_isApplyingFixedData = YES;

      // 应用数据到 Manager
      // 这里的调用发生在队列上，Hook 内部的检查也会在队列上同步进行，是安全的。
      [manager setAbTestData:dataToApply];

      // 重置状态标志
      s_isApplyingFixedData = NO;

      NSLog(@"[DKXS] ABTest本地配置已应用");
    });
}

/**
 * 获取当前ABTest数据
 */
+ (NSDictionary *)getCurrentABTestData {
    AWEABTestManager *manager = [%c(AWEABTestManager) sharedManager];
    return manager ? [manager abTestData] : nil;
}

/**
 * 从网络检查并下载最新配置
 */
+ (void)checkForRemoteConfigUpdate:(BOOL)notify {
    dispatch_async(DKXSABTestQueue(), ^{
      NSString *urlString = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSRemoteConfigURL"];
      if (urlString.length == 0) {
          urlString = kDefaultRemoteConfigURL;
      }
      NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
      NSString *scheme = components.scheme.lowercaseString;
      BOOL invalidURL = NO;
      if (!components || components.host.length == 0 || !scheme || ![scheme isEqualToString:@"https"]) {
          invalidURL = YES;
      }
      NSURL *url = components.URL;
      if (invalidURL || !url) {
          if (notify) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [DKXSUtils showToast:@"配置地址无效"];
              });
          }
          return;
      }
      NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                 BOOL updated = NO;
                                                                 NSError *validationError = nil;
                                                                 if (data && !error) {
                                                                     id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&validationError];
                                                                     if (validationError || ![jsonObject isKindOfClass:[NSDictionary class]]) {
                                                                         if (!validationError) {
                                                                             validationError = [NSError errorWithDomain:@"com.dyyy.remoteconfig" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"配置格式错误"}];
                                                                         }
                                                                     } else {
                                                                         NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                                                                         NSString *documentsDirectory = [paths firstObject];
                                                                         NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DKXS"];
                                                                         NSString *jsonFilePath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];
                                                                         [[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
                                                                         NSData *existingData = [NSData dataWithContentsOfFile:jsonFilePath];
                                                                         if (!existingData || ![existingData isEqualToData:data]) {
                                                                             [data writeToFile:jsonFilePath atomically:YES];
                                                                             updated = YES;
                                                                         }
                                                                         if ([DKXSABTestHook isRemoteMode]) {
                                                                             [[NSUserDefaults standardUserDefaults] setBool:YES forKey:DKXS_REMOTE_CONFIG_FLAG_KEY];
                                                                             [[NSNotificationCenter defaultCenter] postNotificationName:DKXS_REMOTE_CONFIG_CHANGED_NOTIFICATION object:nil];
                                                                         }
                                                                     }
                                                                 }
                                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                                   if (error || !data) {
                                                                       if (notify) {
                                                                           [DKXSUtils showToast:@"配置更新失败"];
                                                                       }
                                                                   } else if (validationError) {
                                                                       if (notify) {
                                                                           [DKXSUtils showToast:@"配置解析失败"];
                                                                       }
                                                                   } else if (updated) {
                                                                       if (notify) {
                                                                           [DKXSUtils showToast:@"配置已更新"];
                                                                       }
                                                                       [DKXSABTestHook cleanLocalABTestData];
                                                                       [DKXSABTestHook loadLocalABTestConfig];
                                                                       [DKXSABTestHook applyFixedABTestData];
                                                                   } else {
                                                                       if (notify) {
                                                                           [DKXSUtils showToast:@"已是最新配置"];
                                                                       }
                                                                   }
                                                                 });
                                                               }];
      [task resume];
    });
}

@end

%hook AWEABTestManager

/**
 * Hook: 设置ABTest数据
 * 阻止在禁止下发模式下更新数据，除非当前正在应用本地配置
 * 使用 dispatch_sync 在队列上同步检查状态标志
 */
- (void)setAbTestData:(id)data {
    __block BOOL shouldBlock = NO;
    __block BOOL nativeLayoutChanged = NO;
    DKXSQueueSync(^{
      if (!s_isApplyingFixedData && (!data || [data isKindOfClass:NSDictionary.class])) {
          NSDictionary *layout = [DKXSABTestOverridePolicy nativeLayoutValuesFrom:data];
          nativeLayoutChanged = ![s_nativeLayoutABTestData isEqual:layout];
          s_nativeLayoutABTestData = layout;
      }
      // 在队列上安全地检查禁止下发标志 和 正在应用本地数据的标志
      // 如果禁止下发开启 并且 不是正在应用本地数据，则阻止
      if (s_abTestBlockEnabled && !s_isApplyingFixedData) {
          shouldBlock = YES;
      }
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止ABTest数据更新 (启用了禁止下发配置且非本地应用)");
        // 原生布局项有变化时，只通过既有串行应用入口复核一次；不在setter内读manager或递归赋值。
        if (nativeLayoutChanged) [DKXSABTestHook applyFixedABTestData];
        return;
    }

    id finalData = data;
    NSNumber *contentHeight = DKXSResolveTabBarHeightFromSettings();
    if (contentHeight) {
        if (!data || [data isKindOfClass:[NSDictionary class]]) {
            finalData = DKXSInjectTabBarHeightConfig(data ?: @{}, contentHeight);
        }
    }

    %orig(finalData);
}

/**
 * Hook: 增量更新ABTest数据
 * 在禁止下发模式下阻止增量更新
 * 使用 dispatch_sync 在队列上同步检查状态
 */
- (void)incrementalUpdateData:(id)data unchangedKeyList:(id)keyList {
    __block BOOL shouldBlock = NO;
    DKXSQueueSync(^{
      shouldBlock = s_abTestBlockEnabled;
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止增量更新ABTest数据 (启用了禁止下发配置)");
        return;
    }
    %orig;
}

/**
 * Hook: 从网络获取配置(带重试)
 * 在禁止下发模式下拦截网络请求，并立即返回空结果
 * 使用 dispatch_sync 在队列上同步检查状态
 */
- (void)fetchConfigurationWithRetry:(BOOL)retry completion:(id)completion {
    __block BOOL shouldBlock = NO;
    DKXSQueueSync(^{
      shouldBlock = s_abTestBlockEnabled;
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止从网络获取ABTest配置 (启用了禁止下发配置)");
        if (completion && [completion isKindOfClass:%c(NSBlock)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              ((void (^)(id))completion)(nil);
            });
        }
        return;
    }
    %orig;
}

/**
 * Hook: 从网络获取配置
 * 在禁止下发模式下阻止网络请求
 * 使用 dispatch_sync 在队列上同步检查状态
 */
- (void)fetchConfiguration:(id)arg1 {
    __block BOOL shouldBlock = NO;
    DKXSQueueSync(^{
      shouldBlock = s_abTestBlockEnabled;
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止从网络获取ABTest配置 (启用了禁止下发配置)");
        return;
    }
    %orig;
}

/**
 * Hook: 重写ABTest数据
 * 在禁止下发模式下阻止覆盖数据
 * 使用 dispatch_sync 在队列上同步检查状态
 */
- (void)overrideABTestData:(id)data needCleanCache:(BOOL)cleanCache {
    __block BOOL shouldBlock = NO;
    DKXSQueueSync(^{
      shouldBlock = s_abTestBlockEnabled;
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止重写ABTest数据 (启用了禁止下发配置)");
        return;
    }
    %orig;
}

/**
 * Hook: 保存ABTest数据
 * 在禁止下发模式下阻止保存
 * 使用 dispatch_sync 在队列上同步检查状态
 */
- (void)_saveABTestData:(id)data {
    __block BOOL shouldBlock = NO;
    DKXSQueueSync(^{
      shouldBlock = s_abTestBlockEnabled;
    });

    if (shouldBlock) {
        NSLog(@"[DKXS] 阻止保存ABTest数据 (启用了禁止下发配置)");
        return;
    }
    %orig;
}

%end

%ctor {
    // 预初始化队列以避免早期访问为 NULL
    DKXSABTestQueue();

    %init;

    // 在队列上异步读取初始状态并加载/应用配置
    dispatch_async(DKXSABTestQueue(), ^{
      s_abTestBlockEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSABTestBlockEnabled"];

      NSString *currentMode = nil;
      if ([DKXSABTestHook isRemoteMode]) {
          currentMode = [DKXSABTestHook isPatchMode] ? @"远程模式(覆写)" : @"远程模式(替换)";
      } else {
          currentMode = [DKXSABTestHook isPatchMode] ? @"覆写模式" : @"替换模式";
      }

      NSLog(@"[DKXS] ABTest Hook已启动: 禁止下发=%@, 当前模式=%@", s_abTestBlockEnabled ? @"开启" : @"关闭", currentMode);

      [DKXSABTestHook loadLocalABTestConfig];
      [DKXSABTestHook applyFixedABTestData];
      DKXSApplyTabBarHeightToCurrentABTestDataIfNeeded();
      if ([DKXSABTestHook isRemoteMode]) {
          [DKXSABTestHook checkForRemoteConfigUpdate:NO];
      }
    });
}
