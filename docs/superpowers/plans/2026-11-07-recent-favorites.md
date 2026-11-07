# 最近与收藏功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在图库中实现「最近」（过去 7 天截图 + 文字混排）与「收藏」（星标截图 + 文字混排），并补上收藏持久化。

**Architecture:** 在 `ScreenshotStore` 的 SQLite 表上增加收藏列与写入方法；用 `LibraryEntry` 把截图和文字统一成可按时间排序的条目；`LibraryWindowView` 统一加载数据后传给 `LensoLibraryView`，侧栏切换 `全部截图 / 文字 / 最近 / 收藏`，最近与收藏复用新的 `LibraryFeedView`。

**Tech Stack:** Swift 6 / SwiftUI / SQLite3（系统库）/ XcodeGen。

**说明：** 项目没有测试 target，验证方式为 `xcodebuild` 编译 + 启动 App 手工走查（计划末尾列出步骤）。

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `LENSO/Infrastructure/ScreenshotStore.swift` | 迁移、记录模型、收藏写入、列表查询 |
| `LENSO/Library/LibraryEntry.swift` | 截图 / 文字统一条目 + `.libraryChanged` 通知名 |
| `LENSO/Library/FavoriteStarButton.swift` | 可复用星标按钮 |
| `LENSO/Library/LibraryFeedView.swift` | 最近 / 收藏的时间倒序混排列表 |
| `LENSO/TextNotes/NoteEditorSheet.swift` | 从 `TextNotesView` 抽出的编辑弹窗（两处复用） |
| `LENSO/Library/LibraryImage.swift` | 网格条目增加收藏状态 |
| `LENSO/Library/LibraryWindowView.swift` | 加载截图 + 文字，监听全部刷新通知 |
| `LENSO/Library/LensoLibraryView.swift` | 侧栏分区、真实计数、网格星标、最近 / 收藏主区域 |
| `LENSO/TextNotes/TextNotesView.swift` | 文字卡片星标 |

---

## Task 1: 数据层 — 收藏列、模型与写入方法

**Files:**
- Modify: `LENSO/Infrastructure/ScreenshotStore.swift`

- [ ] **Step 1: 模型增加收藏字段**

把 `ScreenshotRecord` 与 `TextNote` 改为：

```swift
struct ScreenshotRecord: Identifiable, Hashable {
    let id: UUID
    let filename: String
    let width: Int
    let height: Int
    let fileSize: Int
    let capturedAt: Date
    let isFavorite: Bool
    let favoritedAt: Date?
}

/// 文字收纳条目
struct TextNote: Identifiable {
    let id: UUID
    var content: String
    let sourceApp: String?
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var favoritedAt: Date?
}
```

- [ ] **Step 2: 迁移增加列**

`migrate(db:)` 中两张表的 `CREATE TABLE` 增加列：

```sql
CREATE TABLE IF NOT EXISTS screenshots (
    id TEXT PRIMARY KEY NOT NULL,
    filename TEXT NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    file_size INTEGER NOT NULL,
    captured_at REAL NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    favorited_at REAL
);
...
CREATE TABLE IF NOT EXISTS text_notes (
    id TEXT PRIMARY KEY NOT NULL,
    content TEXT NOT NULL,
    source_app TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    favorited_at REAL
);
```

在现有 `ALTER TABLE clipboard_items ...` 之后追加幂等升级：

```swift
sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN favorited_at REAL;", nil, nil, nil)
sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
sqlite3_exec(db, "ALTER TABLE text_notes ADD COLUMN favorited_at REAL;", nil, nil, nil)
```

- [ ] **Step 3: 更新所有构造点与查询映射**

`save(image:)` 返回值：

```swift
return ScreenshotRecord(
    id: id, filename: filename,
    width: image.width, height: image.height,
    fileSize: fileSize, capturedAt: capturedAt,
    isFavorite: false, favoritedAt: nil
)
```

`listUnlocked()`：

```swift
let sql = "SELECT id, filename, width, height, file_size, captured_at, is_favorite, favorited_at FROM screenshots ORDER BY captured_at DESC;"
...
let isFavorite = sqlite3_column_int(stmt, 6) != 0
let favoritedAt: Date? = sqlite3_column_type(stmt, 7) == SQLITE_NULL
    ? nil
    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
records.append(ScreenshotRecord(
    id: id, filename: filename, width: width, height: height,
    fileSize: fileSize, capturedAt: capturedAt,
    isFavorite: isFavorite, favoritedAt: favoritedAt
))
```

`createTextNote` 返回值：

```swift
return TextNote(id: id, content: content, sourceApp: sourceApp,
                createdAt: now, updatedAt: now,
                isFavorite: false, favoritedAt: nil)
```

`listTextNotes()`：

```swift
let sql = "SELECT id, content, source_app, created_at, updated_at, is_favorite, favorited_at FROM text_notes ORDER BY updated_at DESC;"
...
let isFavorite = sqlite3_column_int(stmt, 5) != 0
let favoritedAt: Date? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
    ? nil
    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
notes.append(TextNote(id: id, content: String(cString: contentText),
                      sourceApp: sourceApp, createdAt: createdAt, updatedAt: updatedAt,
                      isFavorite: isFavorite, favoritedAt: favoritedAt))
```

- [ ] **Step 4: 新增收藏写入方法**

放在 `// MARK: - Delete` 之后：

```swift
// MARK: - Favorites

func setScreenshotFavorite(_ favorite: Bool, id: UUID) throws {
    try queue.sync {
        let sql = "UPDATE screenshots SET is_favorite = ?, favorited_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, favorite ? 1 : 0)
        if favorite {
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        Self.bind(stmt, 3, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
    }
}

func setTextNoteFavorite(_ favorite: Bool, id: UUID) throws {
    try queue.sync {
        let sql = "UPDATE text_notes SET is_favorite = ?, favorited_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.dbFailed }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, favorite ? 1 : 0)
        if favorite {
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        Self.bind(stmt, 3, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.dbFailed }
    }
}
```

- [ ] **Step 5: 编译检查**

Run: `xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add LENSO/Infrastructure/ScreenshotStore.swift
git commit -m "feat: persist favorite state for screenshots and text notes"
```

---

## Task 2: 统一条目、星标按钮与编辑弹窗

**Files:**
- Create: `LENSO/Library/LibraryEntry.swift`
- Create: `LENSO/Library/FavoriteStarButton.swift`
- Create: `LENSO/TextNotes/NoteEditorSheet.swift`

- [ ] **Step 1: 新建 `LibraryEntry.swift`**

```swift
import AppKit

/// 最近 / 收藏列表的统一条目：截图与文字按时间混排
struct LibraryEntry: Identifiable {
    enum Kind { case screenshot, note }

    let id: String
    let kind: Kind
    let date: Date
    let favoriteDate: Date?
    let thumbnail: NSImage?
    let screenshot: ScreenshotRecord?
    let note: TextNote?

    var isFavorite: Bool {
        screenshot?.isFavorite ?? note?.isFavorite ?? false
    }

    static func screenshot(_ record: ScreenshotRecord, thumbnail: NSImage?) -> LibraryEntry {
        LibraryEntry(
            id: "s:\(record.id.uuidString)",
            kind: .screenshot,
            date: record.capturedAt,
            favoriteDate: record.favoritedAt,
            thumbnail: thumbnail,
            screenshot: record,
            note: nil
        )
    }

    static func note(_ note: TextNote) -> LibraryEntry {
        LibraryEntry(
            id: "n:\(note.id.uuidString)",
            kind: .note,
            date: note.updatedAt,
            favoriteDate: note.favoritedAt,
            thumbnail: nil,
            screenshot: nil,
            note: note
        )
    }
}

extension Notification.Name {
    static let libraryChanged = Notification.Name("com.lenso.libraryChanged")
}
```

- [ ] **Step 2: 新建 `FavoriteStarButton.swift`**

```swift
import SwiftUI

/// 收藏星标：未收藏为空心，收藏后为黄色实心
struct FavoriteStarButton: View {
    let isFavorite: Bool
    var size: CGFloat = 13
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.primary.opacity(hovering ? 0.85 : 0.4))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(hovering || isFavorite ? 0.92 : 0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isFavorite ? "取消收藏" : "收藏")
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
    }
}
```

- [ ] **Step 3: 新建 `NoteEditorSheet.swift`**

把 `TextNotesView.swift` 末尾的 `private struct EditNoteSheet` 原样搬出来，改名为 `NoteEditorSheet` 并去掉 `private`：

```swift
import SwiftUI

/// 编辑文字片段
struct NoteEditorSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("编辑文字").font(.system(size: 15, weight: .semibold))
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minWidth: 420, minHeight: 220)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.08)))
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .environment(\.colorScheme, .light)
    }
}
```

- [ ] **Step 4: 重新生成 Xcode 工程**

Run: `xcodegen generate`
Expected: `Created project at .../LENSO.xcodeproj`

- [ ] **Step 5: 编译检查**

Run: `xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add LENSO/Library/LibraryEntry.swift LENSO/Library/FavoriteStarButton.swift LENSO/TextNotes/NoteEditorSheet.swift LENSO.xcodeproj/project.pbxproj
git commit -m "feat: add library entry model, favorite star, shared note editor"
```

---

## Task 3: 混排列表 `LibraryFeedView`

**Files:**
- Create: `LENSO/Library/LibraryFeedView.swift`

- [ ] **Step 1: 新建文件并实现**

```swift
import SwiftUI
import AppKit

/// 「最近」「收藏」的时间倒序混排列表
struct LibraryFeedView: View {
    let entries: [LibraryEntry]
    let emptyTitle: String
    let emptyMessage: String

    @Environment(\.openWindow) private var openWindow
    @State private var editingNote: TextNote?
    @State private var draft = ""
    @State private var copiedID: String?

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "clock",
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            if let record = entry.screenshot {
                                screenshotRow(entry, record: record)
                            } else if let note = entry.note {
                                noteRow(entry, note: note)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(
                text: $draft,
                onCancel: { editingNote = nil },
                onSave: {
                    try? ScreenshotStore.shared.updateTextNote(id: note.id, content: draft)
                    editingNote = nil
                    NotificationCenter.default.post(name: .textNotesChanged, object: nil)
                    NotificationCenter.default.post(name: .libraryChanged, object: nil)
                }
            )
        }
    }

    // MARK: - Rows

    private func screenshotRow(_ entry: LibraryEntry, record: ScreenshotRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                openWindow(id: "preview", value: record.id)
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if let thumbnail = entry.thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.primary.opacity(0.06)
                        }
                    }
                    .frame(width: 120, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.filename)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(record.width) × \(record.height) · \(timeText(entry.date))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开预览")

            FavoriteStarButton(isFavorite: entry.isFavorite) {
                toggleScreenshotFavorite(record)
            }
        }
        .padding(10)
        .background(rowBackground)
    }

    private func noteRow(_ entry: LibraryEntry, note: TextNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.7)))

            VStack(alignment: .leading, spacing: 6) {
                Text(note.content.isEmpty ? "（空白）" : note.content)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let source = note.sourceApp {
                        Label(source, systemImage: "app")
                            .lineLimit(1)
                    }
                    Text(timeText(entry.date))
                    Spacer()
                    if copiedID == entry.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else {
                        actionButton("doc.on.doc", "复制") { copy(note, entry: entry) }
                    }
                    actionButton("pencil", "编辑") {
                        draft = note.content
                        editingNote = note
                    }
                    actionButton("trash", "删除", danger: true) { delete(note) }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            FavoriteStarButton(isFavorite: entry.isFavorite) {
                toggleNoteFavorite(note)
            }
        }
        .padding(10)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.68))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 1)
            )
    }

    private func actionButton(
        _ icon: String,
        _ label: String,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(danger ? .red : .secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Actions

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func toggleScreenshotFavorite(_ record: ScreenshotRecord) {
        try? ScreenshotStore.shared.setScreenshotFavorite(!record.isFavorite, id: record.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func toggleNoteFavorite(_ note: TextNote) {
        try? ScreenshotStore.shared.setTextNoteFavorite(!note.isFavorite, id: note.id)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func delete(_ note: TextNote) {
        try? ScreenshotStore.shared.deleteTextNote(id: note.id)
        NotificationCenter.default.post(name: .textNotesChanged, object: nil)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    private func copy(_ note: TextNote, entry: LibraryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.content, forType: .string)
        ClipboardMonitor.shared.markSelfWrite()
        SaveToastController.shared.show(title: "已复制", subtitle: "到剪贴板", thumbnail: nil)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedID == entry.id { copiedID = nil }
            }
        }
    }
}
```

- [ ] **Step 2: 重新生成工程并编译**

Run: `xcodegen generate && xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add LENSO/Library/LibraryFeedView.swift LENSO.xcodeproj/project.pbxproj
git commit -m "feat: add mixed recent/favorites feed view"
```

---

## Task 4: 图库窗口加载真实文字数据并统一刷新

**Files:**
- Modify: `LENSO/Library/LibraryImage.swift`
- Modify: `LENSO/Library/LibraryWindowView.swift`

- [ ] **Step 1: `LibraryImage` 增加收藏状态**

```swift
struct LibraryImage: Identifiable {
    let id: UUID
    let thumbnail: NSImage
    let sourceName: String
    let isFavorite: Bool
}
```

- [ ] **Step 2: `LibraryWindowView` 加载截图 + 文字并监听全部通知**

```swift
struct LibraryWindowView: View {
    @State private var images: [LibraryImage] = []
    @State private var records: [ScreenshotRecord] = []
    @State private var notes: [TextNote] = []
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LensoLibraryView(
            images: images,
            records: records,
            notes: notes,
            onOpenPreview: { id in
                openWindow(id: "preview", value: id)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .screenshotSaved)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .textNotesChanged)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in load() }
    }

    private func load() {
        let store = ScreenshotStore.shared
        records = (try? store.list()) ?? []
        notes = (try? store.listTextNotes()) ?? []
        images = records.map { record in
            let thumb = store.loadThumbnail(record) ?? store.loadImage(record)
            let nsImage = thumb.map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width / 2, height: $0.height / 2))
            } ?? NSImage(size: NSSize(width: 40, height: 30))
            return LibraryImage(
                id: record.id,
                thumbnail: nsImage,
                sourceName: "LENSO",
                isFavorite: record.isFavorite
            )
        }
    }
}
```

- [ ] **Step 3: 暂不编译、不提交**

`LensoLibraryView` 尚未接收新参数，此时编译会失败。直接进入 Task 5，完成两边的参数对接后一起编译、一起提交。

---

## Task 5: 侧栏分区、真实计数与网格星标

**Files:**
- Modify: `LENSO/Library/LensoLibraryView.swift`

- [ ] **Step 1: 替换视图头部与状态**

```swift
struct LensoLibraryView: View {
    let images: [LibraryImage]
    let records: [ScreenshotRecord]
    let notes: [TextNote]
    @State private var selectedIDs: Set<UUID> = []
    @State private var section: Section = .screenshots
    var onOpenPreview: ((UUID) -> Void)? = nil
    @Environment(\.openWindow) private var openWindow

    enum Section { case screenshots, text, recent, favorites }

    private let columns = [
        GridItem(.adaptive(minimum: 175, maximum: 260), spacing: 12)
    ]
```

删除原来的 `@State searchText`、`@State noteCount`、`.onAppear` 与 `.onReceive(.textNotesChanged)`，因为数据已由父视图统一传入。

- [ ] **Step 2: body 按分区切换**

```swift
var body: some View {
    HStack(spacing: 0) {
        sidebar
            .background(sidebarGradient)

        VStack(spacing: 12) {
            switch section {
            case .screenshots:
                toolbar
                screenshotGrid
                footer
            case .text:
                TextNotesView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .recent:
                feedHeader(title: "最近", subtitle: "过去 7 天")
                LibraryFeedView(
                    entries: recentEntries,
                    emptyTitle: "最近 7 天还没有内容",
                    emptyMessage: "截图和文字收纳条目会按时间出现在这里"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                feedFooter(summary: recentSummary)
            case .favorites:
                feedHeader(title: "收藏", subtitle: "截图与文字")
                LibraryFeedView(
                    entries: favoriteEntries,
                    emptyTitle: "还没有收藏",
                    emptyMessage: "点卡片上的星标即可收藏截图或文字"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                feedFooter(summary: favoriteSummary)
            }
        }
        .padding(12)
        .background(mainGradient)
    }
    .frame(minWidth: 760, minHeight: 520)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .environment(\.colorScheme, .light)
}
```

- [ ] **Step 3: 网格与收藏切换**

```swift
private var screenshotGrid: some View {
    ScrollView {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(images) { item in
                LibraryImageCell(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    onOpen: { onOpenPreview?(item.id) },
                    onToggleSelection: { toggleSelection(item.id) },
                    onToggleFavorite: { toggleFavorite(item) }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }
}

private func toggleSelection(_ id: UUID) {
    if selectedIDs.contains(id) {
        selectedIDs.remove(id)
    } else {
        selectedIDs.insert(id)
    }
}

private func toggleFavorite(_ item: LibraryImage) {
    try? ScreenshotStore.shared.setScreenshotFavorite(!item.isFavorite, id: item.id)
    NotificationCenter.default.post(name: .libraryChanged, object: nil)
}
```

- [ ] **Step 4: 最近 / 收藏数据与计数**

```swift
private var recentCutoff: Date {
    Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
}

private var thumbnailByID: [UUID: NSImage] {
    Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.thumbnail) })
}

private var recentEntries: [LibraryEntry] {
    let cutoff = recentCutoff
    let screenshotEntries = records
        .filter { $0.capturedAt >= cutoff }
        .map { LibraryEntry.screenshot($0, thumbnail: thumbnailByID[$0.id]) }
    let noteEntries = notes
        .filter { $0.updatedAt >= cutoff }
        .map { LibraryEntry.note($0) }
    return (screenshotEntries + noteEntries).sorted { $0.date > $1.date }
}

private var favoriteEntries: [LibraryEntry] {
    let screenshotEntries = records
        .filter(\.isFavorite)
        .map { LibraryEntry.screenshot($0, thumbnail: thumbnailByID[$0.id]) }
    let noteEntries = notes
        .filter(\.isFavorite)
        .map { LibraryEntry.note($0) }
    return (screenshotEntries + noteEntries).sorted {
        ($0.favoriteDate ?? $0.date) > ($1.favoriteDate ?? $1.date)
    }
}

private var recentScreenshotCount: Int { recentEntries.filter { $0.kind == .screenshot }.count }
private var recentNoteCount: Int { recentEntries.filter { $0.kind == .note }.count }
private var favoriteScreenshotCount: Int { favoriteEntries.filter { $0.kind == .screenshot }.count }
private var favoriteNoteCount: Int { favoriteEntries.filter { $0.kind == .note }.count }

private var recentSummary: String {
    "近 7 天 · \(recentScreenshotCount) 张截图 · \(recentNoteCount) 条文字"
}

private var favoriteSummary: String {
    "已收藏 \(favoriteScreenshotCount) 张截图 · \(favoriteNoteCount) 条文字"
}

private func feedHeader(title: String, subtitle: String) -> some View {
    HStack(spacing: 8) {
        Text(title).font(.system(size: 15, weight: .semibold))
        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        Spacer()
        Image(systemName: "magnifyingglass")
            .font(.system(size: 14))
            .foregroundStyle(.primary.opacity(0.65))
            .onTapGesture { SearchPanelController.shared.show() }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Capsule().fill(.white.opacity(0.55)))
    .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
}

private func feedFooter(summary: String) -> some View {
    HStack {
        Text(summary)
            .font(.system(size: 11))
            .foregroundStyle(.primary.opacity(0.7))
        Spacer()
    }
    .padding(.horizontal, 8)
}
```

- [ ] **Step 5: 侧栏真实计数**

把 `navCounts` 改名为 `tagCounts`，只保留标签：

```swift
private let tagCounts: [String: Int] = [
    "工作": 32, "生活": 28, "设计": 24, "其他": 44,
]
```

`tagItem` 中读取 `tagCounts[title]`。

侧栏主项：

```swift
navigationItem("全部截图", icon: "folder.fill", count: images.count,
               isPrimary: section == .screenshots)
    .onTapGesture { section = .screenshots }

navigationItem("文字", icon: "text.alignleft",
               count: notes.count,
               isPrimary: section == .text)
    .onTapGesture { section = .text }

navigationItem("最近", icon: "clock",
               count: recentEntries.count,
               isPrimary: section == .recent)
    .onTapGesture { section = .recent }

navigationItem("收藏", icon: "star",
               count: favoriteEntries.count,
               isPrimary: section == .favorites)
    .onTapGesture { section = .favorites }

navigationItem("回收站", icon: "trash")
```

- [ ] **Step 6: 把 `imageCell` 换成独立单元视图**

删除 `private func imageCell(_ item: LibraryImage) -> some View`，在文件末尾新增：

```swift
private struct LibraryImageCell: View {
    let item: LibraryImage
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onToggleFavorite: () -> Void

    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.blue, lineWidth: 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.blue)
                            .padding(7)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                FavoriteStarButton(isFavorite: item.isFavorite, action: onToggleFavorite)
                    .opacity(hovering || item.isFavorite ? 1 : 0)
                    .allowsHitTesting(hovering || item.isFavorite)
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .contextMenu {
                Button(item.isFavorite ? "取消收藏" : "收藏", action: onToggleFavorite)
            }
            .gesture(
                TapGesture(count: 2)
                    .onEnded(onOpen)
                    .exclusively(before: TapGesture().onEnded(onToggleSelection))
            )
    }
}
```

- [ ] **Step 7: 编译**

Run: `xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add LENSO/Library/LibraryImage.swift LENSO/Library/LibraryWindowView.swift LENSO/Library/LensoLibraryView.swift
git commit -m "feat: recent and favorites library sections with real counts and star toggles"
```

---

## Task 6: 文字卡片星标

**Files:**
- Modify: `LENSO/TextNotes/TextNotesView.swift`

- [ ] **Step 1: 监听收藏刷新并复用编辑弹窗**

- 把 `.sheet` 中的 `EditNoteSheet` 改为 `NoteEditorSheet`。
- 删除文件末尾的 `private struct EditNoteSheet { ... }`。
- 增加监听：

```swift
.onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in reload() }
```

- [ ] **Step 2: 操作栏增加星标**

在 `noteCard` 的操作栏中、复制按钮之前插入：

```swift
cardAction(
    note.isFavorite ? "star.fill" : "star",
    note.isFavorite ? "取消收藏" : "收藏",
    tint: note.isFavorite ? .yellow : nil
) {
    toggleFavorite(note)
}
```

- [ ] **Step 3: 扩展 `cardAction` 支持 tint**

```swift
private func cardAction(
    _ icon: String,
    _ label: String,
    danger: Bool = false,
    tint: Color? = nil,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(tint ?? (danger ? .red : .secondary))
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(label)
}
```

- [ ] **Step 4: 新增 `toggleFavorite`**

```swift
private func toggleFavorite(_ note: TextNote) {
    try? ScreenshotStore.shared.setTextNoteFavorite(!note.isFavorite, id: note.id)
    NotificationCenter.default.post(name: .libraryChanged, object: nil)
    reload()
}
```

- [ ] **Step 5: 编译**

Run: `xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add LENSO/TextNotes/TextNotesView.swift
git commit -m "feat: favorite toggle on text note cards"
```

---

## Task 7: 整体验证

**Files:** 无

- [ ] **Step 1: 完整编译**

Run: `xcodebuild -project LENSO.xcodeproj -scheme LENSO build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: 启动 App 手工走查**

在 Xcode 或 Finder 中启动 LENSO，逐项确认：

1. 侧栏「最近」「收藏」可点击并有选中高亮，计数为真实值。
2. 截一张图后，「最近」出现该截图，「全部截图」计数同步。
3. 悬停截图显示星标，点击后变黄色，「收藏」出现该截图，侧栏计数 +1。
4. 在「收藏」中取消星标，条目立即消失，计数 -1。
5. 在「文字」页给文字卡片打星，切到「收藏」能看到该文字；「最近」中截图与文字按时间倒序混排。
6. 在「最近 / 收藏」列表里点击截图行可打开预览；文字行可复制、编辑、删除。
7. 重启 App，收藏状态保留。
8. 右键截图单元出现「收藏 / 取消收藏」，且不影响双击预览与单击选择。

- [ ] **Step 3: 记录结果**

若有失败项，回到对应 Task 修复后重新验证；全部通过后提交剩余改动（如有）。
