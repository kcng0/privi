---
kind: epic
title: "iOS 平台集成"
status: active
created: 2026-07-19
---

# iOS 平台集成

## 这个 Epic 要改变什么

把 Privi 从 Android-only 的实现形态改为 Android 与 iOS 都有明确平台
adapter 的本地媒体保险库。Flutter 业务、锁覆盖层、数据库、相册与评分继续
共用；Visible Library、Hide/Restore、隐私能力、分享入口、外部播放和更新行为
通过平台 seam 组合，不让调用方学习 MediaStore、PhotoKit 或平台路径规则。

本 Epic 不把“存在 iOS target”当作支持完成。只有 iOS 的 Hide、Restore、锁、
分享、Photos 权限与数据恢复在真机门禁通过后，才可把 iOS 写成当前稳定能力。

## 为什么现在做

兼容性审计确认可复用的 Flutter 主体已经足够多，但现有 D5 隐藏与恢复建立在
Android shared storage、`.nomedia` 和 MediaStore 上。若直接生成 iOS target，
会得到可启动但核心旅程失败的壳。平台接入需要跨 Dart orchestration、native
host、隐私、分享扩展与发布验证，适合由一个活规格约束其演进。

## 关联 Project Spec

- `.cs/spec/index.md`：当前事实仍是 Android-only；本 Epic 准备改变“当前版本不做
  iOS 发布”的边界，但在关闭前不提前改写该事实。

## 当前方案

平台差异集中在 composition root 与两个主要 seam：

```text
                 shared Flutter application
                           |
            +--------------+---------------+
            |                              |
     VisibleLibrary                  VaultWorkflow
 permission / albums / assets        hide / restore
            ^                              ^
            |                              |
   +--------+--------+            +--------+--------+
   |                 |            |                 |
Android adapter   iOS adapter   Android adapter   iOS adapter
MediaStore/photo  PhotoKit      D5 move/purge    private vault/PhotoKit
```

Android adapter 包装现有实现并保留 D5 shared vault、`.nomedia`、MediaStore
清理、原 channel 名与设备行为。iOS adapter 使用 PhotoKit 资源身份和 app-private
vault：Hide 必须先 materialize 并验证私有副本，再请求删除 Photos 源；Restore
必须先创建并验证 Photos asset，再删除 vault 数据。任何未验证副本、缺失 native
method 或源仍存在都不得转换为成功。

iCloud-only 原始资源首版返回明确 `notLocallyAvailable`，不自动下载。iOS 默认
内置播放器，外部播放器能力明确为 unsupported。iOS 隐私 adapter 保护
app-switcher snapshot 并报告无法保证阻止 screenshot。分享附件必须由 Share
Extension 先复制到 App Group durable staging，再交给共用导入队列。

## 需求变化

- Visible 页签在 iOS 显式区分 full、limited、denied/restricted 权限，不把 limited
  当作 full。
- Hide/Restore 的输入身份不再要求是 Android absolute path；平台 asset ID 与
  app-owned staged file 都是明确来源。
- iOS Hide 在用户拒绝删除 Photos 源时报告 `sourceStillPresent`，保留可恢复的私有
  副本，不显示为隐藏成功。
- iOS Restore 只有 Photos creation 可重新读取后才清理 vault 数据。
- Android 用户可见行为、文案与存储位置保持不变。

## 架构考量

- `VaultWorkflow.hide/restore` 是深模块接口；materialize、digest、PhotoKit change
  request、MediaStore purge 与 crash recovery 留在 adapter 实现内部。
- `VisibleLibrary.permissionState/collections/assets` 是独立只读模块，避免把权限、
  列表与 mutation 混成大接口。
- 平台选择只发生在 composition root。presentation、controller 与 repository 不得
  新增分散的 `Platform.isIOS` 分支。
- Android adapter 复用当前 pipeline，而不是重写一套近似行为；characterization
  tests 保护其组合和结果。
- iOS native channel 用 typed domain outcomes 返回失败，不吞掉原始 diagnostics；
  Dart 层只把 outcome code 映射为本地化界面状态。
- `originalPath` 保留为 Android restore 与备份兼容字段；iOS source identity 使用
  独立 platform ID，不伪装成文件路径。

## 质量约束与取舍

- **兼容性 / 共存性**：Android release 的 D5 storage、MediaStore、分享、播放、
  更新与锁行为必须通过现有全测和 Android build；平台 seam 不改变 Android
  channel contract。
- **可靠性 / 可恢复性**：Hide 与 Restore 的破坏性步骤必须在 destination 验证后
  发生；失败结果保留足够状态重试，不删除唯一副本。
- **信息安全性 / 保密性与完整性**：iOS 私有媒体只落在 app-private/App Group
  staging；共享 staging 消费后清理；iOS capability 不虚假声称阻止 screenshot。
- **可维护性 / 模块化与可测试性**：调用方通过相同 interface 使用 Android、iOS
  与 test adapter；平台实现只在 composition 与 adapter 目录可见。
- **交互能力 / 自描述性**：limited access、cloud-only、source still present、
  unsupported external playback 与 restart-required 都有明确、可本地化结果。

## 统一语言

- **Visible asset reference**：平台不透明的媒体身份；Android 可关联 MediaStore，
  iOS 关联 PhotoKit local identifier，不等同于 durable file path。
- **Vault copy**：应用拥有且通过完整性验证的私有媒体副本。
- **Source still present**：Vault copy 已完成，但系统相册源尚未删除；不是 Hide
  success。
- **Platform seam**：调用方可不修改而替换 Android/iOS 行为的 interface 位置。

## 当前推进

### 可推进范围

- 固定 Android composition 与 D5 workflow 的 characterization tests。
- 建立 platform composition、Visible Library、Vault Workflow、privacy、restart 与
  external playback capability seams。
- 实现 Android adapters，并让现有 Android 路径从 adapter 进入。
- 实现 iOS PhotoKit channel 与 app-private vault、Info.plist、entitlements、Share
  Extension/App Group staging。
- 补齐 host 可执行的 Dart/interface tests、静态检查和 Android build 回归。

### 直接推进

- 本 Epic 按用户明确请求直接推进，不另建重复职责 issue；实现结果和验证证据
  持续写回本节。
- 已建立 iOS Runner、PhotoKit/隐私 native channel、Share Extension、App Group
  entitlements 与 Swift Package Manager 项目配置；Android host 与原 channel 保留。
- Flutter 生成的 hosted Swift package 路径包含 package 版本；已将
  `receive_sharing_intent` 固定为 `1.9.0`，并让 Share Extension 的 local package
  reference 指向同版本目录，避免 Xcode 在 macOS 上解析到不存在的无版本路径。
- 已由 composition root 选择 Visible Library、Vault Workflow、Vault Access、Privacy
  Shield、Share Source Stager、external playback、restart 与 binary release source
  adapters；presentation 不直接判断 iOS。
- iOS Hide/Restore 使用 PhotoKit identity、app-private vault 与 SHA-256 完整性验证；
  删除拒绝、cloud-only、删除后数据库标记失败、restore cleanup 失败和 staging cleanup
  失败均保留可重试状态，不把 partial result 报告为成功。
- Visible Library capability 明确隔离 iOS All collection、limited notice 与 mixed-media
  pagination；Android 继续排除 virtual All/Recents，并保持原 permission 与 snackbar
  文案。
- 数据库升级到 v7，备份 manifest 升级到 v4；Android path 保留为历史/恢复字段，
  PhotoKit identity 使用独立字段，跨平台恢复不复用 foreign library identity。

### Host 验证证据

- `flutter pub get`：通过；Linux 无 Xcode，生成的 plugin metadata 不能替代 macOS
  Swift Package Manager 集成验证。
- `dart run build_runner build --delete-conflicting-outputs`：通过并写出 122 个输出；
  当前 build_runner 提示该旧参数已移除并忽略。
- `dart format --output=none --set-exit-if-changed lib test`：通过，179 个文件无变化。
- `flutter analyze`：通过，`No issues found`。
- `timeout 180s flutter test`：通过，185 tests passed；包含 PhotoKit/Share fault
  injection、platform capability、v2-v6 到 v7 migration 与 Android 既有回归。
- `flutter test test/data/ios_host_configuration_test.dart`：通过；一致性测试解析
  plist/entitlements，并锁定 App Group、bundle ID、URL scheme、SceneDelegate、Share
  Extension、版本化 SPM package path、target wiring、embed phase 顺序与 native channel。
- Ruby `REXML` 静态解析：所有 plist、entitlements、workspace 与 scheme XML 通过；
  当前环境没有 `xmllint`，因此使用标准库 XML parser 执行等价语法检查。
- `timeout 240s flutter build apk --debug`：通过，产物为
  `build/app/outputs/flutter-apk/app-debug.apk`。
- `git diff --check`：通过。

### 剩余阻碍

- 当前 Linux/WSL 环境没有 Xcode、iOS simulator 或 physical iOS device；archive、
  signing、PhotoKit、Face ID、Share Extension、iCloud 与 snapshot 行为必须在
  macOS/真机完成，不能由 host tests 替代。
- iOS Swift Package Manager plugin resolution 也必须在安装 Xcode 15+ 的 macOS
  重新执行 `flutter pub get` 后确认；Linux 生成的 plugin metadata 不构成证据。

## 暂不推进范围

- iCloud original 自动下载；首版只给出 `notLocallyAvailable`。
- iOS external-player 临时导出；首版使用内置播放器。
- 自动提交、推送、App Store/TestFlight 发布与 signing secrets 配置。

## 未确认问题

- iOS distribution 最终使用 App Store/TestFlight 还是受控私有分发：不影响本轮
  platform code，但影响 Epic 关闭前的 release gate。
- App Group 与 signing Team 的最终 production identifiers：代码先使用与 bundle
  ID 对齐的占位 identifier，macOS signing 时必须替换并确认。

## 关闭条件

- Android 全量 tests、analyze、format 与 build 通过，现有 D5 行为未回归。
- iOS Xcode archive 在 macOS 成功，所有插件、Runner 与 Share Extension 可签名。
- 真机覆盖 full/limited/denied Photos 权限、本地与 iCloud-only asset、Hide 删除
  拒绝、Restore 恢复、冷/热分享、锁覆盖层、Face ID、app-switcher snapshot。
- Hide/Restore 故障注入证明不会删除唯一副本或把 partial result 报告为成功。
- 用户明确确认 Epic 关闭后，再将稳定 iOS 能力毕业到 project spec。

## 合并回 Project Spec 的候选

- 当前支持平台、每个平台的 Hide/Restore 语义与明确 capability 差异。
- platform composition 与 Vault/Visible Library seams 的稳定架构约束。
- iOS app-private vault、PhotoKit identity、Share staging 和 privacy capability 边界。

## 关闭回写

- 状态：保持 `active`，直到 macOS/真机门禁和用户关闭确认完成。
- 合并位置：待关闭时更新 `.cs/spec/index.md`。
- Vision 同步：当前 `.cs/vision/index.md` 仍是未填充模板，无可毕业来源。
- 保留材料：两份 iOS 审计与本 Epic 保存平台差异、验证限制和取舍证据。

## 相关材料

- `docs/05-review/ios-platform-compatibility-audit.md`：需要确认当前不兼容证据与
  风险时阅读。
- `docs/05-review/ios-platform-adaptation-review.md`：实现 seam、平台语义和阶段门禁
  的设计来源。
