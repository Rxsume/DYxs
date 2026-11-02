//
//  DKXSInterfaceDownload.m
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//

#import "DKXSInterfaceDownload.h"
#import <UIKit/UIKit.h>
#import "DKXSUtils.h"
#import "DKMediaDownloader.h"
#import "DKMediaLibrary.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

@implementation DKXSInterfaceDownload

+ (void)parseAndDownloadWithShareLink:(NSString *)shareLink {
    NSString *apiKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSInterfaceDownload"];
    if (shareLink.length == 0 || apiKey.length == 0) {
        [DKXSUtils showToast:@"分享链接或API密钥无效"];
        return;
    }

    NSString *apiUrl = [NSString stringWithFormat:@"%@%@",
                        apiKey,
                        [shareLink stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSURL *url = [NSURL URLWithString:apiUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                    if (error) {
                                                        [DKXSUtils showToast:[NSString stringWithFormat:@"接口请求失败: %@", error.localizedDescription]];
                                                        return;
                                                    }
                                                    NSError *jsonError = nil;
                                                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                                                    if (jsonError) {
                                                        [DKXSUtils showToast:@"解析接口返回数据失败"];
                                                        return;
                                                    }
                                                    NSInteger code = [json[@"code"] integerValue];
                                                    if (code != 0 && code != 200) {
                                                        [DKXSUtils showToast:[NSString stringWithFormat:@"接口返回错误: %@", json[@"msg"] ?: @"未知错误"]];
                                                        return;
                                                    }
                                                    NSDictionary *dataDict = json[@"data"];
                                                    if (!dataDict) {
                                                        [DKXSUtils showToast:@"接口返回数据为空"];
                                                        return;
                                                    }
                                                    [self handleVideoData:dataDict];
                                                  });
                                                }];
    [dataTask resume];
}

#pragma mark - 下载执行（DYxs MediaSave 基础设施）

+ (DKMediaDownloader *)sharedDownloader {
    static DKMediaDownloader *downloader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"DKXSInterfaceDownload"];
        downloader = [[DKMediaDownloader alloc] initWithDirectory:dir];
    });
    return downloader;
}

+ (void)downloadVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL {
    DKMediaCandidate *candidate = [DKMediaCandidate candidateWithURLs:@[ videoURL.absoluteString ] tag:@"接口解析"];
    [[self sharedDownloader] fetch:@[ candidate ] accept:nil validate:nil completion:^(NSURL *file, DKMediaCandidate *c, NSString *u, NSString *error) {
        if (error || !file) {
            [DKXSUtils showToast:[NSString stringWithFormat:@"视频下载失败：%@", error ?: @"未知错误"]];
            return;
        }
        if (!audioURL) {
            DKMediaLibrarySaveVideo(file, ^(NSString *saveError) {
                [DKXSUtils showToast:saveError ? [NSString stringWithFormat:@"相册写入失败：%@", saveError] : @"视频已保存到相册"];
            });
            return;
        }
        DKMediaCandidate *audioCandidate = [DKMediaCandidate candidateWithURLs:@[ audioURL.absoluteString ] tag:@"背景音乐"];
        [[self sharedDownloader] fetch:@[ audioCandidate ] accept:nil validate:nil completion:^(NSURL *audio, DKMediaCandidate *ac, NSString *au, NSString *audioError) {
            if (audioError || !audio) {
                DKMediaLibrarySaveVideo(file, ^(NSString *saveError) {
                    [DKXSUtils showToast:saveError ? [NSString stringWithFormat:@"相册写入失败：%@", saveError] : @"视频已保存到相册（无音轨）"];
                });
                return;
            }
            NSURL *output = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mov"]];
            DKMediaComposeAudio(file, audio, output, ^(NSURL *merged, NSString *mergeError) {
                DKMediaLibrarySaveVideo(merged ?: file, ^(NSString *saveError) {
                    [DKXSUtils showToast:saveError ? [NSString stringWithFormat:@"相册写入失败：%@", saveError] : @"视频已保存到相册"];
                });
            });
        }];
    }];
}

+ (void)downloadImageURL:(NSURL *)imageURL {
    DKMediaCandidate *candidate = [DKMediaCandidate candidateWithURLs:@[ imageURL.absoluteString ] tag:@"接口解析"];
    [[self sharedDownloader] fetch:@[ candidate ] accept:nil validate:nil completion:^(NSURL *file, DKMediaCandidate *c, NSString *u, NSString *error) {
        if (error || !file) {
            [DKXSUtils showToast:[NSString stringWithFormat:@"图片下载失败：%@", error ?: @"未知错误"]];
            return;
        }
        NSData *data = [NSData dataWithContentsOfURL:file];
        if (!data.length) {
            [DKXSUtils showToast:@"图片下载失败"];
            return;
        }
        NSString *ext = file.pathExtension.lowercaseString;
        NSString *uti = ([ext isEqualToString:@"png"] ? @"public.png" : @"public.jpeg");
        DKMediaLibrarySavePhotoData(data, uti, ^(NSString *saveError) {
            [DKXSUtils showToast:saveError ? [NSString stringWithFormat:@"相册写入失败：%@", saveError] : @"图片已保存到相册"];
        });
    }];
}

+ (void)presentChoices:(NSArray<NSDictionary *> *)choices title:(NSString *)title {
    UIViewController *top = [DKXSUtils topView];
    if (!top) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *choice in choices) {
        NSString *choiceTitle = choice[@"title"];
        void (^handler)(void) = choice[@"handler"];
        [alert addAction:[UIAlertAction actionWithTitle:choiceTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (handler) {
                handler();
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

#pragma mark - handleVideoData（流程与上游一致，UI 与下载改走本文件执行端）

+ (void)handleVideoData:(NSDictionary *)dataDict {
    NSArray *videoList = dataDict[@"video_list"];
    NSArray *videos = dataDict[@"videos"];
    NSArray *images = dataDict[@"images"];
    NSArray *imgArray = dataDict[@"img"];

    NSString *coverURL = nil;
    if (dataDict[@"cover"] && [dataDict[@"cover"] length] > 0) {
        coverURL = dataDict[@"cover"];
    } else if (dataDict[@"pics"] && [dataDict[@"pics"] length] > 0) {
        coverURL = dataDict[@"pics"];
    }

    NSString *musicURL = nil;
    if (dataDict[@"music"] && [dataDict[@"music"] length] > 0) {
        musicURL = dataDict[@"music"];
    } else if (dataDict[@"music_url"] && [dataDict[@"music_url"] length] > 0) {
        musicURL = dataDict[@"music_url"];
    }

    NSString *singleVideoURL = nil;
    if (dataDict[@"url"] && [dataDict[@"url"] length] > 0) {
        singleVideoURL = dataDict[@"url"];
    } else if (dataDict[@"video"] && [dataDict[@"video"] length] > 0) {
        singleVideoURL = dataDict[@"video"];
    } else if (dataDict[@"video_url"] && [dataDict[@"video_url"] length] > 0) {
        singleVideoURL = dataDict[@"video_url"];
    } else if ([videos isKindOfClass:[NSArray class]] && videos.count > 0) {
        id first = videos[0];
        if ([first isKindOfClass:[NSDictionary class]]) {
            singleVideoURL = first[@"url"];
        } else if ([first isKindOfClass:[NSString class]]) {
            singleVideoURL = first;
        }
    }

    BOOL shouldShowQualityOptions = DKXSGetBool(@"DKXSShowAllVideoQuality");
    NSURL *optionalAudioURL = musicURL.length > 0 ? [NSURL URLWithString:musicURL] : nil;

    // 多清晰度列表优先处理（上游原样：video_list 有内容时先走这里）。
    BOOL hasVideoList = [videoList isKindOfClass:[NSArray class]] && videoList.count > 0;
    if (hasVideoList) {
        if (shouldShowQualityOptions) {
            NSMutableArray *choices = [NSMutableArray array];
            for (NSDictionary *videoDict in videoList) {
                NSString *url = videoDict[@"url"];
                NSString *level = videoDict[@"level"];
                if (url.length > 0 && level.length > 0) {
                    [choices addObject:@{ @"title" : level, @"handler" : ^{
                        [self downloadVideoURL:[NSURL URLWithString:url] audioURL:optionalAudioURL];
                    } }];
                }
            }
            if (choices.count > 0) {
                [self presentChoices:choices title:@"选择清晰度"];
                return;
            }
        } else {
            NSDictionary *first = videoList[0];
            NSString *url = first[@"url"];
            if (url.length > 0) {
                [self downloadVideoURL:[NSURL URLWithString:url] audioURL:optionalAudioURL];
                return;
            }
        }
    }

    // 只有图片没有视频时，直接处理图片下载（上游原样分支的简化版：
    // 上游在此还分单图直存与多图批量；本移植逐张保存并提示）。
    BOOL hasImages = [images isKindOfClass:[NSArray class]] && images.count > 0;
    BOOL hasImgArray = [imgArray isKindOfClass:[NSArray class]] && imgArray.count > 0;
    if (!singleVideoURL && (hasImages || hasImgArray || coverURL != nil)) {
        NSMutableArray *allImages = [NSMutableArray array];
        if (hasImages) {
            [allImages addObjectsFromArray:images];
        }
        if (hasImgArray) {
            [allImages addObjectsFromArray:imgArray];
        }
        if (coverURL && ![allImages containsObject:coverURL]) {
            [allImages addObject:coverURL];
        }
        for (id item in allImages) {
            NSString *urlString = nil;
            if ([item isKindOfClass:[NSString class]]) {
                urlString = item;
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                urlString = item[@"url"];
            }
            if (urlString.length > 0) {
                [self downloadImageURL:[NSURL URLWithString:urlString]];
            }
        }
        return;
    }

    // 单个视频：开清晰选项时弹选择（下载视频/封面/背景音乐），否则直接下载。
    if (singleVideoURL.length > 0) {
        if (shouldShowQualityOptions) {
            NSMutableArray *choices = [NSMutableArray array];
            [choices addObject:@{ @"title" : @"下载视频", @"handler" : ^{
                [self downloadVideoURL:[NSURL URLWithString:singleVideoURL] audioURL:optionalAudioURL];
            } }];
            if (coverURL.length > 0) {
                [choices addObject:@{ @"title" : @"下载封面图", @"handler" : ^{
                    [self downloadImageURL:[NSURL URLWithString:coverURL]];
                } }];
            }
            if (musicURL.length > 0) {
                [choices addObject:@{ @"title" : @"下载背景音乐", @"handler" : ^{
                    [self downloadImageURL:[NSURL URLWithString:musicURL]];
                } }];
            }
            [self presentChoices:choices title:@"接口解析"];
            return;
        }
        [self downloadVideoURL:[NSURL URLWithString:singleVideoURL] audioURL:optionalAudioURL];
        return;
    }

    [DKXSUtils showToast:@"接口返回数据中没有可下载的媒体"];
}

@end
