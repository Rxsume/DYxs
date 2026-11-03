# DY778 第 2 批移植说明：福袋助手 / 缓存清理 / Feed 过滤 / 播放倍速

来源：jijiang2333/DY778，commit 4c26f4f（该仓库唯一提交），文件原样拷贝，
仅入口与设置桥接是新写的（见下）。上游 DY778 无 LICENSE 文件；DY778 为
该仓库作者的自有项目，本移植保留 DY778* 符号与注释原样。

## 移植了什么（src/Features/DY778/，共 23 个文件）

- 基础：`DY778Core.h/.m`、`DY778ArchiveStorage.h/.m`、`DY778Toast.m`、
  `DY778Avatar.h/.m`（福袋面板用头像加载）。
- 福袋助手：`DY778LuckyBag.h/.m`、`DY778LuckyClock.h`、`DY778LuckyPolicy.h`。
  只处理当前直播间的普通免费福袋；需灯牌、送礼、付费等额外条件时跳过，
  不代为点亮、升级、关注或消费（上游原逻辑）。
- 缓存清理：`DY778CacheCleaner.h/.m`、`DY778CachePolicy.h`。
- Feed 过滤：`DY778FeedFilter.h/.m`、`DY778FeedFilterPolicy.h`
  （`experimental.skipAds`，默认关闭）。
- 播放倍速：`DY778Playback.h/.m`、`DY778PlaybackPolicy.h`、
  `DY778DefaultPlayback.m`（默认倍速 / 长按倍速 / 播放结束暂停）。
- 入口：`DY778Entry.m`（改写自上游 DY778Entry.m，只装剩余模块，
  仍在主队列重试安装并监听偏好变化）。
- 设置登记：`DY778RemainingSettings.xm`（新写，见“设置桥接”）。

## 刻意不移植的部分

DY778 的消息留存 / 编辑历史 / 撤回通知 / 消息 UI / 设置页已在第 1 批
以 DKXS* 改名前缀移植（`src/Features/MessageArchive/`），重复安装会造成
两套留存库与两套撤回标记。故未拷贝：`DY778Settings.m`、`DY778EditHistory.*`、
`DY778Recall.*`、`DY778RecallContent.*`、`DY778RecallMediaView.*`、
`DY778RecallNotifications.*`、`DY778RecallPolicy.h`、`DY778RecallReentry.h`、
`DY778EditContent.*`、`DY778EditPolicy.h`、`DY778MessageLayout.h`、
`DY778MessageUI.*`、`DY778Help.*`、`DY778ArchiveNative.*`、`DY778ArchivePolicy.h`、
`DY778MessageArchive` 已有的 `DY778ArchiveStorage` 除外（基础需要，已拷贝）。
`DY778Core.h` 里 `DY778InstallSettingsHook` / `DY778SettingsController` 的
声明保留（无调用，不链接定义，不会报错）。

## 设置桥接

DY778 模块读 DY778 专用 suite（`com.dy778.douyin`）的点分键，
DYxs 设置页写标准 defaults 的 DKXS* 键。`DY778RemainingSettings.xm` 在
%ctor 同步一次、每次改值后通过 `DKSettingsOnChange` 再同步一次，
经 `DY778Set` 钳制数值范围并发出偏好变化通知。未动过的键沿用
`DY778RegisterDefaults` 的默认值（本批全部关闭）。
布局行见 `DKSettingsLayout.m` 新增的“DY778 福袋与播放”分区（18 行）。
死键不登记：`lucky.autoPhrase` / `lucky.autoJoin` 只出现在上游默认值表里，
本 commit 的福袋代码并不读取。

## 其他改动

- `Makefile`：`DYxs_FRAMEWORKS` 增加 `WebKit`（福袋面板）与 `AVKit`（播放）。
- `control`：版本 0.6.9.2 → 0.6.9.3。
- 编译修复（与本次移植无关，同一提交顺带修）：`DKXSBatch3bSidebarMessageSearch.xm`
  补 `AWELeftSideBarModuleModel` / `AWELeftSideBarItemModel` 最小声明，
  解决 run 41512492199 的 3 个 `moduleID` / `businessType` 错误
  （ARC 下 `id` 接收者调用未声明方法会报错；上游 AwemeHeaders.h 有声明，
  本文件不 import 它，故在此补）。

## 尚未验证，必须由 CI / 真机验证

- 未在本机编译：Linux 无 Theos / iOS SDK。第一次真实编译由推送后的
  macOS 26 Action 完成；若 CI 报错，按报错修。
- 播放倍速与 DYxs 已有的悬浮倍速按钮 / PlaybackClean 同属播放控制，
  不要同时开两套倍速；Feed 过滤与 DYxs 的 ContentFilter 去广告也可能
  叠加，默认关闭的 `experimental.skipAds` 先别开。
- 福袋助手会用抖音原生能力实际参与福袋：上真机前用测试号核对，
  默认关闭，需手动开启。
