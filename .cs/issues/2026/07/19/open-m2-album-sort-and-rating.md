---
kind: issue
title: "M2 相册排序与评分：AlbumSort/偏好/比较器 + 排序面板泛化 + 评分 UI"
type: feature
status: open
created: 2026-07-19
epic: ".cs/epics/2026/07/19/album-organizer/spec.md"
---

# M2 相册排序与评分：AlbumSort/偏好/比较器 + 排序面板泛化 + 评分 UI

## 目标

用户能给用户相册打 0–3 红心（长按菜单，卡片显示红心行），并在 Invisible 页签 ⋮ 菜单里像媒体一样配置相册排序（名称/创建时间/评分三族多级组合）；偏好持久化、重建后恢复；升级用户未动过设置时首页顺序与现状完全一致（默认名称 A–Z）。

## 范围

- 包含：`AlbumSort` 枚举、`AlbumListPreferences`（sorts/multiSortEnabled/viewMode 字段与持久化，viewMode 本期恒 mosaic）、`AlbumQueryUtils`、`AlbumShelf`/`ShelfEntry`（本期仅 AlbumEntry）、`albumShelfProvider`、排序面板内核泛化、⋮ 菜单"排序"入口（仅 Invisible 页签）、评分菜单项与卡片红心行、l10n 键、测试。
- 不包含：custom 排序的整理入口（M3）；列表渲染（M3）；合集（M4）。`AlbumSort.custom` 枚举值本期定义但面板中隐藏或禁用（无 sortIndex 编辑入口前无意义）。

## 归属

- 隶属 epic：`.cs/epics/2026/07/19/album-organizer/spec.md`（依赖 M1 已合入）
- 相关 spec：`.cs/spec/index.md`（统一语言：红心、置顶）

## 背景与证据

- 镜像范本：`lib/domain/enums.dart` MediaSort、`lib/core/utils/media_query_utils.dart`（比较器/族规则/updateSortSelection）、`lib/application/media/media_view_preferences.dart`（JSON 编解码+校验+串行写）、`lib/presentation/common/grid_app_menu.dart` showSortPicker（多级开关+优先级角标）。
- 评分复用：`lib/presentation/common/quick_rating_sheet.dart`（0–3 大按钮面板）；写入走 M1 的 `AlbumRepository.setRating`。
- 现首页排序在 `album_repository.dart:84-105`；本期把它上移。

## 现状如何工作

（以 M1 完成为前提）`_InvisibleTab` watch `albumsProvider` 得到仓库内排好序（rank+pinned+名称）的 `List<AlbumView>`，UI 分拣系统/用户卡片后渲染；⋮ 菜单只有 样式/新建相册/设置，两页签同一菜单。

## 影响范围

- 必须修改：`domain/enums.dart`、新 `application/media/album_list_preferences.dart`、新 `core/utils/album_query_utils.dart`、新 `domain/models/shelf_entry.dart`（AlbumShelf/ShelfEntry）、`application/providers.dart`（+albumShelfProvider）、`data/repositories/album_repository.dart`（`_buildViews` 移除排序、改出稳定基序）、`presentation/common/grid_app_menu.dart`（内核泛型化）、`presentation/home/home_shell.dart`（菜单按页签、watch 新 provider、评分项、卡片红心行）、4×arb + gen-l10n、测试。
- 需要验证：**媒体排序面板行为与 `test/widget/media_preferences_ui_test.dart` 必须不变**（泛化重构的回归红线）；`albumsProvider` 其余 invalidate 调用点不动；卡片 ValueKey 并入 rating 保证角标刷新。
- 仍待调查：无。

## 质量目标

- 可维护性（来源：epic 约束）：
  - 目标：相册排序全部规则单一来源 `AlbumQueryUtils`；排序面板一个内核两个薄包装；`AlbumListPreferences` 编解码/校验风格与 MediaViewPreferences 同构。
  - 预期证据：单元测试 + `make analyze`；媒体面板回归全绿。
- 兼容性/行为保持（来源：epic 决策 5）：
  - 目标：无偏好存量用户升级后首页顺序 bit 级一致（All→Fav→置顶(pinnedAt desc)→用户相册名称序→回收站）。
  - 预期证据：`album_query_utils_test` 用旧规则快照数据断言默认排序等价。

## 方案判断

排序上移而非在仓库加参数：视图策略归 application 层，与媒体分工一致，仓库保持"数据事实"职责。`AlbumSort.custom` 本期先定义后启用，避免 M3 改枚举触发偏好格式变更。红心行放名称左侧（不遮数量角标），具体像素属示意。

## 实现设计

### 这次要怎么做

先建纯函数与偏好层（可独立测试），再泛化排序面板，最后接 UI：provider 组合数据与偏好产出 `AlbumShelf`，home_shell 从"自己分拣+仓库排序"改为直接消费。

### 功能怎么分工

- `AlbumSort`（enums.dart）+ 族规则/比较器/标签/图标/选择更新（album_query_utils.dart）：custom 排他；自动模式先置顶分区（pinnedAt desc）再按 sorts 逐级比较，末级名称兜底；custom 模式单分区按 sortIndex（NULL 最后名称兜底）。
- `AlbumListPreferences`（album_list_preferences.dart）：单键 `album_list_preferences_v1` JSON；校验：非空、custom 必须单选、族唯一；默认 `[nameAsc]`+multiSort=false+viewMode=mosaic。
- `AlbumShelf` 组装（providers.dart albumShelfProvider）：watch albumsProvider + prefs → 分拣系统卡片 → 用户相册（含 count>0 过滤，规则不变）→ 排序 → entries。
- 排序面板（grid_app_menu.dart）：`_showSortPickerCore<T>`(labelOf/iconOf/familyOf/options) + `showSortPicker`(MediaSort 包装，签名不变) + `showAlbumSortPicker`。
- 评分（home_shell.dart）：长按菜单 isUser 分支加"评分"（副标题当前红心）→ `showQuickRatingSheet` → `repo.setRating`；`_MosaicTile` 名称行前插红心行。
- ⋮ 菜单：接收当前页签；Invisible 时加"排序"（副标题=当前摘要 `AlbumQueryUtils.sortsSummaryL10n`）。

### 请求 / 数据怎么走

长按评分 → 仓库写 rating → 表更新 → albumsProvider 重建 → shelfProvider 重排 → 卡片红心与顺序同步变化。排序面板改动 → prefs controller 提交（内存即时+串行落盘）→ shelfProvider 重排。

### 哪些边界不碰

- 系统卡片不可评分不可排序；"＋新建"位置固定。
- 空相册隐藏规则、照片 XOR 视频过滤、置顶交互均不变。
- 媒体排序面板对外行为不变（红线）。

### 质量目标如何落实

- 可维护性 → 泛型内核消除复制；比较器全部收进 AlbumQueryUtils（home_shell 不写一行比较逻辑）。
- 行为保持 → 默认 prefs 时 shelfProvider 输出用等价性测试钉住旧规则。

### 一步步怎么改

1. enums + AlbumQueryUtils + 单测。
2. AlbumListPreferences + 单测（镜像 media_view_preferences_test）。
3. ShelfEntry/AlbumShelf + albumShelfProvider；仓库 `_buildViews` 去排序（保稳定基序）。
4. grid_app_menu 泛化 + 媒体回归。
5. home_shell 接入：菜单/评分/红心行；arb ×4 + gen-l10n。
6. `make analyze && make test`。

### 怎么确认做对

- `test/core/album_query_utils_test.dart`：族规则、多级优先、custom 排他与 NULL 兜底、默认序=旧规则等价。
- `test/application/album_list_preferences_test.dart`：编解码/非法输入/重建恢复。
- `test/widget/media_preferences_ui_test.dart` 回归 + 新相册排序面板 widget 测试。
- 手动：评分→评分排序生效；杀进程重开偏好保留。

## 验证

- `flutter test test/core/album_query_utils_test.dart test/application/album_list_preferences_test.dart`：默认置顶/名称序等价、多级族规则、custom 排他、合集排序键与偏好重建恢复全部通过。
- `flutter test test/widget/media_preferences_ui_test.dart test/widget/app_smoke_test.dart`：媒体排序面板回归和首页卡片回归通过。
- `flutter analyze`：无问题。

## 执行记录

- 已完成：新增 `AlbumSort`、`AlbumQueryUtils`、全局 `AlbumListPreferences` 与 `AlbumShelf/ShelfEntry` 基础模型；默认 `[nameAsc]` 保持升级前首页观感。
- 已完成：排序面板抽为泛型内核，保留媒体面板签名与行为；Invisible ⋮ 增加相册排序入口。
- 已完成：相册长按评分、0–3 红心持久化和马赛克/列表数据模型中的红心显示。
- 设计无偏差；custom 在 M3 完成后已解禁并保持单选。

## 关闭回写

- epic spec：勾选本 issue；custom 启用状态与 M3 衔接说明。

## 关闭结论

- （关闭时填写）
