import Testing
import Foundation
@testable import LENSO

@Suite("ScreenshotStore Smoke Tests")
struct ScreenshotStoreSmokeTests {
    @Test("ScreenshotStore 初始化：注入临时目录可正常实例化并生成必要数据库和目录")
    func smokeInitialization() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_SmokeTest_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = try ScreenshotStore(baseDirectory: tempDir)
        #expect(store.textNoteCount() == 0)

        // 验证数据库和必要子目录已在临时目录成功生成
        let dbFile = tempDir.appendingPathComponent("lenso.sqlite")
        let origDir = tempDir.appendingPathComponent("Original")
        let thumbDir = tempDir.appendingPathComponent("Thumbnails")
        let clipDir = tempDir.appendingPathComponent("Clipboard")

        #expect(FileManager.default.fileExists(atPath: dbFile.path))
        #expect(FileManager.default.fileExists(atPath: origDir.path))
        #expect(FileManager.default.fileExists(atPath: thumbDir.path))
        #expect(FileManager.default.fileExists(atPath: clipDir.path))
    }
}
