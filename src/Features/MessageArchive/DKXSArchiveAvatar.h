//  DKXSArchiveAvatar.h
//  DY778 第 1 批 staging：头像加载辅助（撤回通知与记录页用）。
//  对应上游 DY778Avatar.h，改名前缀；行为保留：
//  · 只读调用，不 hook AWEIMUserDBManager / AWEUserService；
//  · 下载用 ephemeral 会话，不带 Cookie；失败时保留占位图，不重试轰炸。

#import <UIKit/UIKit.h>

// 从任意对象（用户、资料、消息发送者）中抽头像地址。
FOUNDATION_EXPORT NSString *DKXSArchiveAvatarURL(id value);
FOUNDATION_EXPORT NSArray *DKXSArchiveAvatarURLs(id value);
FOUNDATION_EXPORT void DKXSArchiveLoadAvatar(UIImageView *view, NSString *url, NSString *identity);
FOUNDATION_EXPORT void DKXSArchiveLoadAvatarURLs(UIImageView *view, NSArray *urls, NSString *identity);
FOUNDATION_EXPORT void DKXSArchiveLoadCurrentAccountAvatar(UIImageView *view);
// {uid, name, avatar}，拿不到返回空字典，不抛异常。
FOUNDATION_EXPORT void DKXSArchiveGetCurrentAccountProfile(void (^completion)(NSDictionary *profile));
FOUNDATION_EXPORT NSDictionary *DKXSArchiveProfileFromUser(id user);
FOUNDATION_EXPORT void DKXSArchiveGetLocalUserProfile(NSString *account, NSString *uid, void (^completion)(NSDictionary *profile));
