import Foundation
import AppKit

extension LensoMCPServer {

    func handleToolsList(id: Any?) {
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
            ],
            [
                "name": "lenso_list_screenshots",
                "description": "列出截图记录（按时间倒序），可按天数范围、是否收藏、来源应用过滤，返回文件路径便于直接读取图片",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "number",
                            "description": "返回条目上限（默认 20，最多 100）"
                        ],
                        "days": [
                            "type": "number",
                            "description": "只返回最近 N 天的截图，不传则不限"
                        ],
                        "favorite_only": [
                            "type": "boolean",
                            "description": "仅返回已收藏的截图"
                        ],
                        "source_app": [
                            "type": "string",
                            "description": "按来源应用名过滤（模糊匹配）"
                        ]
                    ]
                ]
            ],
            [
                "name": "lenso_get_text_notes",
                "description": "读取 LENSO 文字收纳库中的便签内容（按时间倒序），可按关键词过滤",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "number",
                            "description": "返回条目上限（默认 20，最多 100）"
                        ],
                        "query": [
                            "type": "string",
                            "description": "可选的关键词过滤"
                        ]
                    ]
                ]
            ],
            [
                "name": "lenso_set_screenshot_favorite",
                "description": "收藏或取消收藏一张截图",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "截图 ID（可用 lenso_list_screenshots 获取）"
                        ],
                        "favorite": [
                            "type": "boolean",
                            "description": "true 收藏，false 取消收藏"
                        ]
                    ],
                    "required": ["id", "favorite"]
                ]
            ],
            [
                "name": "lenso_set_text_note_favorite",
                "description": "收藏或取消收藏一条文字便签",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "便签 ID（可用 lenso_get_text_notes 获取）"
                        ],
                        "favorite": [
                            "type": "boolean",
                            "description": "true 收藏，false 取消收藏"
                        ]
                    ],
                    "required": ["id", "favorite"]
                ]
            ],
            [
                "name": "lenso_delete_item",
                "description": "删除一条截图、文字便签或剪贴板记录（不可恢复，调用前请先确认目标 ID）",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "type": [
                            "type": "string",
                            "enum": ["screenshot", "text_note", "clipboard"],
                            "description": "要删除的条目类型"
                        ],
                        "id": [
                            "type": "string",
                            "description": "条目 UUID"
                        ]
                    ],
                    "required": ["type", "id"]
                ]
            ]
        ]

        sendResponse(id: id, result: ["tools": tools])
    }

    func handleToolsCall(id: Any?, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "lenso_get_recent_clipboard":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 100)
            let kind = args["kind"] as? String ?? "all"
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)

            let items: [ClipboardItem]
            do {
                items = try store.listClipboard(limit: 120)
            } catch {
                mcpLog.error("lenso_get_recent_clipboard storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "获取剪贴板记录失败: \(error.localizedDescription)")
                return
            }
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

            let clips: [ClipboardItem]
            let notes: [TextNote]
            let records: [ScreenshotRecord]
            do {
                clips = try store.listClipboard(limit: 100)
                notes = try store.listTextNotes()
                records = try store.list()
            } catch {
                mcpLog.error("lenso_search_history storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "全局搜索失败: \(error.localizedDescription)")
                return
            }

            // 1. 搜剪贴板
            for c in clips {
                let match = (c.text?.localizedCaseInsensitiveContains(q) ?? false) || (c.sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
                if match {
                    var dict: [String: Any] = [
                        "id": c.id.uuidString,
                        "type": "clipboard",
                        "kind": c.kind.rawValue,
                        "title": Self.previewText(c.text ?? "复制的图片"),
                        "source_app": c.sourceApp ?? "",
                        "created_at": isoFormatter.string(from: c.createdAt)
                    ]
                    if c.kind == .image {
                        dict["image_file_path"] = store.clipboardImageURL(c)?.path ?? ""
                    } else {
                        dict["content"] = c.text ?? ""
                    }
                    results.append(dict)
                }
            }

            // 2. 搜便签
            for n in notes {
                if n.content.localizedCaseInsensitiveContains(q) || (n.sourceApp?.localizedCaseInsensitiveContains(q) ?? false) {
                    results.append([
                        "id": n.id.uuidString,
                        "type": "text_note",
                        "kind": "text",
                        "title": Self.previewText(n.content),
                        "content": n.content,
                        "source_app": n.sourceApp ?? "收纳",
                        "created_at": isoFormatter.string(from: n.createdAt)
                    ])
                }
            }

            // 3. 搜截图（文件名、来源应用、尺寸都能命中）
            for r in records {
                let dimension = "\(r.width)x\(r.height)"
                let match = r.filename.localizedCaseInsensitiveContains(q)
                    || (r.sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
                    || dimension.localizedCaseInsensitiveContains(q)
                if match {
                    results.append([
                        "id": r.id.uuidString,
                        "type": "screenshot",
                        "kind": "image",
                        "title": r.filename,
                        "file_path": store.screenshotOriginalURL(r)?.path ?? "",
                        "source_app": r.sourceApp ?? "",
                        "dimensions": dimension,
                        "is_favorite": r.isFavorite,
                        "created_at": isoFormatter.string(from: r.capturedAt)
                    ])
                }
            }

            // 按时间倒序后再截断，保证返回的是最新命中的结果
            results.sort { ($0["created_at"] as? String ?? "") > ($1["created_at"] as? String ?? "") }

            let sliced = Array(results.prefix(limit))
            sendToolJsonResult(id: id, payload: [
                "query": q,
                "total_matched": results.count,
                "results": sliced
            ])

        case "lenso_get_latest_screenshot":
            let records: [ScreenshotRecord]
            do {
                records = try store.list()
            } catch {
                mcpLog.error("lenso_get_latest_screenshot storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "获取截图失败: \(error.localizedDescription)")
                return
            }
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
            // 写入前先标记为自己写入，否则剪贴板监听会再记一条，造成重复历史
            ClipboardMonitor.shared.markSelfWrite()
            do {
                _ = try store.saveClipboardText(text, sourceApp: "AI MCP Service")
            } catch {
                mcpLog.error("lenso_copy_text storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "写入系统剪贴板记录失败: \(error.localizedDescription)")
                return
            }
            sendToolTextResult(id: id, text: "已成功将文本写入 macOS 剪贴板并归集到 LENSO 历史记录（共 \(text.count) 字符）。")

        case "lenso_add_text_note":
            guard let content = args["content"] as? String else {
                sendToolError(id: id, message: "Missing required argument: content")
                return
            }
            let sourceApp = args["sourceApp"] as? String ?? "AI Assistant"
            do {
                _ = try store.createTextNote(content: content, sourceApp: sourceApp)
            } catch {
                mcpLog.error("lenso_add_text_note storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "保存文字便签失败: \(error.localizedDescription)")
                return
            }
            sendToolTextResult(id: id, text: "已成功保存到 LENSO 文字收纳库。")

        case "lenso_list_screenshots":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 100)
            let favoriteOnly = args["favorite_only"] as? Bool ?? false
            let sourceFilter = (args["source_app"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let days = args["days"] as? Int

            let records: [ScreenshotRecord]
            do {
                records = try store.list()
            } catch {
                mcpLog.error("lenso_list_screenshots storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "读取截图记录失败: \(error.localizedDescription)")
                return
            }

            let cutoff = days.map { Date().addingTimeInterval(-Double($0) * 86_400) }
            var items: [[String: Any]] = []
            for r in records {
                if favoriteOnly && !r.isFavorite { continue }
                if let cutoff, r.capturedAt < cutoff { continue }
                if !sourceFilter.isEmpty,
                   !(r.sourceApp?.localizedCaseInsensitiveContains(sourceFilter) ?? false) { continue }

                items.append([
                    "id": r.id.uuidString,
                    "filename": r.filename,
                    "file_path": store.screenshotOriginalURL(r)?.path ?? "",
                    "width": r.width,
                    "height": r.height,
                    "file_size_bytes": r.fileSize,
                    "source_app": r.sourceApp ?? "",
                    "is_favorite": r.isFavorite,
                    "captured_at": isoFormatter.string(from: r.capturedAt)
                ])
                if items.count >= limit { break }
            }

            sendToolJsonResult(id: id, payload: [
                "count": items.count,
                "items": items
            ])

        case "lenso_get_text_notes":
            let limit = min(max(args["limit"] as? Int ?? 20, 1), 100)
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)

            let notes: [TextNote]
            do {
                notes = try store.listTextNotes()
            } catch {
                mcpLog.error("lenso_get_text_notes storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "读取文字便签失败: \(error.localizedDescription)")
                return
            }

            var items: [[String: Any]] = []
            for n in notes {
                if !query.isEmpty,
                   !n.content.localizedCaseInsensitiveContains(query),
                   !(n.sourceApp?.localizedCaseInsensitiveContains(query) ?? false) { continue }
                items.append([
                    "id": n.id.uuidString,
                    "content": n.content,
                    "char_count": n.content.count,
                    "source_app": n.sourceApp ?? "",
                    "created_at": isoFormatter.string(from: n.createdAt)
                ])
                if items.count >= limit { break }
            }

            sendToolJsonResult(id: id, payload: [
                "count": items.count,
                "items": items
            ])

        case "lenso_set_screenshot_favorite":
            guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
                sendToolError(id: id, message: "Missing or invalid argument: id")
                return
            }
            guard let favorite = args["favorite"] as? Bool else {
                sendToolError(id: id, message: "Missing required argument: favorite")
                return
            }
            do {
                try store.setScreenshotFavorite(favorite, id: id)
            } catch {
                mcpLog.error("lenso_set_screenshot_favorite storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "更新截图收藏状态失败: \(error.localizedDescription)")
                return
            }
            NotificationCenter.default.post(name: .libraryChanged, object: nil)
            sendToolTextResult(id: id, text: favorite ? "已收藏该截图。" : "已取消收藏该截图。")

        case "lenso_set_text_note_favorite":
            guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
                sendToolError(id: id, message: "Missing or invalid argument: id")
                return
            }
            guard let favorite = args["favorite"] as? Bool else {
                sendToolError(id: id, message: "Missing required argument: favorite")
                return
            }
            do {
                try store.setTextNoteFavorite(favorite, id: id)
            } catch {
                mcpLog.error("lenso_set_text_note_favorite storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "更新便签收藏状态失败: \(error.localizedDescription)")
                return
            }
            NotificationCenter.default.post(name: .textNotesChanged, object: nil)
            sendToolTextResult(id: id, text: favorite ? "已收藏该便签。" : "已取消收藏该便签。")

        case "lenso_delete_item":
            guard let type = args["type"] as? String,
                  let idString = args["id"] as? String,
                  let targetID = UUID(uuidString: idString) else {
                sendToolError(id: id, message: "Missing or invalid arguments: type / id")
                return
            }
            let changed: Notification.Name
            do {
                switch type {
                case "screenshot":
                    guard let record = try store.list().first(where: { $0.id == targetID }) else {
                        sendToolError(id: id, message: "未找到该截图记录: \(idString)")
                        return
                    }
                    try store.delete(record)
                    changed = .libraryChanged
                case "text_note":
                    try store.deleteTextNote(id: targetID)
                    changed = .textNotesChanged
                case "clipboard":
                    try store.deleteClipboardItem(id: targetID)
                    changed = .libraryChanged
                default:
                    sendToolError(id: id, message: "Unsupported type: \(type)")
                    return
                }
            } catch {
                mcpLog.error("lenso_delete_item storage error: \(error.localizedDescription)")
                sendToolError(id: id, message: "删除失败: \(error.localizedDescription)")
                return
            }
            NotificationCenter.default.post(name: changed, object: nil)
            sendToolTextResult(id: id, text: "已删除该条目。")

        default:
            sendToolError(id: id, message: "Unknown tool name: \(name)")
        }
    }

    /// 列表里的标题类文本做截断，避免一次返回过长内容
    static func previewText(_ text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    func sendToolJsonResult(id: Any?, payload: Any) {
        let text: String
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            guard let s = String(data: data, encoding: .utf8) else {
                sendToolError(id: id, message: "UTF-8 encoding failed")
                return
            }
            text = s
        } catch {
            mcpLog.error("sendToolJsonResult serialization error: \(error.localizedDescription)")
            sendToolError(id: id, message: "JSON serialization failed: \(error.localizedDescription)")
            return
        }
        sendToolTextResult(id: id, text: text)
    }

    func sendToolTextResult(id: Any?, text: String) {
        sendResponse(id: id, result: MCPMessageCodec.makeToolTextContent(text: text))
    }

    func sendToolError(id: Any?, message: String) {
        markCallFailed(message)
        sendResponse(id: id, result: MCPMessageCodec.makeToolTextContent(text: "Error: \(message)", isError: true))
    }
}
