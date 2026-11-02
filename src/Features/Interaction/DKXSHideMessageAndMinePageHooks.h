// 移植来源：Wtrwx/DYYY 的 DYYYHideMessageAndMinePageHooks.h。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装「消息页星光商城 / 我的页头像加号 / 我的创作 AI 作品」Runtime Hook。
/// 安装与开关无关；替换函数实时读取设置，关闭时透传原实现。
FOUNDATION_EXPORT void DKXSStartHideMessageAndMinePageHooks(void);

NS_ASSUME_NONNULL_END
