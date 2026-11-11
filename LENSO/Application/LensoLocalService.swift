import Foundation
import Network
import AppKit

/// LENSO 本地 HTTP / SSE / MCP 混合网络服务
/// 监听 127.0.0.1:52888 本地环回地址，为外部 AI Agent（Claude、Cursor、Antigravity、Windsurf 等）
/// 以及本地脚本提供免配置的剪贴板历史与截图读取能力。
final class LensoLocalService: @unchecked Sendable {
    static let shared = LensoLocalService()

    static let defaultPort: UInt16 = 52888

    private(set) var isRunning: Bool = false
    private(set) var currentPort: UInt16 = defaultPort
    private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.lenso.localservice", qos: .userInitiated)
    private let isoFormatter = ISO8601DateFormatter()

    // 活跃的 SSE 客户端连接：sessionId -> NWConnection
    private var sseClients: [String: NWConnection] = [:]
    private let sseLock = NSLock()

    private init() {}

    func start(port: UInt16 = defaultPort) {
        guard !isRunning else { return }

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 15

            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback // 仅允许本机访问，确保安全

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                self.lastError = "Invalid port \(port)"
                return
            }

            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.currentPort = port
                    self.lastError = nil
                    print("[LensoLocalService] Ready and listening on http://127.0.0.1:\(port)")
                case .failed(let error):
                    self.isRunning = false
                    self.lastError = error.localizedDescription
                    print("[LensoLocalService] Failed with error: \(error)")
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            listener.start(queue: queue)
        } catch {
            self.lastError = error.localizedDescription
            print("[LensoLocalService] Could not start listener: \(error)")
        }
    }

    func stop() {
        sseLock.lock()
        for (_, conn) in sseClients {
            conn.cancel()
        }
        sseClients.removeAll()
        sseLock.unlock()

        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection Handling

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection)
    }

    private func readHTTPRequest(connection: NWConnection, accumulatedData: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var data = accumulatedData
            if let content = content {
                data.append(content)
            }

            // 检查是否已收到完整的 HTTP Header (\r\n\r\n)
            let headerDelimiter = Data("\r\n\r\n".utf8)
            if let range = data.range(of: headerDelimiter) {
                let headerData = data.subdata(in: 0..<range.lowerBound)
                let bodyData = data.subdata(in: range.upperBound..<data.count)

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                let lines = headerString.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else {
                    connection.cancel()
                    return
                }

                let requestParts = requestLine.components(separatedBy: " ")
                guard requestParts.count >= 2 else {
                    connection.cancel()
                    return
                }

                let method = requestParts[0].uppercased()
                let fullPath = requestParts[1]

                // 解析 Content-Length
                var contentLength = 0
                for line in lines.dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 && parts[0].lowercased() == "content-length" {
                        contentLength = Int(parts[1]) ?? 0
                    }
                }

                if bodyData.count < contentLength {
                    // Body 还没收全，继续接收
                    self.readHTTPRequest(connection: connection, accumulatedData: data)
                    return
                }

                // 完整收到请求，分发路由
                self.dispatchRequest(
                    method: method,
                    fullPath: fullPath,
                    bodyData: bodyData.prefix(contentLength),
                    connection: connection
                )
            } else if !isComplete {
                // Header 还没收全，继续接收
                self.readHTTPRequest(connection: connection, accumulatedData: data)
            } else {
                connection.cancel()
            }
        }
    }

    // MARK: - HTTP Router

    private func dispatchRequest(method: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        // CORS 预检
        if method == "OPTIONS" {
            sendCORSPreflightResponse(connection: connection)
            return
        }

        let urlComponents = URLComponents(string: fullPath)
        let path = urlComponents?.path ?? fullPath
        let queryItems = urlComponents?.queryItems ?? []

        switch (method, path) {
        case ("GET", "/sse"):
            handleSSEConnection(connection: connection)

        case ("POST", "/message"):
            let sessionId = queryItems.first(where: { $0.name == "sessionId" })?.value ?? ""
            handleMessagePost(sessionId: sessionId, bodyData: bodyData, connection: connection)

        case ("POST", "/mcp"), ("POST", "/"):
            handleDirectJSONRPC(bodyData: bodyData, connection: connection)

        case ("GET", "/api/clipboard"):
            handleGetClipboard(queryItems: queryItems, connection: connection)

        case ("GET", "/api/screenshot/latest"):
            handleGetLatestScreenshot(connection: connection)

        case ("GET", "/status"), ("GET", "/"):
            handleGetStatus(connection: connection)

        default:
            sendJSONResponse(
                connection: connection,
                statusCode: 404,
                statusText: "Not Found",
                payload: ["error": "Endpoint not found", "path": path]
            )
        }
    }

    // MARK: - Route Handlers

    private func sendCORSPreflightResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization, Accept\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r\n
        """
        sendRawString(connection: connection, string: response, closeAfter: true)
    }

    private func handleSSEConnection(connection: NWConnection) {
        let sessionId = UUID().uuidString

        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r\n
        """
        sendRawString(connection: connection, string: headers, closeAfter: false)

        // 发送 MCP SSE 握手 endpoint 消息
        let endpointEvent = "event: endpoint\r\ndata: /message?sessionId=\(sessionId)\r\n\r\n"
        sendRawString(connection: connection, string: endpointEvent, closeAfter: false)

        sseLock.lock()
        sseClients[sessionId] = connection
        sseLock.unlock()

        // 监听断开清理
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state, case .cancelled = state {
                self?.sseLock.lock()
                self?.sseClients.removeValue(forKey: sessionId)
                self?.sseLock.unlock()
            }
        }
    }

    private func handleMessagePost(sessionId: String, bodyData: Data, connection: NWConnection) {
        guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
            sendJSONResponse(connection: connection, statusCode: 400, statusText: "Bad Request", payload: ["error": "Invalid JSON"])
            return
        }

        let result = LensoMCPServer.shared.process(json: json)

        if !sessionId.isEmpty {
            sseLock.lock()
            let sseConn = sseClients[sessionId]
            sseLock.unlock()

            if let sseConn = sseConn, let result = result,
               let resData = try? JSONSerialization.data(withJSONObject: result),
               let resStr = String(data: resData, encoding: .utf8) {
                // 通过 SSE 发送
                let sseMessage = "event: message\r\ndata: \(resStr)\r\n\r\n"
                sendRawString(connection: sseConn, string: sseMessage, closeAfter: false)

                // 对 POST 连接回复 202 Accepted
                let okResponse = """
                HTTP/1.1 202 Accepted\r
                Access-Control-Allow-Origin: *\r
                Content-Type: text/plain\r
                Content-Length: 2\r
                \r
                OK
                """
                sendRawString(connection: connection, string: okResponse, closeAfter: true)
                return
            }
        }

        // 如果没有 SSE 连接，直接通过 HTTP 200 返回结果
        if let result = result {
            sendJSONResponse(connection: connection, statusCode: 200, statusText: "OK", payload: result)
        } else {
            sendJSONResponse(connection: connection, statusCode: 204, statusText: "No Content", payload: [:])
        }
    }

    private func handleDirectJSONRPC(bodyData: Data, connection: NWConnection) {
        guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
            sendJSONResponse(connection: connection, statusCode: 400, statusText: "Bad Request", payload: ["error": "Invalid JSON"])
            return
        }

        if let result = LensoMCPServer.shared.process(json: json) {
            sendJSONResponse(connection: connection, statusCode: 200, statusText: "OK", payload: result)
        } else {
            sendJSONResponse(connection: connection, statusCode: 204, statusText: "No Content", payload: [:])
        }
    }

    private func handleGetClipboard(queryItems: [URLQueryItem], connection: NWConnection) {
        let limit = min(max(Int(queryItems.first(where: { $0.name == "limit" })?.value ?? "") ?? 30, 1), 100)
        let kindFilter = queryItems.first(where: { $0.name == "kind" })?.value ?? "all"

        let items = (try? ScreenshotStore.shared.listClipboard(limit: 120)) ?? []
        var resultList: [[String: Any]] = []

        for item in items {
            if kindFilter == "text" && item.kind != .text { continue }
            if kindFilter == "image" && item.kind != .image { continue }

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
                dict["image_file_path"] = ScreenshotStore.shared.clipboardImageURL(item)?.path ?? ""
            }

            resultList.append(dict)
            if resultList.count >= limit { break }
        }

        sendJSONResponse(connection: connection, statusCode: 200, statusText: "OK", payload: [
            "status": "ok",
            "count": resultList.count,
            "items": resultList
        ])
    }

    private func handleGetLatestScreenshot(connection: NWConnection) {
        let records = (try? ScreenshotStore.shared.list()) ?? []
        if let newest = records.first {
            let path = ScreenshotStore.shared.screenshotOriginalURL(newest)?.path ?? ""
            let payload: [String: Any] = [
                "status": "ok",
                "screenshot": [
                    "id": newest.id.uuidString,
                    "filename": newest.filename,
                    "file_path": path,
                    "width": newest.width,
                    "height": newest.height,
                    "file_size_bytes": newest.fileSize,
                    "is_favorite": newest.isFavorite,
                    "captured_at": isoFormatter.string(from: newest.capturedAt)
                ]
            ]
            sendJSONResponse(connection: connection, statusCode: 200, statusText: "OK", payload: payload)
        } else {
            sendJSONResponse(connection: connection, statusCode: 404, statusText: "Not Found", payload: [
                "status": "empty",
                "message": "当前暂无截图记录"
            ])
        }
    }

    private func handleGetStatus(connection: NWConnection) {
        let payload: [String: Any] = [
            "status": "online",
            "app": "LENSO",
            "service": "Lenso Local Assistant & MCP Service",
            "version": "1.0.0",
            "port": currentPort,
            "endpoints": [
                "mcp_sse": "http://127.0.0.1:\(currentPort)/sse",
                "mcp_http": "http://127.0.0.1:\(currentPort)/mcp",
                "clipboard_api": "http://127.0.0.1:\(currentPort)/api/clipboard",
                "latest_screenshot_api": "http://127.0.0.1:\(currentPort)/api/screenshot/latest"
            ],
            "docs": "可以直接使用 GET /api/clipboard 获取最近剪贴板，或添加 mcpServers 指向 /sse"
        ]
        sendJSONResponse(connection: connection, statusCode: 200, statusText: "OK", payload: payload)
    }

    // MARK: - Response Helpers

    private func sendJSONResponse(connection: NWConnection, statusCode: Int, statusText: String, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let headers = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Access-Control-Allow-Origin: *\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        \r\n
        """

        let full = headers + jsonString
        sendRawString(connection: connection, string: full, closeAfter: true)
    }

    private func sendRawString(connection: NWConnection, string: String, closeAfter: Bool) {
        guard let data = string.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak connection] _ in
            if closeAfter {
                connection?.cancel()
            }
        })
    }
}
