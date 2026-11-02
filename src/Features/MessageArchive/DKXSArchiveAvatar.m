//  DKXSArchiveAvatar.m
//  DY778 第 1 批 staging：见头文件注释。

#import "DKXSArchiveAvatar.h"
#import "DKXSArchiveCore.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSArray *DKXSAvatarFields(void) {
    return @[@"avatar", @"avatarURL", @"avatarUrl", @"avatar_url", @"headImage", @"portrait", @"userAvatar", @"avatar_thumb", @"avatarThumb"];
}
NSString *DKXSArchiveAvatarURL(id value) {
    return DKXSArchiveAvatarURLs(value).firstObject ?: @"";
}
NSArray *DKXSArchiveAvatarURLs(id value) {
    NSMutableArray *urls = [NSMutableArray array];
    if ([value isKindOfClass:NSString.class]) { if ([value hasPrefix:@"http"]) [urls addObject:value]; return urls; }
    for (NSString *field in DKXSAvatarFields()) {
        id node = DKXSArchiveRead(value, field);
        if ([node isKindOfClass:NSString.class] && [node hasPrefix:@"http"]) [urls addObject:node];
        else if ([node isKindOfClass:NSDictionary.class]) {
            for (NSString *sub in @[@"url", @"url_list", @"origin_url"]) {
                id inner = node[sub];
                if ([inner isKindOfClass:NSString.class] && [inner hasPrefix:@"http"]) [urls addObject:inner];
                else if ([inner isKindOfClass:NSArray.class] && [[inner firstObject] isKindOfClass:NSString.class] && [[inner firstObject] hasPrefix:@"http"]) [urls addObject:[inner firstObject]];
            }
        } else if ([node isKindOfClass:NSArray.class]) {
            for (id item in node) if ([item isKindOfClass:NSString.class] && [item hasPrefix:@"http"]) [urls addObject:item];
        }
    }
    return urls;
}
void DKXSArchiveLoadAvatarURLs(UIImageView *view, NSArray *urls, NSString *identity) {
    NSString *urlString = urls.firstObject;
    if (!urlString.length || !view) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    view.accessibilityIdentifier = identity ?: @"";
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![view.accessibilityIdentifier isEqualToString:identity ?: @""]) return;
            view.image = image;
        });
    }];
    objc_setAssociatedObject(view, @"DKXSArchiveAvatarTask", task, OBJC_ASSOCIATION_RETAIN);
    [task resume];
}
void DKXSArchiveLoadAvatar(UIImageView *view, NSString *url, NSString *identity) {
    DKXSArchiveLoadAvatarURLs(view, url.length ? @[url] : @[], identity);
}
NSDictionary *DKXSArchiveProfileFromUser(id user) {
    if (!user) return @{};
    NSString *uid = DKXSArchiveIdentifier(DKXSArchiveRead(user, @"uid") ?: DKXSArchiveRead(user, @"userID"));
    NSString *name = DKXSArchiveIdentifier(DKXSArchiveRead(user, @"nickname") ?: DKXSArchiveRead(user, @"name"));
    NSString *avatar = DKXSArchiveAvatarURL(user);
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    if (uid.length) profile[@"uid"] = uid;
    if (name.length) profile[@"name"] = name;
    if (avatar.length) profile[@"avatar"] = avatar;
    return profile;
}
void DKXSArchiveGetCurrentAccountProfile(void (^completion)(NSDictionary *profile)) {
    if (!completion) return;
    @try {
        Class serviceClass = NSClassFromString(@"AWEUserService");
        id service = nil;
        if ([serviceClass respondsToSelector:@selector(sharedInstance)]) service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedInstance));
        id user = service ? DKXSArchiveRead(service, @"currentUser") : nil;
        completion(DKXSArchiveProfileFromUser(user));
    } @catch (__unused NSException *e) { completion(@{}); }
}
void DKXSArchiveLoadCurrentAccountAvatar(UIImageView *view) {
    DKXSArchiveGetCurrentAccountProfile(^(NSDictionary *profile) {
        if (profile[@"avatar"]) DKXSArchiveLoadAvatar(view, profile[@"avatar"], @"current-account");
    });
}
void DKXSArchiveGetLocalUserProfile(NSString *account, NSString *uid, void (^completion)(NSDictionary *profile)) {
    // 本批不做本地用户库：只在当前账号时返回当前资料，其余返回空（上游的 DB 查询不移植）。
    if (!completion) return;
    if ([uid isEqual:DKXSArchiveCurrentAccountID()]) DKXSArchiveGetCurrentAccountProfile(completion);
    else completion(@{});
}
