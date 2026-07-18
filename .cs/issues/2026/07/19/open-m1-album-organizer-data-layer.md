---
kind: issue
title: "M1 数据层：schema v6（相册评分/顺序/合集）+ 备份 manifest v3"
type: feature
status: open
created: 2026-07-19
epic: ".cs/epics/2026/07/19/album-organizer/spec.md"
---

# M1 数据层：schema v6（相册评分/顺序/合集）+ 备份 manifest v3

## 目标

数据层完整支撑相册组织能力且对 UI 零可见变化：老库升级到 v6 后一切照旧；仓库能读写相册评分（0–3）、同级手动顺序（sortIndex）、合集及其成员关系；备份导出携带全部新元数据、导入向后兼容 v1/v2 老备份。

## 范围

- 包含：Drift 表/迁移/查询、域模型、AlbumRepository 新方法、vault 备份 manifest v3、迁移与 DAO 与备份往返测试、codegen 产物（database.g.dart、drift_schemas v6、generated_migrations v6）。
- 不包含：任何 presentation/application 层改动；排序枚举与比较器（M2）；UI（M2–M4）。

## 归属

- 隶属 epic：`.cs/epics/2026/07/19/album-organizer/spec.md`
- 相关 spec：`.cs/spec/index.md`（架构落点 / 质量约束）

## 背景与证据

- 现行迁移风格：`lib/data/db/database.dart` schemaVersion=5，`onUpgrade` if-链 + 手写 `ALTER TABLE`（PRAGMA table_info 幂等检查）+ `beforeOpen` 安全网（`_ensureAlbumPinnedAtColumn` 为范本）。
- 备份是**逐字段手工序列化**：`lib/data/services/vault_backup_service.dart` manifest version 2，albums 只导出 id/name/isSystem/coverMediaId/createdAt/systemKind/pinnedAt；导入端 `version > 2 → throw`（`:138`）。不扩展则新元数据在备份恢复后**静默丢失**。
- 事务惯例：引用完整性手工维护（`deleteUserAlbum` 同事务清 membership；`moveMemberships` 同事务清封面引用）。
- 迁移测试链：`drift_schemas/drift_schema_v2..v5.json` + `test/generated_migrations/schema_v2..v5.dart` + `test/data/database_migration_test.dart`（drift_dev schema dump/generate 工具链）。

## 现状如何工作

打开 DB 时 Drift 按 `schemaVersion` 走 `onUpgrade` 链，`beforeOpen` 再做幂等修补与索引创建。`Albums` 表只有 id/name/isSystem/coverMediaId/createdAt/systemKind/pinnedAt；相册相关写路径全部经 `AlbumRepository` → `AppDatabase` 查询方法。备份导出把 active+recycle 媒体文件拷入目标目录并写 manifest JSON；导入按 version 分支恢复相册（`_restoreV2Albums`：id 校验、冲突检测、`insertWithId`）再恢复 membership。

## 影响范围

- 必须修改：`lib/data/db/tables.dart`、`lib/data/db/database.dart`（版本、迁移、新查询）、`lib/data/db/database.g.dart`（regen）、`lib/domain/models/album.dart`、新 `lib/domain/models/album_group.dart`、`lib/data/repositories/album_repository.dart`、`lib/data/services/vault_backup_service.dart`、`drift_schemas/drift_schema_v6.json`、`test/generated_migrations/`（+v6）、`test/data/database_migration_test.dart`、`test/data/vault_backup_service_test.dart`、新 DAO 测试文件。
- 需要验证：`test/data/album_cover_validity_test.dart`（新列不破坏封面校验）；`watchAlbumViewsReactive` 现行为不变（本 issue 仅把 `albumGroups` 加进 TableUpdateQuery）；导入管线 `getOrCreateUserAlbumByName`（新相册 sortIndex/groupId=NULL 语义自然成立）。
- 仍待调查：drift_dev schema dump/generate 的确切命令行参数（按 v5 产物与 drift_dev 文档核对）。

## 质量目标

- 可靠性 / 数据完整性（来源：epic 约束）：
  - 目标：v5 库升级 v6 后行数与既有字段值不变、新列取默认值；解散合集后成员相册与媒体完好；备份"导出→清库→导入"往返保全 rating/sortIndex/groupId/合集。
  - 预期证据：迁移测试（v5 数据 → v6 断言）；DAO 事务测试；备份往返测试 + v2 老 manifest 兼容导入测试。
- 可维护性（来源：epic 约束）：
  - 目标：迁移/事务/防御风格与既有代码不可区分（PRAGMA 检查、beforeOpen 安全网、仓库边界 clamp）。
  - 预期证据：`make analyze` 零告警；评审对照既有范本。

## 方案判断

一次迁移携带全部三列与合集表（epic 决策 4），换取用户单次升级；不加 SQL 外键、事务手工维护引用（沿项目惯例，降低 ALTER 复杂度）。有界简化：**sortIndex 不做迁移回填**（NULL=未整理，比较器兜底名称序）；上限=用户从未整理时 custom≈名称序；触发=用户困惑 → 升级为按当前显示序回填。

## 实现设计

### 这次要怎么做

按"表 → 迁移 → 域模型 → 仓库方法 → 备份 → 测试"顺序推进，每步保持全绿。全程不触碰 UI 消费面，`watchAlbumViewsReactive` 的对外行为（排序结果）不变。

### 功能怎么分工

- 表定义（tables.dart）：`Albums` 加 `rating integer withDefault(0)`、`sortIndex integer nullable`、`groupId text nullable`；新 `AlbumGroups` 表（`@DataClassName('AlbumGroupRow')`：id TEXT PK、name、createdAt、sortIndex nullable）。
- 迁移（database.dart）：`schemaVersion → 6`；`onUpgrade` 加 `if (from < 6) await _ensureAlbumOrganizerSchema();`；`beforeOpen` 安全网并入同方法。SQL：三条 `ALTER TABLE albums ADD COLUMN ...`（rating `INTEGER NOT NULL DEFAULT 0`、sort_index `INTEGER NULL`、group_id `TEXT NULL`，均先查 PRAGMA）+ `CREATE TABLE IF NOT EXISTS album_groups (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL, sort_index INTEGER NULL)`；`@DriftDatabase(tables:)` 加 `AlbumGroups`。
- 新查询（database.dart，沿现有分区注释风格）：
  - `updateAlbumRating(id, rating)`：clamp 0–3 且 `isSystem = false` 守卫；
  - `setAlbumSortIndexes(Map<String,int>)`：单事务批量写；
  - `setAlbumsGroup(List<String> albumIds, String? groupId)`：单事务；
  - AlbumGroups CRUD：insert / rename / `setGroupSortIndexes` / `dissolveAlbumGroup(id)`（单事务：成员 group_id 置 NULL + 删组行）/ `getAllAlbumGroups()`。
- 域模型：`Album` 加 rating/sortIndex/groupId 三字段；新 `AlbumGroup`{id,name,createdAt,sortIndex}。（GroupView/ShelfEntry 属 M2/M4 消费面，本 issue 不建。）
- 仓库（album_repository.dart）：`_mapAlbum` 带新字段；镜像上述方法（setRating/setSortIndexes/addToGroup/removeFromGroup/createGroup/renameGroup/dissolveGroup/listGroups/setGroupSortIndexes）；`insertWithId` 加可选 rating/sortIndex/groupId（备份恢复用）；`watchAlbumViewsReactive` 的 `TableUpdateQuery.onAllTables` 加 `_db.albumGroups`——**排序逻辑一行不动**。
- 备份（vault_backup_service.dart）：manifest `version: 3`；albums 条目加 `rating/sortIndex/groupId`；顶层加 `albumGroups` 数组（id/name/createdAt/sortIndex）；导入：版本上限放宽到 3，先恢复合集（id 走 `_validatedId`，同名冲突沿 `_restoreV2Albums` 风格），再恢复相册（groupId 指向不存在的组 → 防御置 NULL）；v1/v2 老备份照常导入、新字段取缺省。

### 请求 / 数据怎么走

UI（未来）→ Repository 方法（clamp/守卫/事务组合）→ AppDatabase 查询 → 表更新通知 → `watchAlbumViewsReactive` 防抖重建 → 首页流。备份导出读全表快照写 JSON；导入按 manifest 版本分支重建行。

### 哪些边界不碰

- 系统相册永不获得 rating/groupId（守卫 + 上层不提供入口）。
- 不改 `_buildViews` 排序、不动 MediaItems 相关任何路径、不动 UI。
- 老 App 导入 v3 备份仍被版本校验拒绝（既有行为）。

### 质量目标如何落实

- 数据完整性 → 迁移幂等（PRAGMA 检查 + 安全网）；所有多行写与引用清理单事务；仓库边界 clamp 与 isSystem 守卫；备份导入端逐字段防御校验。
- 可维护性 → 每处新增都指向一个既有范本（迁移=\_ensureAlbumPinnedAtColumn，事务=deleteUserAlbum，恢复=\_restoreV2Albums），不引入新风格。

### 一步步怎么改

1. tables.dart 加列/表 → `make gen` regen database.g.dart。
2. database.dart：版本+迁移+安全网+新查询。
3. drift_dev schema dump 出 `drift_schema_v6.json`，schema generate 更新 `test/generated_migrations/`（先核对 v5 的生成方式）。
4. 域模型与仓库方法。
5. 备份导出/导入扩展。
6. 测试补齐（见下）→ `make analyze && make test` 全绿。

### 怎么确认做对

- 迁移测试：用 schema_v5 建库灌数据 → 升 v6 → 断言旧值保留、新列默认（扩展 `database_migration_test.dart`）。
- DAO 测试（新 `test/data/album_organizer_test.dart`）：rating clamp 与系统相册守卫；setSortIndexes 事务原子性；建组/入组/移出/改名/解散；解散后相册与媒体行完好、groupId 全 NULL。
- 备份测试（扩展 `vault_backup_service_test.dart`）：v3 往返保全三字段与合集；v2 老 manifest 导入成功且新字段缺省；损坏 groupId 防御置 NULL。
- 回归：全量 `make test`（含封面校验、导入管线、锁生命周期）。

## 验证

- `dart run drift_dev schema dump lib/data/db/database.dart drift_schemas/drift_schema_v6.json`：生成 v6 schema。
- `dart run drift_dev schema generate drift_schemas test/generated_migrations`：生成 v6 migration helper。
- `flutter test test/data/database_migration_test.dart`：v2/v3/v4/v5 → v6 全部通过，旧字段保留且新列为默认值。
- `flutter test test/data/album_organizer_test.dart test/data/vault_backup_service_test.dart`：评分 clamp、事务入组/解散、缺失组错误、manifest v3 往返与 v1 兼容全部通过。
- `flutter analyze`：无问题。

## 执行记录

- 已完成：`Albums` 增加 `rating/sortIndex/groupId`，新增 `AlbumGroups`，schemaVersion 提升至 6，并把幂等安全网接入 `beforeOpen`。
- 已完成：新增评分、同级顺序、入组/移出、合集 CRUD、解散和跨相册/合集排序写入事务；删除相册 membership 清理也纳入事务。
- 已完成：`Album`/`AlbumGroup` 域模型与 Repository 映射；稳定基序从 Repository 移除，保留响应式表更新。
- 已完成：备份 manifest v3 导出三项相册元数据与 `albumGroups`，导入支持 v1/v2/v3，并对悬挂 groupId 置空。
- 设计无偏差；新增 manifest v3 的显式 group-id 保留逻辑与事务 API 是为满足往返和完整性关闭契约所必需。

## 关闭回写

- epic spec：`当前推进` 勾选本 issue，沉淀迁移/备份格式结论。
- notes：如 drift_dev schema 工具链有坑，另记 `.cs/notes/`。

## 关闭结论

- （关闭时填写）
