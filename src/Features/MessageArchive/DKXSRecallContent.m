//  DKXSRecallContent.m
//  DY778 第 1 批 staging：见头文件注释。分类规则与上游一致，做了两处收敛：
//  · 媒体遍历预算（深度 22、节点预算）与无关路径排除原样保留，避免大分享体拖慢主线程；
//  · 系统撤回提示判定保留“type 40001 且在官方非用户生成集合内”的双重校验，单凭 type 不算。

#import "DKXSRecallContent.h"
#import "DKXSMessageArchivePolicy.h"
#import "DKXSArchiveCore.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *DKXSContentString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}
static NSString *DKXSValueForKeys(NSDictionary *node, NSArray *keys) {
    for (NSString *key in keys) {
        NSString *value = DKXSContentString(node[key]);
        if (value.length && ![value isEqualToString:@"Recall Content Hided"]) return value;
    }
    return @"";
}
static BOOL DKXSHasContentValue(NSDictionary *node, NSArray *keys) {
    for (NSString *key in keys) {
        id value = node[key];
        if ([value isKindOfClass:NSString.class] && [value length]) return YES;
        if (([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) && [value count]) return YES;
    }
    return NO;
}
static BOOL DKXSContainsAny(NSString *text, NSArray *words) {
    for (NSString *word in words) if ([text containsString:word]) return YES;
    return NO;
}
static id DKXSUnpackContent(id node) {
    if (![node isKindOfClass:NSString.class] || [node length] > 1024 * 1024) return node;
    NSString *text = [node stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![text hasPrefix:@"{"] && ![text hasPrefix:@"["]) return node;
    id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [parsed isKindOfClass:NSDictionary.class] || [parsed isKindOfClass:NSArray.class] ? parsed : node;
}

NSString *DKXSRecallMessageKind(NSString *className) {
    if (![className isKindOfClass:NSString.class] || ![className hasPrefix:@"AWEIM"]) return @"";
    if ([className containsString:@"AudioMessage"]) return @"audio";
    if ([className containsString:@"ImageMessage"]) return @"image";
    if ([className containsString:@"VideoMessage"] && ![className containsString:@"Share"] && ![className containsString:@"Feed"]) return @"video";
    if ([className isEqualToString:@"AWEIMShareLocationMessage"]) return @"location";
    return @"";
}

BOOL DKXSRecallContentIsNotice(id content) {
    NSDictionary *node = [content isKindOfClass:NSDictionary.class] ? content : nil;
    if (!node) return NO;
    id type = node[@"type"] ?: node[@"messageType"];
    if ([type longLongValue] != 40001) return NO;
    // 双重校验：type 40001 且官方把它列为非用户生成类型，才算系统提示。
    static NSSet *systemTypes; static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"AWEIMMessage");
        SEL selector = NSSelectorFromString(@"notUserGeneratedMessageTypes");
        Method method = class_getClassMethod(cls, selector);
        if (!method || method_getNumberOfArguments(method) != 2) return;
        char returned[8] = {0}; method_getReturnType(method, returned, sizeof(returned));
        if (returned[0] != '@') return;
        @try {
            id values = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
            if ([values isKindOfClass:NSSet.class]) systemTypes = [values copy];
            else if ([values isKindOfClass:NSArray.class]) systemTypes = [NSSet setWithArray:values];
        } @catch (__unused NSException *e) { }
    });
    return [systemTypes containsObject:@40001] || [systemTypes containsObject:@"40001"];
}

static NSString *DKXSNodeKind(NSDictionary *node, NSString *inherited) {
    if (DKXSValueForKeys(node, @[@"recall_user_id", @"recallUserID", @"recalled_message_id", @"recall_message_id", @"custom_recall_text", @"customRecallText"]).length) return @"recall-notice";
    if ([@[@"image", @"audio", @"video", @"location"] containsObject:inherited]) return inherited;
    if (DKXSValueForKeys(node, @[@"room_id", @"roomId", @"roomID", @"room_owner_id"]).length) return @"live";
    if (DKXSValueForKeys(node, @[@"product_id", @"productId", @"promotion_id", @"promotionId", @"chatGoodsSchema"]).length) return @"goods";
    if (DKXSValueForKeys(node, @[@"sticker_type", @"stickerType", @"sticker_id", @"stickerID", @"giphy_name", @"giphyName", @"emoji_type", @"emojiType", @"animate_url", @"animateURL"]).length || node[@"giphy_url"] || node[@"giphyURL"]) return @"sticker";
    if (DKXSHasContentValue(node, @[@"res_origin_url_list", @"resOriginUrlList", @"res_thumb_url_list", @"resThumbUrlList", @"res_medium_url_list", @"resMediumUrlList", @"res_large_url_list", @"resLargeUrlList", @"res_long_url_list", @"resLongUrlList", @"res_still_url_list", @"resStillUrlList"])) return @"image";
    BOOL resource = DKXSHasContentValue(node, @[@"resource_url", @"resourceUrl"]);
    NSString *contentType = DKXSValueForKeys(node, @[@"content_type", @"contentType"]).lowercaseString;
    BOOL dimensions = (node[@"cover_width"] || node[@"coverWidth"]) && (node[@"cover_height"] || node[@"coverHeight"]);
    if ([contentType hasPrefix:@"audio/"] || [@[@"audio", @"voice"] containsObject:contentType] ||
        (resource && (node[@"average_power_arr"] || node[@"averagePowerArr"] || (node[@"duration"] && !dimensions)))) return @"audio";
    if (resource && dimensions) return @"image";
    NSString *workID = DKXSValueForKeys(node, @[@"aweme_id", @"awemeID", @"itemId", @"item_id"]);
    if (workID.length && ![workID isEqualToString:@"0"]) return @"work";
    id latitude = node[@"latitude"], longitude = node[@"longitude"] ?: node[@"lng"];
    if ([latitude respondsToSelector:@selector(doubleValue)] && [longitude respondsToSelector:@selector(doubleValue)]) {
        double lat = [latitude doubleValue], lon = [longitude doubleValue];
        BOOL described = DKXSHasContentValue(node, @[@"cover_resource_url", @"coverResourceUrl", @"poi_name", @"poiName", @"poi_address", @"poiAddress"]);
        if (described && isfinite(lat) && isfinite(lon) && fabs(lat) <= 90 && fabs(lon) <= 180) return @"location";
    }
    return inherited ?: @"";
}
static NSString *DKXSKindForURL(NSString *path, NSString *context, NSURL *url) {
    NSString *all = [NSString stringWithFormat:@"%@ %@", path.lowercaseString, url.pathExtension.lowercaseString];
    if (DKXSContainsAny(all, @[@"avatar", @"portrait"])) return nil;
    if (DKXSContainsAny(all, @[@"cover", @"thumb", @"display_icon", @"displayicon", @"static_url", @"staticurl"])) return @"image";
    if ([@[@"image", @"audio", @"video"] containsObject:context] && DKXSContainsAny(path.lowercaseString, @[@"resource", @"res_", @"resorigin", @"resmedium", @"reslarge", @"reslong", @"resstill"])) return context;
    if (DKXSContainsAny(all, @[@"audio", @"voice", @"mp3", @"m4a", @"aac", @"wav", @"amr", @"opus"])) return @"audio";
    if (DKXSContainsAny(all, @[@"video", @"play_addr", @"playurl", @"play_url", @"mp4", @"mov", @"m3u8"])) return @"video";
    if (DKXSContainsAny(all, @[@"image", @"photo", @"giphy", @"sticker", @"emoji", @"animate", @"jpg", @"jpeg", @"png", @"gif", @"webp", @"heic"])) return @"image";
    if (DKXSContainsAny(all, @[@"file_url", @"fileurl", @"download_url"])) return @"file";
    if ([@[@"sticker", @"goods", @"live"] containsObject:context]) return @"image";
    return nil;
}
static BOOL DKXSUnrelatedMediaPath(NSString *path) {
    return DKXSContainsAny(path.lowercaseString, @[@".author", @".user", @".avatar", @".portrait", @".music", @".quote", @".reply", @".refer", @".comment", @".emoji_icon", @".blur", @".gaussian"]);
}
static NSInteger DKXSMediaQuality(NSString *path) {
    NSString *p = path.lowercaseString;
    if (DKXSContainsAny(p, @[@"origin", @"original", @"large", @"high_quality"])) return 600;
    if (DKXSContainsAny(p, @[@"thumb", @"small", @"preview"])) return 100;
    if (DKXSContainsAny(p, @[@"dynamic", @"animate"])) return 200;
    if (DKXSContainsAny(p, @[@"cover", @"poster"])) return 500;
    if (DKXSContainsAny(p, @[@"image", @"photo"])) return 400;
    return 300;
}
static void DKXSWalkContent(id raw, NSString *path, NSString *inherited, NSMutableDictionary *presentation,
                            NSMutableArray *media, NSMutableSet *seen, NSUInteger depth, NSUInteger *budget) {
    if (depth > 22 || !*budget || DKXSUnrelatedMediaPath(path)) return; (*budget)--;
    id node = DKXSUnpackContent(raw);
    if ([node isKindOfClass:NSDictionary.class]) {
        NSString *kind = DKXSNodeKind(node, inherited);
        NSDictionary *authorNode = [node[@"author"] isKindOfClass:NSDictionary.class] ? node[@"author"] : nil;
        NSString *authorName = DKXSValueForKeys(authorNode, @[@"nickname", @"name"]);
        if (authorName.length && ![presentation[@"author"] length]) presentation[@"author"] = authorName;
        if (kind.length && (![presentation[@"kind"] length] || [kind isEqualToString:@"recall-notice"])) presentation[@"kind"] = kind;
        NSString *text = DKXSValueForKeys(node, @[@"text", @"content", @"title", @"desc", @"description"]);
        if (text.length && ![presentation[@"text"] length]) presentation[@"text"] = text;
        for (NSString *key in node) {
            id child = node[key];
            NSString *childPath = [path stringByAppendingFormat:@".%@", key];
            if ([child isKindOfClass:NSString.class]) {
                NSURL *url = [NSURL URLWithString:child];
                if (url.scheme.length && url.host.length) {
                    NSString *urlKind = DKXSKindForURL(childPath, kind, url);
                    if (urlKind) {
                        NSString *identity = child;
                        if (![seen containsObject:identity]) {
                            [seen addObject:identity];
                            [media addObject:@{@"kind": urlKind, @"remoteURL": child, @"quality": @(DKXSMediaQuality(childPath)), @"cover": @NO}];
                        }
                    }
                }
            } else if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
                DKXSWalkContent(child, childPath, kind, presentation, media, seen, depth + 1, budget);
            }
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id item in node) DKXSWalkContent(item, path, inherited, presentation, media, seen, depth + 1, budget);
    }
}

NSArray *DKXSRecallMediaFromContent(id content) {
    NSMutableDictionary *presentation = [NSMutableDictionary dictionary];
    NSMutableArray *media = [NSMutableArray array];
    NSUInteger budget = 400;
    DKXSWalkContent(content, @"", @"", presentation, media, [NSMutableSet set], 0, &budget);
    return [media sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"quality"] compare:a[@"quality"]];
    }];
}
static NSDictionary *DKXSEnrichCard(NSDictionary *record) {
    id content = record[@"content"];
    NSMutableDictionary *presentation = [NSMutableDictionary dictionary];
    NSMutableArray *media = [NSMutableArray array];
    NSUInteger budget = 400;
    DKXSWalkContent(content, @"", DKXSRecallMessageKind(record[@"messageClass"]), presentation, media, [NSMutableSet set], 0, &budget);
    NSArray *sorted = [media sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"quality"] compare:a[@"quality"]];
    }];
    NSMutableDictionary *card = [NSMutableDictionary dictionary];
    card[@"kind"] = presentation[@"kind"] ?: @"";
    card[@"text"] = presentation[@"text"] ?: @"";
    card[@"author"] = presentation[@"author"] ?: (record[@"senderName"] ?: @"");
    card[@"media"] = sorted;
    card[@"workID"] = DKXSValueForKeys([content isKindOfClass:NSDictionary.class] ? content : @{}, @[@"aweme_id", @"awemeID", @"itemId", @"item_id"]);
    NSDictionary *comment = DKXSRecallCommentFromContent(content);
    if (comment) card[@"comment"] = comment;
    return card;
}
NSDictionary *DKXSRecallEnrichRecord(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *enriched = [record mutableCopy];
    enriched[@"card"] = DKXSEnrichCard(record);
    return enriched;
}
NSString *DKXSRecallSummary(NSDictionary *record) {
    NSDictionary *card = [record isKindOfClass:NSDictionary.class] ? record[@"card"] : nil;
    if (![card isKindOfClass:NSDictionary.class]) card = DKXSEnrichCard(record)[@"card"];
    NSString *text = card[@"text"];
    if (text.length) return text.length > 120 ? [[text substringToIndex:120] stringByAppendingString:@"…"] : text;
    static NSDictionary *kindNames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kindNames = @{@"image": @"[图片]", @"audio": @"[语音]", @"video": @"[视频]", @"live": @"[直播分享]", @"goods": @"[商品分享]", @"sticker": @"[表情]", @"work": @"[作品分享]", @"location": @"[位置分享]"}; });
    return kindNames[card[@"kind"]] ?: @"[消息]";
}
NSDictionary *DKXSRecallCommentFromContent(id content) {
    if (![content isKindOfClass:NSDictionary.class]) return nil;
    // 分享评论节点：只取带评论文字/作者/编号的分支。
    for (NSString *key in @[@"comment", @"shareComment", @"referComment", @"quotedComment"]) {
        id node = content[key];
        if (![node isKindOfClass:NSDictionary.class]) continue;
        NSString *text = DKXSValueForKeys(node, @[@"text", @"content", @"comment_text"]);
        NSString *author = DKXSValueForKeys([node[@"author"] isKindOfClass:NSDictionary.class] ? node[@"author"] : @{}, @[@"nickname", @"name"]);
        NSString *commentID = DKXSValueForKeys(node, @[@"comment_id", @"commentID", @"cid"]);
        if (text.length || author.length) return @{@"text": text ?: @"", @"author": author ?: @"", @"commentID": commentID ?: @""};
    }
    return nil;
}
NSDictionary *DKXSMergeCapturedComment(NSDictionary *previous, NSDictionary *candidate) {
    // 首次取得的评论文字为准：已有文字时后续删除提示不得覆盖；只有旧记录无文字时才补。
    if (!candidate) return previous;
    if (!previous) return candidate;
    if ([previous[@"text"] length]) return previous;
    NSMutableDictionary *merged = [previous mutableCopy];
    if ([candidate[@"text"] length]) merged[@"text"] = candidate[@"text"];
    if (![merged[@"author"] length] && [candidate[@"author"] length]) merged[@"author"] = candidate[@"author"];
    if (![merged[@"commentID"] length] && [candidate[@"commentID"] length]) merged[@"commentID"] = candidate[@"commentID"];
    return merged;
}
NSString *DKXSRecallWorkIdentifier(NSDictionary *record) {
    NSDictionary *card = record[@"card"];
    NSString *workID = [card isKindOfClass:NSDictionary.class] ? card[@"workID"] : nil;
    if (!workID.length || [workID isEqualToString:@"0"]) {
        id content = record[@"content"];
        workID = [content isKindOfClass:NSDictionary.class] ? DKXSValueForKeys(content, @[@"aweme_id", @"awemeID", @"itemId", @"item_id"]) : @"";
    }
    if (!workID.length || [workID isEqualToString:@"0"]) return nil;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [workID rangeOfCharacterFromSet:nonDigits].location == NSNotFound ? workID : nil;
}
BOOL DKXSRecallRecordShouldHide(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return YES;
    if ([record[@"systemRecallNotice"] boolValue]) return YES;
    if (DKXSRecallContentIsNotice(record[@"content"])) return YES;
    NSDictionary *card = record[@"card"];
    if (![card isKindOfClass:NSDictionary.class]) card = DKXSEnrichCard(record)[@"card"];
    return ![card[@"text"] length] && ![card[@"media"] count] && ![card[@"kind"] length];
}
NSArray *DKXSRecallPreviewCandidates(NSDictionary *record) {
    NSDictionary *card = [record isKindOfClass:NSDictionary.class] ? record[@"card"] : nil;
    if (![card isKindOfClass:NSDictionary.class]) card = DKXSEnrichCard(record)[@"card"];
    NSArray *media = card[@"media"];
    return [media isKindOfClass:NSArray.class] ? media : @[];
}
NSDictionary *DKXSRecallPrimaryMedia(NSDictionary *record) {
    NSArray *candidates = DKXSRecallPreviewCandidates(record);
    return candidates.firstObject;
}
