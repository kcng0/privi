---
kind: issue
title: "M4 合集：加入/新建/移出/重命名/解散 + GroupScreen + 组内整理"
type: feature
status: open
created: 2026-07-19
epic: ".cs/epics/2026/07/19/album-organizer/spec.md"
---

# M4 合集：加入/新建/移出/重命名/解散 + GroupScreen + 组内整理

## 目标

用户能把相册组织成合集（如漫画系列）：长按相册加入已有或新建合集；首页两种形态出现合集条目（封面+叠层标识+成员相册数），参与当前排序（名称/创建时间/成员最大评分/custom）；点开合集看到成员相册网格，可重命名、组内拖拽排序、移出成员、解散合集；解散在任何路径下不删除相册与媒体。

## 范围

- 包含：GroupView/GroupEntry 组装进 `albumShelfProvider`；合集卡片与列表行；加入合集底部面板（含新建）；GroupScreen；组内整理（复用 ArrangeScreen，组作用域）；合集长按/⋮ 菜单（重命名/整理顺序/解散）；成员菜单"移出合集"；空合集与过滤可见性规则；l10n；测试。
- 不包含：合集嵌套、合集独立评分、批量入组、封面手选（epic 暂不推进范围）。

## 归属

- 隶属 epic：`.cs/epics/2026/07/19/album-organizer/spec.md`（依赖 M1 数据层、M2 排序、M3 形态与 ArrangeScreen）

## 背景与证据

- 数据与事务：M1 的 group CRUD/dissolve/setAlbumsGroup。
- 目标线框与流程：epic spec"目标界面 A/B/D + 合集关键交互 Mermaid"。
- 可见性现规则：count==0 用户相册隐藏（`home_shell.dart` `_InvisibleTab`）；合集规则见 epic 稳定约束（0 成员空合集可见；有成员但全被过滤则隐藏）。
- 锁：GroupScreen 为普通 push 路由，自动被覆盖（AGENTS.md）。

## 现状如何工作

（以 M3 完成为前提）shelfProvider 产出 entries（仅 AlbumEntry），两种形态渲染，ArrangeScreen 支持顶层整理；数据层已具备合集全部读写能力但无 UI 消费。

## 影响范围

- 必须修改：新 `domain/models/group_view.dart`（或并入 shelf_entry.dart）、`providers.dart`（shelf 组装并入 groups：一次 listGroups + 内存按 groupId 分桶，成员 count/cover 复用既有 AlbumView，禁止 N+1）、`album_query_utils.dart`（GroupEntry 排序键：name/createdAt/max成员rating/sortIndex）、`home_shell.dart`（合集卡片/行、长按菜单、加入合集面板）、新 `presentation/home/group_screen.dart`、`arrange_albums_screen.dart`（组作用域参数，保存不切排序偏好）、arb ×4、测试。
- 需要验证：合集内成员相册的既有能力全部可用（打开媒体网格、评分、置顶含义、取消隐藏、删除——删除成员相册后组视图与计数正确）；封面失效链路（成员封面变化→组封面跟随）；照片 XOR 视频过滤下组计数与可见性；顶层整理列表包含合集条目后 M3 行为不回归。
- 仍待调查：无。

## 质量目标

- 数据完整性（来源：epic 约束）：
  - 目标：解散/删除路径在任何时序下保全相册与媒体；移出成员仅置 NULL 不触碰 membership。
  - 预期证据：M1 DAO 测试 + 本期 UI 流集成/手动验证。
- 交互能力 / 用户差错防御（来源：epic 约束）：
  - 目标：解散确认文案明示"相册将回到主页，不会删除任何内容"；不存在"连同相册删除"入口；加入面板可一步新建。
  - 预期证据：widget 测试断言文案与动作集合 + 手动路径。
- 性能效率（来源：epic 容量边界）：
  - 目标：shelf 组装 O(相册数+组数)，不因合集引入每组额外查询。
  - 预期证据：实现评审（组装函数无 per-group await）+ 大量相册手动冒烟。

## 方案判断

合集作为独立表 + 相册外键，而非"相册套相册"：避免污染 Album 不变量（coverMediaId/isSystem/membership）。组封面取"按成员顺序第一个有封面者"，不落库：零同步成本，上限=不可手选，触发=用户要求→加 coverAlbumId。组排序评分键用成员 max：直觉是"系列里最好的一卷"，计算即时无一致性负担。

## 实现设计

### 这次要怎么做

自底向上：先把 groups 并进 shelf 组装与排序（纯函数可测），再画两种形态的合集条目与菜单，再做 GroupScreen 与组内整理，最后接加入/解散流。

### 功能怎么分工

- 组装：providers 层把 albums 按 groupId 分桶 → GroupView{group, members(组内 sortIndex 序), totalCount, cover, maxRating}；顶层 entries = 未入组相册 + 合集，交 AlbumQueryUtils 排序。
- 呈现：`_MosaicTile` 合集变体（叠层图标+成员数角标）与 `_ShelfListTile` 合集行；可见性规则实现于组装处（单一来源）。
- 加入合集面板：长按相册 →"加入合集…"→ showVaultSheet 列既有合集 + "新建合集…"（命名对话框）→ `repo.addToGroup`（组内末尾）。
- GroupScreen：入参 groupId；watch shelfProvider 派生该组 GroupView；网格复用相册卡片；⋮=重命名（对话框同相册改名）/整理顺序（ArrangeScreen 组作用域）/解散（确认对话框→`repo.dissolveGroup`）；成员长按=既有菜单+移出合集；组被解散时本屏自动 pop。
- 组内整理：ArrangeScreen 传成员列表与 groupId 作用域，保存仅写成员 sortIndex。

### 请求 / 数据怎么走

一切写操作走 M1 仓库事务 → 表更新 → shelf 重建 → 首页与 GroupScreen 同源刷新（GroupScreen 无独立数据通道，杜绝双真相）。

### 哪些边界不碰

- 系统相册不可入组；合集不可嵌套；组不可评分。
- 不改变成员相册在媒体层的任何行为（membership、封面、回收站）。

### 质量目标如何落实

- 完整性 → 全部走 M1 事务方法；GroupScreen 对已删组防御（pop）。
- 差错防御 → 解散文案+确认；"删除"语义只存在于相册自身菜单。
- 性能 → 组装纯内存，无 per-group 查询；评审核对。

### 一步步怎么改

1. GroupView/GroupEntry + 组装与排序键 + 单测。
2. 两形态合集条目 + 可见性规则。
3. 加入合集面板 + 新建流。
4. GroupScreen + 组内整理 + 解散/重命名/移出。
5. arb ×4 + gen-l10n；`make analyze && make test`；epic 关闭条件的手动全流程。

### 怎么确认做对

- 单测：分桶组装（含隐藏规则/过滤计数/maxRating）；GroupEntry 各排序键。
- widget：解散确认文案；加入面板动作；GroupScreen 菜单集合。
- 手动：epic 关闭条件清单（建组→改名→组内排序→移出→解散→数据完好）。

## 验证

- `flutter test test/core/album_query_utils_test.dart test/data/album_organizer_test.dart test/data/vault_backup_service_test.dart`：组装排序键、成员顺序、解散保全与 manifest v3 往返通过。
- `make test`：146 项全量测试通过，包含首页、锁、媒体面板与导入回归。
- `flutter analyze`：无问题。

## 执行记录

- 已完成：shelf 按 groupId 一次分桶组装 `GroupView`，复用成员 `AlbumView` 的 count/cover，支持空合集可见和过滤后全空隐藏。
- 已完成：合集卡片/列表行、加入已有/新建合集、GroupScreen、重命名、组内整理、成员移出与解散确认；解散只清 groupId 并删除组行，不删除相册或媒体。
- 已完成：合集参与名称/创建时间/成员最大评分/custom 排序，组内手动顺序和顶层合集顺序均持久化。
- 已完成：成员菜单保留评分、重命名、置顶、删除和移出合集入口；组屏路由沿应用 Navigator，自动受根锁覆盖。

## 关闭回写

- epic spec：勾选本 issue；合集可见性与封面规则沉淀为稳定结论，触发 epic 关闭检查。

## 关闭结论

- （关闭时填写）
