import Testing
import Foundation
@testable import LENSO

@Suite("错误语义与显式抛错测试")
struct ScreenshotStoreErrorTests {

    @Test("目录创建失败显式抛错：baseDirectory 指向无法创建子目录的非法路径")
    func testDirectoryCreationFailure() {
        // 创建一个普通文件，然后将其作为 baseDirectory（同名文件阻止目录创建）
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("LENSO_FileConflict_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempFile.path, contents: "conflict".data(using: .utf8))
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let invalidBase = tempFile.appendingPathComponent("CannotCreateDir")

        #expect(throws: ScreenshotStore.StoreError.self) {
            _ = try ScreenshotStore(baseDirectory: invalidBase)
        }
    }

    @Test("MCPServer 参数校验错误显式返回：lenso_search_history 缺少 query")
    func testMCPServerMissingQuery() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 101,
            "method": "tools/call",
            "params": [
                "name": "lenso_search_history",
                "arguments": [:]
            ]
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let res = resp?["result"] as? [String: Any]
        #expect(res?["isError"] as? Bool == true)
        let content = res?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""
        #expect(text.contains("query"))
    }

    @Test("MCPServer 参数校验错误显式返回：lenso_copy_text 缺少 text")
    func testMCPServerMissingText() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 102,
            "method": "tools/call",
            "params": [
                "name": "lenso_copy_text",
                "arguments": [:]
            ]
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let res = resp?["result"] as? [String: Any]
        #expect(res?["isError"] as? Bool == true)
        let content = res?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""
        #expect(text.contains("text"))
    }

    @Test("MCPServer 参数校验错误显式返回：lenso_add_text_note 缺少 content")
    func testMCPServerMissingContent() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 103,
            "method": "tools/call",
            "params": [
                "name": "lenso_add_text_note",
                "arguments": [:]
            ]
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let res = resp?["result"] as? [String: Any]
        #expect(res?["isError"] as? Bool == true)
    }

    @Test("MCPServer 资源未找到显式返回：resources/read 请求未知 URI")
    func testMCPServerResourceNotFound() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 104,
            "method": "resources/read",
            "params": [
                "uri": "unknown://path"
            ]
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let err = resp?["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32602)
    }
}
