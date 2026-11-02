# DYxs 移植说明：自动消息 + ABTest（第二阶段，本地已完成，未经 CI 编译验证）

## 移植了什么（共 41 个文件）

- `src/Features/AutoMessage/`：DYads- 的自动消息 / 私聊 / 好友分享子系统，
  原 31 个文件全部改名前缀 DYYY -> DKXS，包括：
  DKXSAutoMessage、Batch、Editor、Panel、QuietHoursPanel、Hooks、
  DKXSIMService、IMConversationStore、IMHistoryReader、IMShareParser、IMSendLedger、
  DKXSFriendShareService、History、Delivery、ReturnState、BadgeView。
- `src/Features/ABTest/`：DKXSABTestHook、DKXSConstants。
- 新增移植层（不从 DYYY 全量搬运）：
  - `DKXSUtils`：只实现移植代码实际用到的 showToast / isDarkMode /
    firstAvailableViewControllerFromView，以及 DKXSNSLog 本体
    （原实现在 DYYYUtils.m，不移植会链接失败；这里用 os_log + 系统 NSLog 实现）。
  - `DKXSSettingsHelper`：只实现自动消息用到的 createSettingItem /
    createSectionWithTitle / showTextInputAlert / createSubSettingsViewController。
    DYYY 原版的依赖联动、冲突处理、图标定制不移植。
  - `DKXSAwemeHeaders.h`：DYads- AwemeHeaders.h 全量改名前缀后的副本，
    仅供移植单元使用，不与 DouyinHeaders 混 import。
- 新增 DYxs 设置入口（不 import 移植引擎头文件，走 NSClassFromString 调用，避免头文件重复声明冲突）：
  - `DKAutoMessageSettings.xm`：启用自动消息、发送提示、ID 查询关键词、
    自动消息设置页、好友分享进推荐、每次打开刷新、立即扫描、清除已刷记录。
  - `DKABTestSettings.xm`：禁止 ABTest 下发、远程配置地址、检查远程配置更新。

## 刻意改动 / 删减

- 设置键全部由 DYYY* 改为 DKXS*（例如 DKXSAutoMessageEnabled），
  旧 DYads- 用户的设置不会自动迁移到 DYxs，属新插件的干净起点。
- `DKXSAutoMessageHooks.xm` 中属于 DYYY 聊天视频布局 / 详情文案布局的 hook 已删：
  AWEAwemeDetailTableViewController 整个 hook、AWEPlayInteractionViewController 里的
  DetailCaptionLayout / ChatVideoLayout 调用。保留的只有好友分享角标、
  IM 服务捕获、Feed 绑定、好友分享插入等与自动消息直接相关的 hook。
  DYKiller 已有自己的视频 / 详情布局逻辑，硬拷那两套布局会重复布局、冲突。
- 内部类前缀 DK*（DYKiller 原有）与 DKXS*（移植）并存，这是故意的：
  全量统一前缀会断符号，插件名、包名、dylib 名已统一为 DYxs。
- DKXSConstants 的名称 / 版本已改为 DYxs / 0.6.9.2，GeoNames 错误域改为 com.dyxs。

## 本地已做的静态检查（均通过）

- 移植目录内 DYYY 字样 0 处，ChatVideoLayout / DetailCaptionLayout 引用 0 处。
- 移植文件 import 的本地头文件全部存在，无缺失。
- 系统框架需求在 DYKiller 原 Makefile 已覆盖范围内（UIKit、Photos、PhotosUI、QuartzCore 等）。
- DKXSNSLog 链接缺口已补（见上）。

## 尚未验证，必须由 CI / 真机验证

- **未在本机编译**：本机为 Linux，无 Theos / iOS SDK，无法真正编译 ObjC + UIKit + Logos。
  第一次真实编译在推送到 GitHub 后由 macOS 26 Action 完成；若 CI 报错，按报错修移植层。
- 同类 hook 叠加风险：移植的 Feed / 列表数据 hook（AWEListDataController、
  AWEHotListDataController、AWEFeedTableViewController 等）与 DYKiller 的
  ContentFilter / VideoFullscreen 已 hook 同类同方法，Logos 会按 %orig 链式调用，
  但好友分享插入与去广告过滤的先后顺序需在抖音 40.8.0 真机上实测。
- 自动消息本身会用抖音原生消息服务实际发消息：上真机前务必先用测试号、
  关闭“启用自动消息”默认状态核对（本移植保持原逻辑：默认关闭，需手动开启）。
- ABTest 远程地址默认仍为 Nathalie-Annis 的 GitHub release，信任点与审计结论一致。

## 下一步

1. 用户提供目标 GitHub 仓库并授权推送。
2. 推送 DYxs，触发 build + publish Action，打出 rootful / rootless / roothide 三种 deb。
3. 按 CI 报错修移植层；真机验证自动消息、好友分享、ABTest 三条主线后再定版。
