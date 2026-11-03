# DY778 移植说明：仅保留福袋助手

来源：jijiang2333/DY778，commit 4c26f4f（该仓库唯一提交），文件原样拷贝，
仅入口与设置桥接是新写的（见下）。上游 DY778 无 LICENSE 文件；DY778 为
该仓库作者的自有项目，本移植保留 DY778* 符号与注释原样。

## 2026-11-03：删除 DY778 其余部分，只留福袋

用户决定删除 DY778 的其余代码，只保留福袋助手。本次删除：

- `src/Features/MessageArchive/` 整个目录（消息留存 / 编辑历史 / 撤回通知 /
  消息 UI，DKXS* 改名前缀移植）及其在 `DKSettingsLayout.m` 的“消息留存”分区。
- `src/Features/DY778/` 内的缓存清理、Feed 过滤、播放倍速、留存存储：
  `DY778CacheCleaner.h/.m`、`DY778CachePolicy.h`、`DY778FeedFilter.h/.m`、
  `DY778FeedFilterPolicy.h`、`DY778Playback.h/.m`、`DY778DefaultPlayback.m`、
  `DY778ArchiveStorage.h/.m`（`DY778Core.m` 里对它的 import 一并去掉，
  Core.m 并不使用其中的符号）。
- 设置：`DY778RemainingSettings.xm` 只留 7 个福袋键，布局分区改名“DY778 福袋”；
  `Makefile` 去掉仅播放模块用的 `AVKit`（`WebKit` 福袋面板仍需，保留）；
  `control` 版本升至 0.6.9.4。

保留的文件（`src/Features/DY778/`）：`DY778Core.h/.m`、`DY778Avatar.h/.m`、
`DY778Toast.m`、`DY778LuckyBag.h/.m`、`DY778LuckyClock.h`、`DY778LuckyPolicy.h`、
`DY778PlaybackPolicy.h`（仅倍速标签格式化静态内联函数，供 `DY778Toast.m` 使用）、
`DY778Entry.m`（只装 Core + 福袋）、`DY778RemainingSettings.xm`（福袋键桥接）。

福袋助手只处理当前直播间的普通免费福袋；需灯牌、送礼、付费等额外条件时跳过，
不代为点亮、升级、关注或消费（上游原逻辑）。

## 设置桥接

DY778 模块读 DY778 专用 suite（`com.dy778.douyin`）的点分键，
DYxs 设置页写标准 defaults 的 DKXS* 键。`DY778RemainingSettings.xm` 在
%ctor 同步一次、每次改值后通过 `DKSettingsOnChange` 再同步一次，
经 `DY778Set` 钳制数值范围并发出偏好变化通知。未动过的键沿用
`DY778RegisterDefaults` 的默认值（福袋默认关闭）。
布局行见 `DKSettingsLayout.m` 的“DY778 福袋”分区（7 行）。
死键不登记：`lucky.autoPhrase` / `lucky.autoJoin` 只出现在上游默认值表里，
本 commit 的福袋代码并不读取。

## 尚未验证，必须由 CI / 真机验证

- 未在本机编译：Linux 无 Theos / iOS SDK。第一次真实编译由推送后的
  macOS 26 Action 完成；若 CI 报错，按报错修。删除消息留存目录后，
  run 41573517237 在 `DKXSMessageArchiveHooks.xm` 报的错误随文件消失。
- 福袋助手会用抖音原生能力实际参与福袋：上真机前用测试号核对，
  默认关闭，需手动开启。
