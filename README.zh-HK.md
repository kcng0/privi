# Privi

[English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文（香港）](./README.zh-HK.md)

個人使用、完全在裝置上的 **Android 媒體保險庫**。將相片和影片從系統相簿隱藏，支援 **1–3 顆紅心**評分、相簿與合集整理、**對齊 VLC 的內置播放器**或外置 **VLC**、本地保險庫備份，以及**圖案 / PIN + 生物識別**鎖。只支援深色主題。只提供 APK 側載，不使用雲端儲存、帳戶或分析服務。

**作者：** [kcng0](https://github.com/kcng0) · **授權條款：** [MIT](./LICENSE) · **支持：** [Buy Me a Coffee](https://buymeacoffee.com/kcng0)。

這是一個個人專案；優先保持簡單，而不是堆疊功能。

---

## 安裝（APK）

Privi 不發佈到 Google Play。下載 Release APK 並側載：

1. 開啟最新的 **[Release](https://github.com/kcng0/privi/releases/latest)**。
2. 下載 `privi-<version>.apk`（可選下載 `SHA256SUMS`）。
3. 在電腦上校驗下載檔案：
   ```bash
   sha256sum -c SHA256SUMS
   ```
4. 如有提示，在手機上允許瀏覽器或檔案管理器安裝未知來源應用程式。
5. 開啟 APK 並安裝。

每個 Release 都包含：

| 檔案 | 用途 |
|------|------|
| `privi-<version>.apk` | 側載安裝 |
| `SHA256SUMS` / `.sha256` / `CHECKSUMS.txt` | 完整性校驗 |
| **Source code（zip / tar.gz）** | GitHub 按 tag 自動附加 |

**要求：** Android 8.0+（API 26）。可選安裝 [VLC](https://www.videolan.org/) 進行外置影片播放。所有媒體都保留在裝置上。

> 官方 GitHub Release APK 使用**永久 Release 簽署**（各版本使用同一密鑰）。首次安裝新簽署時，Play Protect 可能顯示「未知應用程式」提示；確認 **仍然安裝**，並保持有害應用程式偵測開啟。

### 熱更新

由 **v1.0.4** 起，更新完全由用戶控制。開啟 **設定 → 檢查更新**，先檢查最新穩定版 GitHub Release，再檢查目前安裝版本對應的 Shorebird 熱更新頻道。發現新的完整 Release 時，會顯示確認操作並開啟其 GitHub Release 頁面；有簽署 Dart 修補程式時，Privi 會在下載前詢問。由 **v1.0.5** 起，修補程式下載成功後會自動重新啟動 Privi，使修補程式立即生效。關於頁面會顯示基礎版本/建置編號和已套用的修補程式編號。

Android/原生程式碼、插件、權限、內置資源和 Flutter 引擎變更仍需要新的 APK。v1.0.3 首次加入更新器但使用自動模式；安裝一次 v1.0.5 可啟用需要同意的更新和自動重新啟動。網絡存取只發生在手動檢查之後，保險庫媒體始終留在裝置上。

---

## 功能

- **Visible | Invisible** 首頁：瀏覽系統相簿資料夾或私人保險庫
- **記住的馬賽克/列表版面**：每個首頁頁籤、資料夾和合集各自保存檢視
- **隱藏資料夾**：從系統相簿移除媒體，同時保留磁碟檔案
- **一致的高清封面**：隱藏前後使用同一張 768 px 影片幀
- **穩定的日期順序**：隱藏後資料夾仍保持原始拍攝順序
- **紅心（0–3）**、收藏、評分篩選、多重排序和拖曳手動整理
- **合集**：建立、重新命名、整理成員和無損解散
- **分享**：透過系統分享面板傳送選中的 Visible 或 Invisible 媒體，也可匯入分享進來的圖片和影片
- **內置播放器**對齊 VLC：上一首/下一首、已播放與總時長、長按 2 倍速、雙擊與拖動快進、時間軸幀預覽，以及左側亮度、右側音量滑動
- **畫面**：最佳適應、適應螢幕（裁切）、填滿（拉伸）、原始大小和固定比例。方向跟隨感應器；工作階段鎖定在切換媒體後仍然保留
- **音軌與字幕**：選擇音軌和字幕、開啟外部字幕檔案、調整音軌/字幕延遲，以及 Android 播放器上的 A–B 區間循環
- **子母畫面**：只限目前 Android 影片。保險庫保持鎖定，播放不會自動切到下一項
- **外置播放清單**：VLC 和其他外置播放器只在播放完成時切到下一項。返回停留在目前項目
- **圖案 / PIN + 生物識別**鎖、自動鎖定，以及可選的 `FLAG_SECURE`（禁止截圖）
- **根路由恢復鎖**：覆蓋所有頁籤和路由。只有正在追蹤的媒體應用程式返回可以跳過重新認證
- **可校驗的保險庫備份**：匯出和恢復媒體與元資料，並核對校驗和
- 語言：跟隨系統、English、简体中文、繁體中文（香港）
- 媒體儲存在裝置上；簽署更新檢查由用戶主動觸發

### 關鍵字

`android photo vault` · `hide photos from gallery` · `private gallery app` ·
`video vault` · `offline media locker` · `pattern lock gallery` ·
`biometric photo lock` · `sideload apk vault` · `flutter media vault` ·
`hide videos android` · `no cloud gallery` · `vlc private player`

GitHub topics：`flutter` `android` `photo-vault` `video-vault` `private-gallery`
`hide-photos` `biometric-lock` `privacy` `offline` `sideload` `apk` `vlc` `mit-license`

---

## 截圖

截圖來自目前 **Privi v1.1.0** Flutter UI，使用合成的資料夾、相簿、合集和內置應用程式圖示生成。不使用個人媒體或連接裝置。播放器截圖使用與 Android 內置播放器相同的公開控制項，widget 測試不會啟動解碼器。

維護者無需 Android 裝置即可重新生成：
`flutter test tool/readme_screenshots_test.dart --update-goldens`。

| Visible 馬賽克 | Visible 列表 | Invisible 馬賽克 |
|:--------------:|:------------:|:----------------:|
| <img src="assets/screenshots/01_visible_mosaic.png" width="200" alt="Visible 系統資料夾馬賽克檢視"> | <img src="assets/screenshots/02_visible_list.png" width="200" alt="Visible 系統資料夾列表檢視"> | <img src="assets/screenshots/03_invisible_mosaic.png" width="200" alt="Invisible 相簿和合集馬賽克檢視"> |

| Invisible 列表 | 合集馬賽克 | 合集列表 |
|:--------------:|:--------:|:------:|
| <img src="assets/screenshots/04_invisible_list.png" width="200" alt="Invisible 相簿和合集列表檢視"> | <img src="assets/screenshots/05_collection_mosaic.png" width="200" alt="合集成員馬賽克檢視"> | <img src="assets/screenshots/06_collection_list.png" width="200" alt="合集成員列表檢視"> |

| 合集管理 | 相簿 | 多選 |
|:--------:|:----:|:----:|
| <img src="assets/screenshots/07_collection_management.png" width="200" alt="合集成員管理選單"> | <img src="assets/screenshots/08_album_mosaic.png" width="200" alt="帶紅心評分和篩選的相簿馬賽克"> | <img src="assets/screenshots/09_album_selection.png" width="200" alt="選中媒體後的分享、評分和取消隱藏"> |

| 播放器 | 播放器設定 | 設定 |
|:------:|:----------:|:----:|
| <img src="assets/screenshots/10_player.png" width="200" alt="內置播放器的時間、切換、畫面、音軌和子母畫面"> | <img src="assets/screenshots/11_player_settings.png" width="200" alt="紅心、快進、倍速和方向的播放器設定"> | <img src="assets/screenshots/12_settings.png" width="200" alt="安全、顯示和播放設定"> |

| 保險庫備份 | 鎖設定 |
|:----------:|:------:|
| <img src="assets/screenshots/13_vault_backup.png" width="200" alt="儲存設定中的保險庫匯出和恢復"> | <img src="assets/screenshots/14_lock_setup.png" width="200" alt="圖案鎖設定頁面"> |

- **Visible / Invisible**：資料夾、相簿和合集按範圍記住馬賽克或列表
- **相簿**：保險庫媒體上的紅心評分和評分篩選
- **多選**：對目前選擇取消隱藏、評分、分享和刪除
- **播放器**：已播放/總時長、上一首/下一首、畫面模式、方向、音軌和子母畫面
- **播放器設定**：紅心評分、雙擊與拖動快進、播放速度和預設方向
- **設定 / 備份 / 鎖**：安全、播放、可校驗的保險庫匯出與恢復，以及首次圖案設定

---

## 開發

### 前置要求

| 工具 | 說明 |
|------|------|
| Flutter **3.44.6** | 建議使用 FVM（`.fvmrc` 固定精確版本） |
| JDK 17+ | Android Gradle |
| Android SDK | platform **37**、build-tools、cmdline-tools，並已接受 licenses |
| 裝置 / 模擬器 | Android 8.0+（API 26） |

### Ubuntu / WSL2 一鍵設定

```bash
git clone https://github.com/kcng0/privi.git
cd privi

# 可選：安裝 Flutter、Android SDK 和 licenses
./scripts/install-toolchain.sh && source ~/.bashrc

# 生成原生腳手架、依賴和程式碼
./scripts/bootstrap.sh

# 在已連接裝置上執行
make run
```

### 日常命令

```bash
make run       # 在已連接裝置上啟動
make test      # 單元測試 + widget 測試
make analyze   # 靜態分析
make format    # dart format lib test
make gen       # build_runner（Drift + Riverpod）
make watch     # 程式碼生成 watch 模式
make apk       # 生成用於側載的 Release APK
make help      # 列出 Make 目標
```

不使用 `make` 時，可使用 `fvm flutter …`（未安裝 FVM 則使用普通 `flutter`）。

完整環境說明、故障排查和 CI 細節見 **[DEVELOPMENT.md](./DEVELOPMENT.md)**。

### 倉庫結構

```
├── lib/           # Dart 原始碼（按功能組織）
├── test/          # 單元測試和 widget 測試
├── tool/          # README 截圖生成器
├── android/       # Android 宿主工程
├── ios/           # 倉庫內的 iOS 宿主；發佈檔案是 Android APK
├── assets/        # 品牌 / 圖示 / 截圖
├── scripts/       # bootstrap + 工具鏈安裝器
├── .github/       # CI + Release 工作流
├── pubspec.yaml
├── Makefile
└── DEVELOPMENT.md
```

---

## Release 與 CI

| 工作流 | 觸發條件 | 內容 |
|--------|---------|------|
| [CI](./.github/workflows/ci.yaml) | push / PR 到 `main` | format、codegen、analyze、test |
| [Release](./.github/workflows/release.yml) | tag `v*` 或手動觸發 | Shorebird 基礎 APK、校驗和與 GitHub Release |
| [Patch](./.github/workflows/patch.yml) | 在 `main` 上手動觸發 | 現有基礎版本的簽署 Dart 修補程式 |

從乾淨的 `main` 建立 Release：

```bash
# 修改 pubspec.yaml 版本（例如 0.1.0+1 → 0.1.1+2），提交後執行：
git tag v0.1.1
git push origin v0.1.1
```

也可以透過 **Actions → Release APK → Run workflow** 執行。只包含 Dart 程式碼的修復不需要新 APK，可透過 PR 合併後執行 **Actions → Shorebird Patch**，並指定準確的基礎版本（例如 `1.0.4+5`）。

---

## 支援

如果 Privi 對你有幫助，可以在這裡支持開發：

**[Buy Me a Coffee](https://buymeacoffee.com/kcng0)**

## 社群

- **[Linux do](https://linux.do)**

## 授權條款

[MIT](./LICENSE) — Copyright (c) 2026 [kcng0](https://github.com/kcng0)。
