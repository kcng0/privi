# Privi

[English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文（香港）](./README.zh-HK.md)

个人使用、完全在设备上的 **Android 媒体保险库**。将照片和视频从系统相册中隐藏，支持 **1–3 颗红心**评分、相册与合集整理、**对齐 VLC 的内置播放器**或外部 **VLC**、本地保险库备份，以及**图案 / PIN + 生物识别**锁。仅支持深色主题。仅提供 APK 侧载，不使用云存储、账号或分析服务。

**作者：** [kcng0](https://github.com/kcng0) · **许可证：** [MIT](./LICENSE) · **支持：** [Buy Me a Coffee](https://buymeacoffee.com/kcng0)。

这是一个个人项目；优先保持简单，而不是堆叠功能。

---

## 安装（APK）

Privi 不发布到 Google Play。下载 Release APK 并侧载：

1. 打开最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下载 `privi-<version>.apk`（可选下载 `SHA256SUMS`）。
3. 在电脑上校验下载文件：
   ```bash
   sha256sum -c SHA256SUMS
   ```
4. 如有提示，在手机上允许浏览器或文件管理器安装未知来源应用。
5. 打开 APK 并安装。

每个 Release 都包含：

| 文件 | 用途 |
|------|------|
| `privi-<version>.apk` | 侧载安装 |
| `SHA256SUMS` / `.sha256` / `CHECKSUMS.txt` | 完整性校验 |
| **Source code（zip / tar.gz）** | GitHub 根据 tag 自动附加 |

**要求：** Android 8.0+（API 26）。可选安装 [VLC](https://www.videolan.org/) 进行外部视频播放。所有媒体都保留在设备上。

> 官方 GitHub Release APK 使用**永久 Release 签名**（各版本使用同一密钥）。首次安装新签名时，Play Protect 可能显示“未知应用”提示；确认 **仍然安装**，并保持有害应用检测开启。

### 热更新

从 **v1.0.4** 起，更新完全由用户控制。打开 **设置 → 检查更新**，先检查最新稳定版 GitHub Release，再检查当前安装版本对应的 Shorebird 热更新通道。发现新的完整 Release 时，会显示确认操作并打开其 GitHub Release 页面；有签名 Dart 补丁时，Privi 会在下载前询问。自 **v1.0.5** 起，补丁下载成功后会自动重启 Privi，使补丁立即生效。关于页面显示基础版本/构建号和已应用的补丁编号。

Android/原生代码、插件、权限、内置资源和 Flutter 引擎变化仍需要新的 APK。v1.0.3 首次加入更新器但使用自动模式；安装一次 v1.0.5 可启用需要同意的更新和自动重启。网络访问只发生在手动检查之后，保险库媒体始终留在设备上。

---

## 功能

- **Visible | Invisible** 首页：浏览系统相册文件夹或私人保险库
- **记住的马赛克/列表布局**：每个首页页签、文件夹和合集各自保存视图
- **隐藏文件夹**：从系统相册移除媒体，同时保留磁盘文件
- **一致的高清封面**：隐藏前后使用同一张 768 px 视频帧
- **稳定的日期顺序**：隐藏后文件夹仍保持原始拍摄顺序
- **红心（0–3）**、收藏、评分筛选、多重排序和拖拽手动整理
- **合集**：创建、重命名、整理成员和无损解散
- **分享**：通过系统分享面板发送选中的 Visible 或 Invisible 媒体，也可导入分享进来的图片和视频
- **内置播放器**对齐 VLC：上一首/下一首、已播放与总时长、长按 2 倍速、双击与拖动快进、时间轴帧预览，以及左侧亮度、右侧音量滑动
- **画面**：最佳适配、适应屏幕（裁切）、填满（拉伸）、原始大小和固定比例。方向跟随传感器；会话锁定在切换媒体后仍然保留
- **音轨与字幕**：选择音轨和字幕、打开外部字幕文件、调整音轨/字幕延迟，以及 Android 播放器上的 A–B 区间循环
- **画中画**：仅限当前 Android 视频。保险库保持锁定，播放不会自动切到下一项
- **外部播放列表**：VLC 和其他外部播放器只在播放完成时切到下一项。返回停留在当前项
- **图案 / PIN + 生物识别**锁、自动锁定，以及可选的 `FLAG_SECURE`（禁止截图）
- **根路由恢复锁**：覆盖所有页签和路由。只有正在追踪的媒体应用返回可以跳过重新认证
- **可校验的保险库备份**：导出和恢复媒体与元数据，并核对校验和
- 语言：跟随系统、English、简体中文、繁體中文（香港）
- 媒体保存在设备上；签名更新检查由用户主动触发

### 关键词

`android photo vault` · `hide photos from gallery` · `private gallery app` ·
`video vault` · `offline media locker` · `pattern lock gallery` ·
`biometric photo lock` · `sideload apk vault` · `flutter media vault` ·
`hide videos android` · `no cloud gallery` · `vlc private player`

GitHub topics：`flutter` `android` `photo-vault` `video-vault` `private-gallery`
`hide-photos` `biometric-lock` `privacy` `offline` `sideload` `apk` `vlc` `mit-license`

---

## 截图

截图来自当前 **Privi v1.1.0** Flutter UI，使用合成的文件夹、相册、合集和内置应用图标生成。不使用个人媒体或连接设备。播放器截图使用与 Android 内置播放器相同的公开控件，widget 测试不会启动解码器。

维护者无需 Android 设备即可重新生成：
`flutter test tool/readme_screenshots_test.dart --update-goldens`。

| Visible 马赛克 | Visible 列表 | Invisible 马赛克 |
|:--------------:|:------------:|:----------------:|
| <img src="assets/screenshots/01_visible_mosaic.png" width="200" alt="Visible 系统文件夹马赛克视图"> | <img src="assets/screenshots/02_visible_list.png" width="200" alt="Visible 系统文件夹列表视图"> | <img src="assets/screenshots/03_invisible_mosaic.png" width="200" alt="Invisible 相册和合集马赛克视图"> |

| Invisible 列表 | 合集马赛克 | 合集列表 |
|:--------------:|:--------:|:------:|
| <img src="assets/screenshots/04_invisible_list.png" width="200" alt="Invisible 相册和合集列表视图"> | <img src="assets/screenshots/05_collection_mosaic.png" width="200" alt="合集成员马赛克视图"> | <img src="assets/screenshots/06_collection_list.png" width="200" alt="合集成员列表视图"> |

| 合集管理 | 相册 | 多选 |
|:--------:|:----:|:----:|
| <img src="assets/screenshots/07_collection_management.png" width="200" alt="合集成员管理菜单"> | <img src="assets/screenshots/08_album_mosaic.png" width="200" alt="带红心评分和筛选的相册马赛克"> | <img src="assets/screenshots/09_album_selection.png" width="200" alt="选中媒体后的分享、评分和取消隐藏"> |

| 播放器 | 播放器设置 | 设置 |
|:------:|:----------:|:----:|
| <img src="assets/screenshots/10_player.png" width="200" alt="内置播放器的时间、切换、画面、音轨和画中画"> | <img src="assets/screenshots/11_player_settings.png" width="200" alt="红心、快进、倍速和方向的播放器设置"> | <img src="assets/screenshots/12_settings.png" width="200" alt="安全、显示和播放设置"> |

| 保险库备份 | 锁设置 |
|:----------:|:------:|
| <img src="assets/screenshots/13_vault_backup.png" width="200" alt="存储设置中的保险库导出和恢复"> | <img src="assets/screenshots/14_lock_setup.png" width="200" alt="图案锁设置页面"> |

- **Visible / Invisible**：文件夹、相册和合集按范围记住马赛克或列表
- **相册**：保险库媒体上的红心评分和评分筛选
- **多选**：对当前选择取消隐藏、评分、分享和删除
- **播放器**：已播放/总时长、上一首/下一首、画面模式、方向、音轨和画中画
- **播放器设置**：红心评分、双击与拖动快进、播放速度和默认方向
- **设置 / 备份 / 锁**：安全、播放、可校验的保险库导出与恢复，以及首次图案设置

---

## 开发

### 前置要求

| 工具 | 说明 |
|------|------|
| Flutter **3.44.6** | 推荐使用 FVM（`.fvmrc` 固定精确版本） |
| JDK 17+ | Android Gradle |
| Android SDK | platform **37**、build-tools、cmdline-tools，且已接受 licenses |
| 设备 / 模拟器 | Android 8.0+（API 26） |

### Ubuntu / WSL2 一键设置

```bash
git clone https://github.com/kcng0/privi.git
cd privi

# 可选：安装 Flutter、Android SDK 和 licenses
./scripts/install-toolchain.sh && source ~/.bashrc

# 生成原生脚手架、依赖和代码
./scripts/bootstrap.sh

# 在已连接设备上运行
make run
```

### 日常命令

```bash
make run       # 在已连接设备上启动
make test      # 单元测试 + widget 测试
make analyze   # 静态分析
make format    # dart format lib test
make gen       # build_runner（Drift + Riverpod）
make watch     # 代码生成 watch 模式
make apk       # 生成用于侧载的 Release APK
make help      # 列出 Make 目标
```

不使用 `make` 时，可使用 `fvm flutter …`（未安装 FVM 则使用普通 `flutter`）。

完整环境说明、故障排查和 CI 细节见 **[DEVELOPMENT.md](./DEVELOPMENT.md)**。

### 仓库结构

```
├── lib/           # Dart 源码（按功能组织）
├── test/          # 单元测试和 widget 测试
├── tool/          # README 截图生成器
├── android/       # Android 宿主工程
├── ios/           # 仓库内的 iOS 宿主；发布文件是 Android APK
├── assets/        # 品牌 / 图标 / 截图
├── scripts/       # bootstrap + 工具链安装器
├── .github/       # CI + Release 工作流
├── pubspec.yaml
├── Makefile
└── DEVELOPMENT.md
```

---

## Release 与 CI

| 工作流 | 触发条件 | 内容 |
|--------|---------|------|
| [CI](./.github/workflows/ci.yaml) | push / PR 到 `main` | format、codegen、analyze、test |
| [Release](./.github/workflows/release.yml) | tag `v*` 或手动触发 | Shorebird 基础 APK、校验和与 GitHub Release |
| [Patch](./.github/workflows/patch.yml) | 在 `main` 上手动触发 | 现有基础版本的签名 Dart 补丁 |

从干净的 `main` 创建 Release：

```bash
# 修改 pubspec.yaml 版本（例如 0.1.0+1 → 0.1.1+2），提交后执行：
git tag v0.1.1
git push origin v0.1.1
```

也可以通过 **Actions → Release APK → Run workflow** 执行。只包含 Dart 代码的修复不需要新 APK，可通过 PR 合并后运行 **Actions → Shorebird Patch**，并指定准确的基础版本（例如 `1.0.4+5`）。

---

## 支持

如果 Privi 对你有帮助，可以在这里支持开发：

**[Buy Me a Coffee](https://buymeacoffee.com/kcng0)**

## 社区

- **[Linux do](https://linux.do)**

## 许可证

[MIT](./LICENSE) — Copyright (c) 2026 [kcng0](https://github.com/kcng0)。
