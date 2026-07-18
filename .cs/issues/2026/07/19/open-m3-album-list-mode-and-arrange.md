---
kind: issue
title: "M3 列表模式与整理顺序：list 渲染 + ArrangeScreen 拖拽 + custom 语义"
type: feature
status: open
created: 2026-07-19
epic: ".cs/epics/2026/07/19/album-organizer/spec.md"
---

# M3 列表模式与整理顺序：list 渲染 + ArrangeScreen 拖拽 + custom 语义

## 目标

用户能把 Invisible 首页切成列表形态（持久化、长按菜单等能力等价）；能从 ⋮ 进入"整理顺序"拖拽调整用户相册顺序，保存后首页按手动顺序显示（排序自动切为 custom）；custom 模式下置顶不浮顶但图钉角标保留（epic 决策 2）。

## 范围

- 包含：viewMode 启用（M2 已有字段）、样式面板加"列表"选项、列表渲染、ArrangeScreen（本期仅顶层作用域）、`AlbumSort.custom` 在排序面板启用、保存切换逻辑、l10n、测试。
- 不包含：合集条目（M4 在两种形态与整理列表中加入 GroupEntry）；组内整理（M4 复用本屏）。

## 归属

- 隶属 epic：`.cs/epics/2026/07/19/album-organizer/spec.md`（依赖 M1/M2）

## 背景与证据

- 目标线框：epic spec"目标界面 B/C"。
- 样式面板：`GridAppMenu.showStylePicker`（现纯列数）；首页样式入口 `home_shell.dart _pickHomeStyle`。
- 拖拽：Flutter SDK `ReorderableListView`（零新依赖，epic 架构考量）；参考现有 widget 测试风格 `test/widget/capsule_order_test.dart`。
- 锁：新路由 push 应用 Navigator 即被锁覆盖（AGENTS.md），禁止自建 Navigator。

## 现状如何工作

（以 M2 完成为前提）`_InvisibleTab` 消费 `albumShelfProvider` 得到系统卡片与已排序 entries，仅有 GridView 一种渲染；排序面板 custom 隐藏/禁用；sortIndex 全为 NULL，无写入入口。

## 影响范围

- 必须修改：`home_shell.dart`（渲染分支 + 样式面板选项 + ⋮ 加"整理顺序"）、新 `presentation/home/arrange_albums_screen.dart`、`album_list_preferences.dart`（setViewMode）、`album_query_utils.dart`（custom 启用已在 M2 就绪则仅解禁面板）、arb ×4、测试。
- 需要验证：列表形态下长按菜单/评分/照片XOR视频过滤/下拉刷新等价；custom 与自动模式往返切换顺序稳定；provider 容器重建后 viewMode 与 custom 序恢复（AGENTS.md 偏好不变量的验证方式）；锁覆盖 ArrangeScreen（现有 lock 回归思路）。
- 仍待调查：无。

## 质量目标

- 交互能力 / 用户差错防御（来源：epic 约束）：
  - 目标：整理有未保存改动时返回需确认；拖拽手柄可见可点；保存成功有反馈（SnackBar/Haptic 与现风格一致）。
  - 预期证据：widget 测试（dirty 返回弹确认）+ 手动路径。
- 可靠性（来源：epic 约束）：
  - 目标：保存 = 单事务批量写 sortIndex（M1 方法），中断不产生半序；重开 App 后 custom 顺序与 viewMode 完整恢复。
  - 预期证据：DAO 事务测试（M1 已有）+ prefs 恢复测试 + 手动杀进程验证。

## 方案判断

整理用独立编辑屏而非网格内直拖：SDK 原生、零依赖、语义清晰（编辑态/浏览态分离）；上限=马赛克内不能直接拖，触发=体验不足→引入 reorderable-grid 依赖（epic 暂不推进范围）。custom 下置顶不浮顶：手动序必须是完全序（epic 决策 2）。列表模式复用同一份 entries 数据，仅是渲染分支，杜绝两形态行为漂移。

## 实现设计

### 这次要怎么做

先把渲染层拆成"数据（shelf）→ 形态（grid|list）"两段，加列表分支；再做 ArrangeScreen 与保存链路；最后在排序面板解禁 custom 并接通"选 custom→提示整理"。

### 功能怎么分工

- 形态切换：样式面板选项 [3列, 4列, 列表]；选网格写 albumColumns+viewMode=mosaic，选列表写 viewMode=list；`_InvisibleTab` 按 viewMode 分支 GridView / ListView（行组件新建 `_ShelfListTile`，复用卡片的数据与菜单回调）。
- ArrangeScreen：入参=初始条目列表（顶层：用户区 entries；M4 传组内成员）；`ReorderableListView` + 本地工作副本；[保存] → `repo.setSortIndexes({id: index})` 单事务 → 顶层作用域时再 `prefs.setSorting([AlbumSort.custom], multiSortEnabled: false)` → pop；WillPop dirty 确认。
- 排序面板：custom 选项解禁；选中时排他（M2 校验已支持）；若当前全 NULL（从未整理）提示"进入整理顺序"快捷入口。
- ⋮ 菜单：Invisible 页签加"整理顺序"。

### 请求 / 数据怎么走

拖拽只改屏内副本 → 保存一次性落库+切偏好 → 表更新与偏好变更双触发 shelfProvider 重排 → 首页（任一形态）呈现手动序。

### 哪些边界不碰

- 系统卡片与"＋新建"不进整理列表、位置不变。
- 置顶交互本身不变（仅 custom 模式显示语义变化）。
- 不动媒体网格的任何排序/形态。

### 质量目标如何落实

- 差错防御 → dirty 确认对话框；保存按钮仅 dirty 时可用。
- 可靠性 → 单事务写；保存失败（异常）不切偏好并提示重试。

### 一步步怎么改

1. 渲染拆分 + 列表分支 + 样式面板选项 + prefs setViewMode。
2. ArrangeScreen + 保存链路。
3. 排序面板解禁 custom + 快捷入口。
4. arb ×4 + gen-l10n；`make analyze && make test`。

### 怎么确认做对

- widget：ArrangeScreen 拖拽后 onSave 收到的 index 映射正确；dirty 返回弹确认；列表形态长按菜单可用。
- 单测：custom 比较器（M2 已有）+ viewMode 编解码。
- 手动：整理→保存→两形态验证顺序；切回名称排序→再切 custom 顺序仍在；杀进程恢复。

## 验证

- `flutter test test/application/album_list_preferences_test.dart test/data/album_organizer_test.dart`：viewMode/custom 偏好恢复、顺序事务和系统相册守卫通过。
- `flutter test test/widget/app_smoke_test.dart`：首页 Invisible 主路径与锁覆盖回归通过。
- `flutter analyze`：无问题。

## 执行记录

- 已完成：Invisible 样式面板支持 3 列、4 列、列表；列表行复用同一 shelf 数据和长按菜单路径。
- 已完成：新增 SDK `ReorderableListView` 整理屏，保存前本地工作副本、脏返回确认、单事务批量写 sortIndex；顶层保存切换为 `[custom]`，组内保存不改偏好。
- 已完成：custom 排序启用，custom 模式不浮顶但保留图钉显示；顶层整理同时支持相册与合集条目并使用跨表单事务。

## 关闭回写

- epic spec：勾选本 issue；custom/置顶语义作为稳定结论记入。

## 关闭结论

- （关闭时填写）
