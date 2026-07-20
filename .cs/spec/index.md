# Project Spec

## 这个项目是什么

privi 是一个纯本地的 Android 私密媒体保险库（Flutter 个人应用，不发布 pub.dev）。它把照片/视频从系统相册"隐藏"进应用私有的 vault 目录，提供 1–3 红心评分、收藏、相册组织、内建/VLC 播放，以及图案/PIN + 生物识别锁。深色主题，无任何云端依赖。

## 当前状态与重点

- 版本 1.0.14+19；通过 GitHub Releases 提供 Android APK。
- 首页两个页签：**Visible**（系统相册文件夹，经 photo_manager 读 MediaStore）与 **Invisible**（保险库相册，Drift 数据库）。隐藏 = 拷入 vault + 尽力删除原件；取消隐藏反向恢复。
- 元数据在 Drift(SQLite) **schema v6**；媒体字节在磁盘 vault 目录；备份为"媒体文件 + JSON manifest(version 3)"的**逐字段手工序列化**导出。
- 锁以覆盖层渲染在应用 Navigator 之上（不可破坏不变量，见 AGENTS.md）；push 到应用 Navigator 的路由自动被锁覆盖。

## 能力地图

- **隐藏/取消隐藏**：Visible 页签多选 → 导入管线（vault 拷贝、元数据、缩略图、DB 行）→ 系统相册删除。深入：`docs/02-design/screens/06-import.md`、`lib/data/services/import/`。
- **首页浏览**：Visible 文件夹与 Invisible 相册均支持马赛克/列表切换且分别持久化；Invisible 包含系统卡片 All/Fav/回收站、用户相册与合集。深入：`docs/02-design/screens/02-home-albums.md`、`03-media-grid.md`。
- **评分与筛选**：媒体和保险库相册支持 0–3 红心；Favorites 是计算相册（rating>=1）；媒体网格支持红心筛选。
- **媒体排序**：多级排序（日期/名称/评分三族 × 升降序；族内唯一；选择顺序=优先级），客户端比较器实现。
- **相册组织**：Invisible 支持相册多级排序、排他的 custom 手动顺序、置顶、评分，以及合集创建/改名/添加成员/移出/整理/无损解散。
- **每文件夹视图偏好**：排序/筛选/列数按 `MediaViewScope`（`visibleFolder:` / `vaultAlbum:`）持久化，互相隔离。
- **回收站**：软删除 + 保留期清理。
- **备份/恢复**：导出到目录（媒体 + manifest v3）；导入向后兼容 v1/v2。
- **安全**：图案/PIN + 生物识别、FLAG_SECURE、自动锁。深入：`docs/03-architecture/security.md`。

## 使用路径

- 想隐藏媒体：Visible 页签 → 进文件夹 → 多选 → Hide。
- 想切换首页形态：Visible 或 Invisible → 顶部列表/马赛克按钮；两个页签分别记忆选择。
- 想整理保险库：Invisible → 相册或合集长按；⋮ 菜单可排序、整理顺序、新建相册/合集和调整样式。
- 想找回媒体：相册菜单"取消隐藏"，或回收站恢复。

## 界面与交互

### 首页 Visible / Invisible

- 角色与入口：解锁后的默认页签。
- 图示状态：当前

```text
┌ [📷 Visible][🔒 Invisible]  ▦/≣ 🖼|▶ ⋮ ┐
│ ┌─────┐ ┌─────┐                    │
│ │ All │ │ Fav♡│   系统卡片          │
│ └─────┘ └─────┘                    │
│ ┌─────┐ ┌─────┐   相册/合集         │
│ │📌 A │ │合集 B│   (可排序/评分/     │
│ └─────┘ └─────┘    手动整理)         │
│ ┌─────┐ ┌─────┐                    │
│ │＋新建│ │回收站│                   │
└────────────────────────────────────┘
```

- 交互与状态：两个页签的马赛克/列表偏好独立持久化；马赛克列数沿用全局设置；Visible 列表行支持点按进入与长按隐藏；Invisible 两种形态共享同一份 Shelf 数据与操作。
- 稳定约束：固定顺序 All → Fav → [用户区] → ＋新建 → 回收站；"照片 XOR 视频"全局过滤同时作用于两个页签的计数与封面。

## 架构落点

- `lib/domain/`：模型与枚举（MediaItem、Album、MediaSort…）。
- `lib/data/db/`：Drift 表/查询/迁移（database.dart，v6；手写 ALTER + beforeOpen 幂等安全网）。
- `lib/data/repositories/`：AlbumRepository（首页流 `watchAlbumViewsReactive`，表更新 + 75ms 防抖全量重建）、MediaRepository。
- `lib/data/services/`：导入/隐藏命名/缩略图/备份（vault_backup_service.dart）/图库封装。
- `lib/application/`：Riverpod 3 手写 providers、设置（AppSettings/SharedPreferences）、按 scope 的媒体视图偏好，以及互相隔离的 Visible/Invisible 首页形态偏好。
- `lib/presentation/`：home / grid / viewer / player / lock / settings / visible。
- 测试：`test/`（host 端 Drift 走 sqlite3 override）；迁移测试配套 `drift_schemas/*.json` + `test/generated_migrations/`。

## 统一语言

- **Visible 文件夹**：系统 MediaStore 相册（GalleryFolder）。应用侧无持久身份、不可改名。
- **保险库相册（vault album）**：Invisible 页签的媒体容器（Albums 表）；用户口中的"文件夹"多指它。不要与 Visible 文件夹混用。
- **红心（Hearts）**：0–3 评分；>=1 即收藏（Favorites）。
- **置顶（pin）**：`pinnedAt` 非空的用户相册浮到用户区最前，最近置顶在前。
- **MediaViewScope**：视图偏好命名空间 `visibleFolder:{id}` / `vaultAlbum:{id}`。
- **系统相册**：All / Favorites / Recycle，按查询计算、不落 membership（决策 A6）。

## 阅读路径

- 想理解产品与场景：`docs/01-overview/product-overview.md`、`docs/02-design/screens/`。
- 想改数据层：`docs/03-architecture/data-model.md` → `lib/data/db/`。
- 想改状态管理：`docs/03-architecture/state-management.md` → `lib/application/`。
- 想动锁/安全：`docs/03-architecture/security.md` + AGENTS.md 根锁不变量。
- 环境与发布：`DEVELOPMENT.md`、`Makefile`、`docs/toolchain-setup.md`。

## 当前边界

- 做：单机 Android、本地元数据、目录级备份/恢复。
- 不做：云同步；当前版本不做 iOS 发布；Visible 文件夹的应用侧元数据（评分/自定义顺序等）。
- iOS 适配审计：见 `docs/05-review/ios-platform-compatibility-audit.md`；审计结论是 Flutter 业务层可复用，但当前 Android D5 隐藏、PhotoKit 权限、分享扩展、隐私保护、外部播放与发布链尚未形成 iOS 实现。

## 关键考量

- 系统相册用查询计算而非 membership，避免评分与收藏关系漂移（决策 A6）。
- 媒体时序统一用 `COALESCE(dateTaken, dateAdded)` + 原文件名平局，保证隐藏/取消隐藏不重排。
- 视图偏好按 scope 隔离而非全局，防止跨文件夹串扰（AGENTS.md 不变量）。
- 首页形态偏好按页签隔离：Visible 文件夹列表与 Invisible Shelf 列表不得互相切换。
- 迁移采取"显式 onUpgrade + beforeOpen 幂等安全网"双保险，容忍旧构建跳版本升级。

## 质量约束与取舍

- **可靠性/可恢复性**：认证覆盖层必须位于应用 Navigator 之上；锁定期间保持 Navigator 挂载并禁用指针/焦点/语义；所有私有路由被覆盖（AGENTS.md；有回归测试）。
- **数据完整性**：rating 不变量 0–3 在仓库边界 clamp；删除相册不删媒体；解散合集不删相册或媒体；purge 同时清文件+缩略图+行+membership+封面引用。
- **兼容性**：备份导入向后兼容旧 manifest 版本；对未知的更高版本硬校验拒绝。

## 证据索引

- `lib/data/db/tables.dart`、`lib/data/db/database.dart`（schemaVersion=6、迁移链、合集表与索引）。
- `lib/application/providers.dart`、`lib/core/utils/album_query_utils.dart`（首页 Shelf 组装与相册排序规则）。
- `lib/application/media/album_list_preferences.dart`、`visible_folder_view_preferences.dart`（两个首页形态偏好及隔离 key）。
- `lib/application/media/media_view_preferences.dart`（多级排序校验与 JSON 持久化模式）。
- `lib/core/utils/media_query_utils.dart`（客户端多级比较器与选择规则）。
- `lib/data/services/vault_backup_service.dart`（manifest v3 全字段清单、合集往返与旧版导入防御）。
- `docs/03-architecture/data-model.md`（模型与不变量）。
