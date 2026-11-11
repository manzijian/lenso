import Foundation
import AppKit

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

    private let store = ScreenshotStore.shared
    private let isoFormatter = ISO8601DateFormatter()
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

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
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

    private func sendResponse(id: Any?, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
        sendRaw(response)
    }

    private func sendError(id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendRaw(response)
    }

    private func sendRaw(_ dict: [String: Any]) {
        if let callback = responseCallback {
            callback(dict)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              var str = String(data: data, encoding: .utf8) else { return }
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

    private func handleToolsList(id: Any?) {
        let tools: [[String: Any]] = [
            [
                "name": "lenso_get_recent_clipboard",
                "description": "获取用户最近的剪贴板历史记录（包含复制的文字与图片，按时间倒序排列，包含来源应用信息）",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "number",
                            "description": "返回条目上限（默认 20，最多 100）"
                        ],
                        "kind": [
                            "type": "string",
                            "enum": ["all", "text", "image"],
                            "description": "过滤类型：all 全部，text 纯文字，image 图片"
                        ],
                        "query": [
                            "type": "string",
                            "description": "可选的搜索关键字，按内容或来源应用过滤"
                        ]
                    ]
                ]
            ],
            [
                "name": "lenso_search_history",
                "description": "全局搜索剪贴板历史、截图记录与收纳便签，按相关度与时间综合排序",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "需要搜索的关键词"
                        ],
                        "limit": [
                            "type": "number",
                            "description": "返回条目上限（默认 20）"
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "lenso_get_latest_screenshot",
                "description": "获取用户最新截取的一张截图元数据以及本地图片的绝对文件路径（便于直接查看或分析图片）",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "lenso_copy_text",
                "description": "将指定文本写入 macOS 系统剪贴板，并自动记录到 LENSO 剪贴板历史流中",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "需要写入剪贴板的纯文本内容"
                        ]
                    ],
                    "required": ["text"]
                ]
            ],
            [
                "name": "lenso_add_text_note",
                "description": "向 LENSO 添加一条文字收纳便签",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "content": [
                            "type": "string",
                            "description": "便签内容"
                        ],
                        "sourceApp": [
                            "type": "string",
                            "description": "来源标记（如 AI Assistant）"
                        ]
                    ],
                    "required": ["content"]
                ]
            ]
        ]

        sendResponse(id: id, result: ["tools": tools])
    }

    private func handleToolsCall(id: Any?, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "lenso_get_recent_clipboard":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 100)
            let kind = args["kind"] as? String ?? "all"
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)

            let items = (try? store.listClipboard(limit: 120)) ?? []
            var resultItems: [[String: Any]] = []

            for item in items {
                if kind == "text" && item.kind != .text { continue }
                if kind == "image" && item.kind != .image { continue }

                if !query.isEmpty {
                    let textMatch = item.text?.localizedCaseInsensitiveContains(query) ?? false
                    let appMatch = item.sourceApp?.localizedCaseInsensitiveContains(query) ?? false
                    if !textMatch && !appMatch { continue }
                }

                var dict: [String: Any] = [
                    "id": item.id.uuidString,
                    "kind": item.kind.rawValue,
                    "source_app": item.sourceApp ?? "Unknown",
                    "created_at": isoFormatter.string(from: item.createdAt)
                ]

                if item.kind == .text {
                    dict["content"] = item.text ?? ""
                    dict["char_count"] = (item.text ?? "").count
                } else if item.kind == .image {
                    let imagePath = store.clipboardImageURL(item)?.path
                    dict["image_file_path"] = imagePath ?? ""
                }

                resultItems.append(dict)
                if resultItems.count >= limit { break }
            }

            sendToolJsonResult(id: id, payload: [
                "count": resultItems.count,
                "items": resultItems
            ])

        case "lenso_search_history":
            guard let query = args["query"] as? String, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                sendToolError(id: id, message: "Missing required argument: query")
                return
            }
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 50)
            let q = query.trimmingCharacters(in: .whitespaces)

            var results: [[String: Any]] = []

            // 1. 搜剪贴板
            let clips = (try? store.listClipboard(limit: 100)) ?? []
            for c in clips {
                let match = (c.text?.localizedCaseInsensitiveContains(q) ?? false) || (c.sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
                if match {
                    results.append([
                        "id": c.id.uuidString,
                        "type": "clipboard",
                        "kind": c.kind.rawValue,
                        "title": c.text ?? "复制的图片",
                        "source_app": c.sourceApp ?? "",
                        "created_at": isoFormatter.string(from: c.createdAt)
                    ])
                }
            }

            // 2. 搜便签
            let notes = (try? store.listTextNotes()) ?? []
            for n in notes {
                if n.content.localizedCaseInsensitiveContains(q) || (n.sourceApp?.localizedCaseInsensitiveContains(q) ?? false) {
                    results.append([
                        "id": n.id.uuidString,
                        "type": "text_note",
                        "kind": "text",
                        "title": n.content,
                        "source_app": n.sourceApp ?? "收纳",
                        "created_at": isoFormatter.string(from: n.createdAt)
                    ])
                }
            }

            // 3. 搜截图
            let records = (try? store.list()) ?? []
            for r in records {
                if r.filename.localizedCaseInsensitiveContains(q) {
                    results.append([
                        "id": r.id.uuidString,
                        "type": "screenshot",
                        "kind": "image",
                        "title": r.filename,
                        "file_path": store.screenshotOriginalURL(r)?.path ?? "",
                        "dimensions": "\(r.width)x\(r.height)",
                        "created_at": isoFormatter.string(from: r.capturedAt)
                    ])
                }
            }

            let sliced = Array(results.prefix(limit))
            sendToolJsonResult(id: id, payload: [
                "query": q,
                "total_matched": results.count,
                "results": sliced
            ])

        case "lenso_get_latest_screenshot":
            let records = (try? store.list()) ?? []
            if let newest = records.first {
                let imagePath = store.screenshotOriginalURL(newest)?.path ?? ""
                let payload: [String: Any] = [
                    "id": newest.id.uuidString,
                    "filename": newest.filename,
                    "file_path": imagePath,
                    "width": newest.width,
                    "height": newest.height,
                    "file_size_bytes": newest.fileSize,
                    "is_favorite": newest.isFavorite,
                    "captured_at": isoFormatter.string(from: newest.capturedAt)
                ]
                sendToolJsonResult(id: id, payload: payload)
            } else {
                sendToolTextResult(id: id, text: "当前暂无截图记录。")
            }

        case "lenso_copy_text":
            guard let text = args["text"] as? String else {
                sendToolError(id: id, message: "Missing required argument: text")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            _ = try? store.saveClipboardText(text, sourceApp: "AI MCP Service")
            sendToolTextResult(id: id, text: "已成功将文本写入 macOS 剪贴板并归集到 LENSO 历史记录（共 \(text.count) 字符）。")

        case "lenso_add_text_note":
            guard let content = args["content"] as? String else {
                sendToolError(id: id, message: "Missing required argument: content")
                return
            }
            let sourceApp = args["sourceApp"] as? String ?? "AI Assistant"
            _ = try? store.createTextNote(content: content, sourceApp: sourceApp)
            sendToolTextResult(id: id, text: "已成功保存到 LENSO 文字收纳库。")

        default:
            sendToolError(id: id, message: "Unknown tool name: \(name)")
        }
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
            let items = (try? store.listClipboard(limit: 50)) ?? []
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
            let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted])) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? "[]"
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
            let records = (try? store.list()) ?? []
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
            let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted])) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? "[]"
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

    // MARK: - Helpers

    private func sendToolJsonResult(id: Any?, payload: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            sendToolError(id: id, message: "JSON serialization failed")
            return
        }
        sendToolTextResult(id: id, text: text)
    }

    private func sendToolTextResult(id: Any?, text: String) {
        sendResponse(id: id, result: [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ]
        ])
    }

    private func sendToolError(id: Any?, message: String) {
        sendResponse(id: id, result: [
            "content": [
                [
                    "type": "text",
                    "text": "Error: \(message)"
                ]
            ],
            "isError": true
        ])
    }
}
