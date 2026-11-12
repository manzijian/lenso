import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import LENSO

@Suite("安全与健壮性加固测试")
struct HardeningSecurityTests {

    private func makeTestCGImage(width: Int = 100, height: Int = 80) -> CGImage {
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
        ctx.setFillColor(NSColor.blue.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - 1. SQLite 自检与灾难恢复

    @Test("SQLite 灾难恢复：遭遇损坏数据库时自动备份为 lenso.corrupt 并重建新库")
    func testSQLiteIntegrityCheckAutoRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_CorruptTest_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbFile = tempDir.appendingPathComponent("lenso.sqlite")

        // 写入破坏性坏数据到 dbFile
        let junk = "NOT AN SQLITE DATABASE FILE HEADER JUNK DATA".data(using: .utf8)!
        try junk.write(to: dbFile)

        // 初始化 store，应自检失败并自动备份重建
        let store = try ScreenshotStore(baseDirectory: tempDir)
        #expect(store.textNoteCount() == 0)

        // 断言已生成 lenso.corrupt 备份文件
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let hasCorruptBackup = files.contains { $0.lastPathComponent.contains("lenso.corrupt.") }
        #expect(hasCorruptBackup == true)
        #expect(FileManager.default.fileExists(atPath: dbFile.path))
    }

    // MARK: - 2. 缩略图 ImageIO 降采样

    @Test("缩略图 ImageIO 降采样：大图保存后生成长边不超过 480 的紧凑缩略图")
    func testThumbnailDownsampling() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_ThumbTest_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try ScreenshotStore(baseDirectory: tempDir)
        let bigImage = makeTestCGImage(width: 800, height: 600)
        let record = try store.save(image: bigImage)

        let thumb = store.loadThumbnail(record)
        #expect(thumb != nil)
        if let thumb {
            #expect(thumb.width <= 480)
            #expect(thumb.height <= 480)
        }
    }

    // MARK: - 3. 本地服务 Token 鉴权与一键配置生成

    @Test("本地服务鉴权：Bearer Token 与 Query Token 正确放行，无 Token 拒绝")
    func testLocalServiceTokenValidation() {
        let service = LensoLocalService.shared
        let validToken = service.authToken

        // 1. 无 Token 验证失败
        #expect(service.validateAuth(headers: [:], queryItems: [:]) == false)

        // 2. Authorization Bearer Token 验证成功
        let validHeaders = ["authorization": "Bearer \(validToken)"]
        #expect(service.validateAuth(headers: validHeaders, queryItems: [:]) == true)

        // 3. Query Token 验证成功
        let validQuery = ["token": validToken]
        #expect(service.validateAuth(headers: [:], queryItems: validQuery) == true)

        // 4. 错误 Token 拒绝
        #expect(service.validateAuth(headers: ["authorization": "Bearer wrong"], queryItems: [:]) == false)
    }

    @Test("Claude Desktop 与 Claude Code 配置片段生成有效性")
    func testClaudeConfigGeneration() {
        let service = LensoLocalService.shared

        let desktopConfig = service.claudeDesktopConfig()
        #expect(desktopConfig.contains("mcpServers"))
        #expect(desktopConfig.contains("lenso"))
        #expect(desktopConfig.contains("--mcp"))

        let cliCommand = service.claudeCodeCommand()
        #expect(cliCommand.contains("claude mcp add lenso"))
        #expect(cliCommand.contains("--mcp"))

        let sseSnippet = service.sseConfigSnippet()
        #expect(sseSnippet.contains("http://127.0.0.1:"))
        #expect(sseSnippet.contains("/sse?token="))
    }
}
