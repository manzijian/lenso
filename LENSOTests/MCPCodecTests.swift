import Testing
import Foundation
@testable import LENSO

@Suite("MCP 与本地服务协议编解码测试")
struct MCPCodecTests {

    // MARK: - 1. JSON-RPC 解析测试

    @Test("解析 initialize 请求：正确提取 method 与 id")
    func testParseInitialize() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "clientInfo": {
                    "name": "test-client",
                    "version": "1.0.0"
                }
            }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let req = try MCPMessageCodec.parseRequest(data: data)

        #expect(req.method == "initialize")
        #expect(req.id == AnyHashable(1))
        let clientInfo = req.params["clientInfo"] as? [String: Any]
        #expect(clientInfo?["name"] as? String == "test-client")
    }

    @Test("解析 tools/list 请求：正确提取 method")
    func testParseToolsList() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "req-99",
            "method": "tools/list"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let req = try MCPMessageCodec.parseRequest(data: data)

        #expect(req.method == "tools/list")
        #expect(req.id == AnyHashable("req-99"))
        #expect(req.params.isEmpty)
    }

    @Test("解析 tools/call 请求：正确提取工具名称与入参")
    func testParseToolsCall() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 42,
            "method": "tools/call",
            "params": {
                "name": "lenso_copy_text",
                "arguments": {
                    "text": "Hello MCP"
                }
            }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let req = try MCPMessageCodec.parseRequest(data: data)

        #expect(req.method == "tools/call")
        #expect(req.id == AnyHashable(42))
        #expect(req.params["name"] as? String == "lenso_copy_text")
        let args = req.params["arguments"] as? [String: Any]
        #expect(args?["text"] as? String == "Hello MCP")
    }

    // MARK: - 2. 非法报文与错误处理

    @Test("非法 JSON 报文：抛出 -32700 parseError")
    func testParseInvalidJSON() {
        let invalidData = "This is not json { [".data(using: .utf8)!
        #expect(throws: MCPCodecError.self) {
            _ = try MCPMessageCodec.parseRequest(data: invalidData)
        }
    }

    @Test("缺失 method：抛出 -32600 invalidRequest")
    func testParseMissingMethod() {
        let json = "{\"id\": 10, \"params\": {}}".data(using: .utf8)!
        #expect(throws: MCPCodecError.self) {
            _ = try MCPMessageCodec.parseRequest(data: json)
        }
    }

    // MARK: - 3. 响应构造测试

    @Test("构造标准成功响应：含 jsonrpc, id 与 result")
    func testMakeSuccessResponse() {
        let resp = MCPMessageCodec.makeResponse(id: 123, result: ["status": "ok"])
        #expect(resp["jsonrpc"] as? String == "2.0")
        #expect(resp["id"] as? Int == 123)
        let res = resp["result"] as? [String: String]
        #expect(res?["status"] == "ok")
    }

    @Test("构造标准错误响应：含 code 与 message")
    func testMakeErrorResponse() {
        let resp = MCPMessageCodec.makeErrorResponse(id: "req-1", code: -32601, message: "Method not found")
        #expect(resp["jsonrpc"] as? String == "2.0")
        #expect(resp["id"] as? String == "req-1")
        let err = resp["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32601)
        #expect(err?["message"] as? String == "Method not found")
    }

    @Test("构造工具文本结果：标准 content 格式与 isError 标识")
    func testMakeToolContentResult() {
        let ok = MCPMessageCodec.makeToolTextContent(text: "done", isError: false)
        #expect(ok["isError"] == nil)
        let content = ok["content"] as? [[String: Any]]
        #expect(content?.first?["text"] as? String == "done")

        let fail = MCPMessageCodec.makeToolTextContent(text: "error info", isError: true)
        #expect(fail["isError"] as? Bool == true)
    }

    // MARK: - 4. SSE 帧构造与解析测试

    @Test("SSE Endpoint 帧格式与解析")
    func testSSEEndpointFraming() {
        let frame = MCPMessageCodec.formatSSEEndpoint(sessionId: "test-session-123")
        #expect(frame.contains("event: endpoint"))
        #expect(frame.contains("data: /message?sessionId=test-session-123"))

        let parsed = MCPMessageCodec.parseSSEFrame(frame)
        #expect(parsed.event == "endpoint")
        #expect(parsed.data == "/message?sessionId=test-session-123")
    }

    @Test("SSE Message 帧格式与解析")
    func testSSEMessageFraming() {
        let jsonStr = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"status\":\"ok\"}}"
        let frame = MCPMessageCodec.formatSSEMessage(jsonString: jsonStr)
        #expect(frame.contains("event: message"))
        #expect(frame.contains("data: \(jsonStr)"))

        let parsed = MCPMessageCodec.parseSSEFrame(frame)
        #expect(parsed.event == "message")
        #expect(parsed.data == jsonStr)
    }

    // MARK: - 5. 本地服务 HTTP 协议头解析（免监听端口）

    @Test("HTTP 请求头解析：GET /sse")
    func testParseHTTPHeaderSSE() {
        let raw = """
        GET /sse HTTP/1.1\r
        Host: 127.0.0.1:52888\r
        Accept: text/event-stream\r
        \r
        """
        let info = MCPMessageCodec.parseHTTPHeader(raw)
        #expect(info != nil)
        #expect(info?.method == "GET")
        #expect(info?.path == "/sse")
        #expect(info?.contentLength == 0)
    }

    @Test("HTTP 请求头解析：POST /message 带 query 与 Content-Length")
    func testParseHTTPHeaderPostMessage() {
        let raw = """
        POST /message?sessionId=abc-456 HTTP/1.1\r
        Host: 127.0.0.1:52888\r
        Content-Type: application/json\r
        Content-Length: 128\r
        \r
        """
        let info = MCPMessageCodec.parseHTTPHeader(raw)
        #expect(info != nil)
        #expect(info?.method == "POST")
        #expect(info?.path == "/message")
        #expect(info?.queryItems["sessionId"] == "abc-456")
        #expect(info?.contentLength == 128)
    }

    // MARK: - 6. LensoMCPServer.shared.process 独立调用

    @Test("MCPServer 纯逻辑处理：ping 方法返回 status ok")
    func testMCPServerProcessPing() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "ping"
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        #expect(resp?["id"] as? Int == 1)
        let res = resp?["result"] as? [String: Any]
        #expect(res?["status"] as? String == "ok")
    }

    @Test("MCPServer 纯逻辑处理：tools/list 返回内置工具集")
    func testMCPServerProcessToolsList() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "list-1",
            "method": "tools/list"
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let res = resp?["result"] as? [String: Any]
        let tools = res?["tools"] as? [[String: Any]]
        #expect(tools != nil)
        let toolNames = tools?.compactMap { $0["name"] as? String } ?? []
        #expect(toolNames.contains("lenso_get_recent_clipboard"))
        #expect(toolNames.contains("lenso_search_history"))
        #expect(toolNames.contains("lenso_copy_text"))
    }

    @Test("MCPServer 纯逻辑处理：未定义方法返回 -32601 错误")
    func testMCPServerProcessMethodNotFound() {
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 999,
            "method": "unknown_future_method"
        ]
        let resp = LensoMCPServer.shared.process(json: req)
        #expect(resp != nil)
        let err = resp?["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32601)
    }
}
