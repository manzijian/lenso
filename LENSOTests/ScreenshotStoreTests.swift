import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import LENSO

@Suite("ScreenshotStore Storage Layer Tests")
struct ScreenshotStoreTests {

    private func createTempStore() throws -> (ScreenshotStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_StoreTest_\(UUID().uuidString)", isDirectory: true)
        let store = try ScreenshotStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    private func makeTestCGImage(width: Int = 32, height: Int = 32, color: NSColor = .red) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - 1. 截图记录 CRUD

    @Test("截图记录 CRUD：保存、查询、加载图片、删除与文件清理")
    func screenshotCRUD() throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let image = makeTestCGImage(width: 64, height: 48, color: .green)
        let now = Date()
        let record = try store.save(image: image, capturedAt: now)

        #expect(record.width == 64)
        #expect(record.height == 48)
        #expect(record.fileSize > 0)
        #expect(record.isFavorite == false)
        #expect(record.favoritedAt == nil)

        // 查询
        let list = try store.list()
        #expect(list.count == 1)
        #expect(list.first?.id == record.id)
        #expect(list.first?.filename == record.filename)

        // 加载图片与缩略图
        let loadedOrig = store.loadImage(record)
        let loadedThumb = store.loadThumbnail(record)
        #expect(loadedOrig != nil)
        #expect(loadedThumb != nil)

        // 删除
        try store.delete(record)
        let listAfter = try store.list()
        #expect(listAfter.isEmpty)

        // 验证磁盘文件已删除
        let origFile = tempDir.appendingPathComponent("Original").appendingPathComponent(record.filename)
        let thumbFile = tempDir.appendingPathComponent("Thumbnails").appendingPathComponent(record.filename)
        #expect(!FileManager.default.fileExists(atPath: origFile.path))
        #expect(!FileManager.default.fileExists(atPath: thumbFile.path))
    }

    // MARK: - 2. Favorite 切换与 favoritedAt

    @Test("收藏切换：isFavorite 状态改变与 favoritedAt 时间戳记录")
    func screenshotFavoriteToggle() throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let image = makeTestCGImage()
        let record = try store.save(image: image)

        #expect(record.isFavorite == false)
        #expect(record.favoritedAt == nil)

        // 标为收藏
        try store.setScreenshotFavorite(true, id: record.id)
        let listFav = try store.list()
        let favRecord = try #require(listFav.first)
        #expect(favRecord.isFavorite == true)
        #expect(favRecord.favoritedAt != nil)

        // 取消收藏
        try store.setScreenshotFavorite(false, id: record.id)
        let listUnfav = try store.list()
        let unfavRecord = try #require(listUnfav.first)
        #expect(unfavRecord.isFavorite == false)
        #expect(unfavRecord.favoritedAt == nil)
    }

    // MARK: - 3. Retention 过期清理

    @Test("Retention 过期清理：清理指定期限之前的数据，保留收藏项")
    func retentionCleanup() throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldDate = Date().addingTimeInterval(-86400 * 10) // 10 天前
        let midDate = Date().addingTimeInterval(-86400 * 8)  // 8 天前
        let newDate = Date().addingTimeInterval(-86400 * 1)  // 1 天前
        let cutoff = Date().addingTimeInterval(-86400 * 7)   // 7 天前为阈值

        let image = makeTestCGImage()
        let oldRecord = try store.save(image: image, capturedAt: oldDate)
        let oldFavRecord = try store.save(image: image, capturedAt: midDate)
        try store.setScreenshotFavorite(true, id: oldFavRecord.id)
        let newRecord = try store.save(image: image, capturedAt: newDate)

        // 执行清理：preserveFavorites = true
        let result = store.cleanupOlderThan(cutoff: cutoff, preserveFavorites: true)
        #expect(result.deletedScreenshots == 1) // 只有 oldRecord 被删除，oldFavRecord 被保护

        let remaining = try store.list()
        let remainingIDs = Set(remaining.map(\.id))
        #expect(!remainingIDs.contains(oldRecord.id))
        #expect(remainingIDs.contains(oldFavRecord.id))
        #expect(remainingIDs.contains(newRecord.id))
    }

    // MARK: - 4. 剪贴板图文写入/去重/时间倒序

    @Test("剪贴板图文写入：去重、时间倒序与最新时间跃升")
    func clipboardDeduplicationAndOrder() async throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. 文本写入与倒序
        _ = try store.saveClipboardText("Hello World", sourceApp: "Xcode")
        _ = try store.saveClipboardText("Second Line", sourceApp: "Safari")

        var clips = try store.listClipboard()
        #expect(clips.count == 2)
        #expect(clips[0].text == "Second Line")
        #expect(clips[1].text == "Hello World")

        // 2. 再次复制相同的文本 "Hello World" -> 不新增行，原行时间更新并跃升至第 1 位
        try? await Task.sleep(nanoseconds: 20_000_000)
        _ = try store.saveClipboardText("Hello World", sourceApp: "Notes")

        clips = try store.listClipboard()
        #expect(clips.count == 2) // 去重，总数依然为 2
        #expect(clips[0].text == "Hello World") // 跃升为最新第 1 项
        #expect(clips[0].sourceApp == "Notes")
        #expect(clips[1].text == "Second Line")

        // 3. 图片写入与去重
        let img1 = makeTestCGImage(width: 20, height: 20, color: .magenta)
        let clipImg1 = try store.saveClipboardImage(img1, sourceApp: "Finder")
        #expect(clipImg1.kind == .image)
        #expect(clipImg1.filename != nil)

        // 再次保存完全相同的图片 -> 指纹去重，不新增行，不重复写文件
        try? await Task.sleep(nanoseconds: 20_000_000)
        let clipImg2 = try store.saveClipboardImage(img1, sourceApp: "Chrome")
        #expect(clipImg2.id == clipImg1.id)
        #expect(clipImg2.filename == clipImg1.filename)

        let imageClips = (try store.listClipboard()).filter { $0.kind == .image }
        #expect(imageClips.count == 1)
        #expect(imageClips.first?.sourceApp == "Chrome")
    }

    // MARK: - 5. TextNote CRUD

    @Test("TextNote CRUD：创建、查询、更新、Touch 跃升、收藏与删除")
    func textNoteCRUD() async throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 创建
        let note1 = try store.createTextNote(content: "Note Content A", sourceApp: "Safari")
        let note2 = try store.createTextNote(content: "Note Content B", sourceApp: "Terminal")

        #expect(store.textNoteCount() == 2)
        var notes = try store.listTextNotes()
        #expect(notes[0].content == "Note Content B")
        #expect(notes[1].content == "Note Content A")

        // 更新内容
        try store.updateTextNote(id: note1.id, content: "Note Content A (Edited)")
        notes = try store.listTextNotes()
        #expect(notes[0].id == note1.id) // update 会刷新 updated_at，跃升为第 1 位
        #expect(notes[0].content == "Note Content A (Edited)")

        // 再次 touch note2
        try? await Task.sleep(nanoseconds: 20_000_000)
        try store.touchTextNote(id: note2.id)
        notes = try store.listTextNotes()
        #expect(notes[0].id == note2.id) // note2 跃升为第 1 位

        // 收藏
        try store.setTextNoteFavorite(true, id: note2.id)
        notes = try store.listTextNotes()
        #expect(notes.first(where: { $0.id == note2.id })?.isFavorite == true)

        // 删除
        try store.deleteTextNote(id: note1.id)
        #expect(store.textNoteCount() == 1)
    }

    // MARK: - 6. 并发插 50 条断言无丢失

    @Test("并发写入 50 条：多线程并发调用 createTextNote，断言无丢失无死锁")
    func concurrentInsertNoLoss() throws {
        let (store, tempDir) = try createTempStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let count = 50
        DispatchQueue.concurrentPerform(iterations: count) { i in
            do {
                _ = try store.createTextNote(content: "Concurrent Note #\(i)", sourceApp: "TestWorker")
            } catch {
                Issue.record("并发写入失败: \(error)")
            }
        }

        #expect(store.textNoteCount() == count)
        let list = try store.listTextNotes()
        #expect(list.count == count)

        // 验证 50 条各不相同
        let contents = Set(list.map(\.content))
        #expect(contents.count == count)
    }
}
