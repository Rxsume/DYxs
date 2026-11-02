# DYxs 合并说明（v1 脚手架）

- 底座：HierarchThurs/DYKiller 0.6.9.2（commit 261c2d5），已改名。
- 改名：TWEAK_NAME DYKiller -> DYxs；control Name DYxs，Package com.dyxs.dyxs，
  Version 保持 0.6.9.2；DYxs.plist、Makefile、工作流、脚本输出名已同步为 DYxs。
- 内部类前缀仍为 DK*（未做全量重命名，避免符号断裂）；可见名、包名、dylib 名已是 DYxs。
- 原作者署名与 MIT 许可保留在 LICENSE / README 中，Maintainer/Author 字段仍为 hierarch，
  推送到自有仓库前可再改为实际维护者。
- 尚未移植（需第二阶段）：DYads- 的自动消息 / 私聊 / 好友分享子系统（31 个文件，
  依赖 DYYYSettingsHelper、DYYYUtils、AwemeHeaders），以及 ABTest 远程配置模块。
  这些不能直接拷贝，会与 DYKiller 的 FriendClean / MessageClean / 设置体系冲突，
  需改前缀、改设置键、并在抖音 40.8.0 下实测。
- 打包：沿用 DYKiller 原有 GitHub Actions（macOS 26 + Theos），产出
  DYxs_0.6.9.2_arm-rootful.deb、DYxs_0.6.9.2_arm64-rootless.deb、
  DYxs_0.6.9.2_arm64e-roothide.deb、DYxs.dylib。
  本机为 Linux、无 Theos / iOS SDK，故本地不直接出包，须推送到 GitHub 后由 CI 打包。

## 第二阶段更新
- 自动消息 + ABTest 已按 PORT_NOTES.md 移植完成（本地静态检查通过，未经 CI 编译验证）。
