# 最近与收藏功能设计

- 日期：2026-11-07
- 状态：已确认，待实现
- 范围：图库侧栏的「最近」「收藏」两个入口及其数据层支持

## 1. 背景

图库侧栏目前有五个入口：全部截图、文字、最近、收藏、回收站。
「全部截图」「文字」已接真实数据，「最近」「收藏」「回收站」只是无响应的占位项，并且带有硬编码假计数（`LensoLibraryView.navCounts`）。
数据层没有收藏字段，也没有「最近」的时间筛选。

本次只实现「最近」和「收藏」。回收站、标签体系、批量多选收藏不在范围内。

## 2. 目标

1. 「最近」展示过去 7 天内的截图与文字收纳条目，按时间倒序混排。
2. 「收藏」展示已收藏的截图与文字收纳条目，按收藏时间倒序混排。
3. 截图与文字都可以收藏 / 取消收藏。
4. 侧栏显示真实计数，并具备可点击的选中态。

## 3. 数据模型

### 3.1 表结构变更

`screenshots` 与 `text_notes` 各新增两列：

```sql
ALTER TABLE screenshots ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;
ALTER TABLE screenshots ADD COLUMN favorited_at REAL;
ALTER TABLE text_notes  ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;
ALTER TABLE text_notes  ADD COLUMN favorited_at REAL;
```

沿用 `ScreenshotStore.migrate` 现有的幂等做法：直接执行 `ALTER TABLE`，列已存在时忽略错误。

### 3.2 模型变更

```swift
struct ScreenshotRecord {
    // 现有字段…
    let isFavorite: Bool
    let favoritedAt: Date?
}

struct TextNote {
    // 现有字段…
    var isFavorite: Bool
    var favoritedAt: Date?
}
```

`list()`、`listTextNotes()` 的 SELECT 增加两列并映射。

### 3.3 Store API

```swift
func setScreenshotFavorite(_ favorite: Bool, id: UUID) throws
func setTextNoteFavorite(_ favorite: Bool, id: UUID) throws
```

- 收藏时写入 `favorited_at = now`，取消收藏时置为 `NULL`。
- 写入后由调用方发送 `.libraryChanged` 通知。
- 列表过滤在内存中完成（本地数据量小），不新增筛选 SQL。

### 3.4 刷新通知

新增 `Notification.Name.libraryChanged`。

- 收藏 / 取消收藏后发送。
- `LibraryWindowView`、`TextNotesView` 监听 `.libraryChanged` 与现有的 `.screenshotSaved`、`.textNotesChanged`，统一重新加载。
- 文字的新建 / 编辑 / 删除仍发送 `.textNotesChanged`，保持不变。

## 4. 统一条目模型

新增 `LibraryEntry`（放在 `LENSO/Library/LibraryImage.swift`）：

```swift
struct LibraryEntry: Identifiable {
    enum Kind { case screenshot, note }
    let id: String          // "s:<uuid>" 或 "n:<uuid>"，避免两类 ID 冲突
    let kind: Kind
    let date: Date          // 排序基准
    let favoriteDate: Date? // 收藏时间，用于收藏排序
    let thumbnail: NSImage? // 仅截图
    let screenshot: ScreenshotRecord?
    let note: TextNote?
}
```

### 4.1 「最近」口径

- 时间窗口：过去 7 天（`Calendar.current.date(byAdding: .day, value: -7, to: Date())`）。
- 截图按 `capturedAt` 判断并排序；文字按 `updatedAt` 判断并排序。
- 两类混在一起，按 `date` 倒序。
- 侧栏计数 = 该窗口内截图数 + 文字数。

### 4.2 「收藏」口径

- 条件：`isFavorite == true`。
- 排序基准：`favoritedAt` 倒序；缺失时回退到 `date`。
- 侧栏计数 = 收藏截图数 + 收藏文字数。

## 5. 界面设计

### 5.1 侧栏

- `Section` 枚举扩展为：`screenshots`、`text`、`recent`、`favorites`、`trash`。
- 「最近」「收藏」可点击，选中时使用与现有主项一致的高亮样式（白底圆角 + 蓝色文字）。
- 两项显示真实计数；删除 `navCounts` 中「最近」「收藏」「回收站」的假计数。
- 「回收站」保持不可点击、无计数（不在本次范围）。
- 标签分组保持现状。

### 5.2 最近 / 收藏主区域

采用时间倒序的纵向列表（`ScrollView` + `LazyVStack`），每行一种类型：

- **截图行**
  - 左侧 120×75 缩略图（圆角 8）。
  - 右侧：文件名、尺寸、时间。
  - 行尾星标按钮。
  - 点击行打开预览窗口（双击语义不适用于列表，改为单击）。
- **文字行**
  - 文字摘要（最多 3 行）、来源应用、更新时间。
  - 行尾操作：复制、编辑、星标。
- 行背景：白色半透明圆角卡片，与文字卡片风格一致。
- 顶部区域显示当前入口标题与说明（如「过去 7 天」/「已收藏」）。
- 底部计数：
  - 最近：`近 7 天 · X 张截图 · Y 条文字`
  - 收藏：`已收藏 X 张截图 · Y 条文字`

### 5.3 空状态

- 最近：`最近 7 天还没有内容`，副标题 `截图和文字收纳条目会按时间出现在这里`。
- 收藏：`还没有收藏`，副标题 `点卡片上的星标即可收藏截图或文字`。

### 5.4 星标入口

- **全部截图网格**：每个图片单元左上角显示星标。
  - 未收藏：仅悬停时显示空心星。
  - 已收藏：始终显示黄色实心星。
  - 点击星标只切换收藏，不触发选中或预览。
  - 右键菜单增加「收藏 / 取消收藏」。
- **文字卡片**：操作栏新增星标按钮，已收藏为黄色实心星。
- **最近 / 收藏列表**：行尾星标同上。

### 5.5 全部截图网格

- 现有网格、多选、底部合计、双击预览保持不变。
- 新增的星标使用 `Button` + `.plain` 样式，并用 `contentShape` 限定点击区域，避免与单元格手势冲突。
- 星标按钮与选中勾角标位置错开（星标左上，勾选右上）。

## 6. 边界情况

- 截图 UUID 与文字 UUID 理论上可能相同；`LibraryEntry.id` 加类型前缀。
- 在「收藏」中取消收藏后，条目立即从列表消失，计数同步更新。
- 在「最近」中取消收藏，条目仍保留（只要还在 7 天窗口内）。
- 收藏条目被删除时，收藏列表随之减少（无需额外清理）。
- 文字编辑不改变收藏时间，收藏排序保持稳定。
- 取消收藏后 `favorited_at` 置空；再次收藏使用新的时间。
- 应用首次启动执行迁移，已有数据默认 `is_favorite = 0`。

## 7. 非目标

- 回收站与恢复逻辑。
- 标签的增删改与筛选。
- 批量收藏 / 批量取消收藏。
- 收藏夹分组、排序自定义。
- 剪贴板历史条目的收藏（现有「收藏到文字收纳」保持不变）。

## 8. 验证

1. `xcodebuild -project LENSO.xcodeproj -scheme LENSO build` 成功。
2. 启动 App：
   - 新截图出现在「全部截图」与「最近」。
   - 点击星标后出现在「收藏」，侧栏计数 +1。
   - 再次点击取消，条目从「收藏」消失，计数 -1。
   - 文字卡片打星后出现在「收藏」，最近列表中文字与截图按时间混排。
   - 「最近」只包含 7 天内的条目。
   - 重启 App 后收藏状态保留。
