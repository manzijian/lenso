import Foundation
import AppKit
import os

let mcpLog = Logger(subsystem: "com.lenso.app", category: "mcp")

/// LENSO 内置 Model Context Protocol (MCP) 服务器
/// 协议版本：2024-11-05 (JSON-RPC 2.0 over stdio)
/// 外部 AI 客户端（Claude Desktop、Cursor、Antigravity、VS Code 等）可直接连接此服务，
/// 读取最近复制的文字、截图历史、搜索剪贴板并向剪贴板写入内容。
final class LensoMCPServer: @unchecked Sendable {

    nonisolated(unsafe) static let shared = LensoMCPServer()

    static func run() {
        let server = LensoMCPServer()
        server.startStdioLoop()
    }

    let store = ScreenshotStore.shared
    let isoFormatter = ISO8601DateFormatter()
    private let lock = NSLock()
    private var responseCallback: (([String: Any]) -> Void)?

    /// 提供给本地 HTTP / SSE 服务的请求处理入口
    func process(json: [String: Any]) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        var captured: [String: Any]?
        responseCallback = { resp in
            captured = resp
        }
        handleMessage(json)
        responseCallback = nil
        return captured
    }

    private func startStdioLoop() {
        let input = FileHandle.standardInput

        while true {
            guard let lineData = readNextLine(from: input), !lineData.isEmpty else {
                break
            }

            let json: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    sendError(id: nil, code: -32600, message: "Invalid JSON-RPC payload")
                    continue
                }
                json = parsed
            } catch {
                mcpLog.error("JSON parse error from stdio: \(error.localizedDescription)")
                sendError(id: nil, code: -32700, message: "Parse error: \(error.localizedDescription)")
                continue
            }

            handleMessage(json)
        }
    }

    private func readNextLine(from handle: FileHandle) -> Data? {
        var buffer = Data()
        while true {
            let chunk = handle.readData(ofLength: 1)
            if chunk.isEmpty {
                return buffer.isEmpty ? nil : buffer
            }
            if chunk[0] == 0x0A { // \n
                return buffer
            }
            buffer.append(chunk)
        }
    }

    func sendResponse(id: Any?, result: Any) {
        sendRaw(MCPMessageCodec.makeResponse(id: id, result: result))
    }

    func sendError(id: Any?, code: Int, message: String) {
        sendRaw(MCPMessageCodec.makeErrorResponse(id: id, code: code, message: message))
    }

    func sendRaw(_ dict: [String: Any]) {
        if let callback = responseCallback {
            callback(dict)
            return
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: dict)
        } catch {
            mcpLog.error("Failed to serialize outgoing MCP response: \(error.localizedDescription)")
            return
        }
        guard var str = String(data: data, encoding: .utf8) else { return }
        str.append("\n")
        if let outData = str.data(using: .utf8) {
            FileHandle.standardOutput.write(outData)
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        let method = json["method"] as? String ?? ""
        let id = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            handleInitialize(id: id, params: params)

        case "notifications/initialized":
            // 客户端连接确认通知，无需响应
            break

        case "ping":
            sendResponse(id: id, result: ["status": "ok"])

        case "tools/list":
            handleToolsList(id: id)

        case "tools/call":
            handleToolsCall(id: id, params: params)

        case "resources/list":
            handleResourcesList(id: id)

        case "resources/read":
            handleResourcesRead(id: id, params: params)

        default:
            if id != nil {
                sendError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    // MARK: - Handlers

    private func handleInitialize(id: Any?, params: [String: Any]) {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [
                    "listChanged": false
                ],
                "resources": [
                    "subscribe": false,
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": "lenso-mcp",
                "version": "1.0.0"
            ],
            "instructions": "LENSO MCP 服务：可检索和读取用户在 macOS 上最近复制的文字、截图历史及便签，支持写入系统剪贴板。"
        ]
        sendResponse(id: id, result: result)
    }

    private func handleResourcesList(id: Any?) {
        let resources: [[String: Any]] = [
            [
                "uri": "clipboard://recent",
                "name": "最近剪贴板记录 (JSON)",
                "description": "包含最新复制的 50 条图文剪贴板数据",
                "mimeType": "application/json"
            ],
            [
                "uri": "screenshots://recent",
                "name": "最近截图记录 (JSON)",
                "description": "包含最新截取的 30 张屏幕截图元数据与文件路径",
                "mimeType": "application/json"
            ]
        ]
        sendResponse(id: id, result: ["resources": resources])
    }

    private func handleResourcesRead(id: Any?, params: [String: Any]) {
        let uri = params["uri"] as? String ?? ""
        if uri == "clipboard://recent" {
            let items: [ClipboardItem]
            do {
                items = try store.listClipboard(limit: 50)
            } catch {
                mcpLog.error("resources/read listClipboard error: \(error.localizedDescription)")
                sendError(id: id, code: -32603, message: "Internal error: \(error.localizedDescription)")
                return
            }
            let list = items.map { item -> [String: Any] in
                var d: [String: Any] = [
                    "id": item.id.uuidString,
                    "kind": item.kind.rawValue,
                    "source_app": item.sourceApp ?? "Unknown",
                    "created_at": isoFormatter.string(from: item.createdAt)
                ]
                if item.kind == .text {
                    d["content"] = item.text ?? ""
                } else if item.kind == .image {
                    d["image_file_path"] = store.clipboardImageURL(item)?.path ?? ""
                }
                return d
            }
            let text: String
            do {
                let data = try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted])
                text = String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                mcpLog.error("resources/read JSON serialize error: \(error.localizedDescription)")
                sendError(id: id, code: -32603, message: "Internal error: \(error.localizedDescription)")
                return
            }
            sendResponse(id: id, result: [
                "contents": [
                    [
                        "uri": uri,
                        "mimeType": "application/json",
                        "text": text
                    ]
                ]
            ])
        } else if uri == "screenshots://recent" {
            let records: [ScreenshotRecord]
            do {
                records = try store.list()
            } catch {
                mcpLog.error("resources/read list screenshots error: \(error.localizedDescription)")
                sendError(id: id, code: -32603, message: "Internal error: \(error.localizedDescription)")
                return
            }
            let list = records.prefix(30).map { r -> [String: Any] in
                return [
                    "id": r.id.uuidString,
                    "filename": r.filename,
                    "file_path": store.screenshotOriginalURL(r)?.path ?? "",
                    "width": r.width,
                    "height": r.height,
                    "captured_at": isoFormatter.string(from: r.capturedAt)
                ]
            }
            let text: String
            do {
                let data = try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted])
                text = String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                mcpLog.error("resources/read JSON serialize error: \(error.localizedDescription)")
                sendError(id: id, code: -32603, message: "Internal error: \(error.localizedDescription)")
                return
            }
            sendResponse(id: id, result: [
                "contents": [
                    [
                        "uri": uri,
                        "mimeType": "application/json",
                        "text": text
                    ]
                ]
            ])
        } else {
            sendError(id: id, code: -32602, message: "Resource not found: \(uri)")
        }
    }
}
