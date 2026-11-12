import Foundation

public enum JSONRPCErrorCode: Int, Sendable {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}

public struct MCPRequest: Equatable, @unchecked Sendable {
    public let id: AnyHashable?
    public let method: String
    public let params: [String: Any]

    public init(id: AnyHashable?, method: String, params: [String: Any] = [:]) {
        self.id = id
        self.method = method
        self.params = params
    }

    public static func == (lhs: MCPRequest, rhs: MCPRequest) -> Bool {
        return lhs.id == rhs.id && lhs.method == rhs.method
    }
}

public struct MCPCodecError: Error, LocalizedError, Equatable, Sendable {
    public let code: JSONRPCErrorCode
    public let message: String

    public var errorDescription: String? { message }
}

public enum MCPMessageCodec: Sendable {

    // MARK: - JSON-RPC Parsing

    public static func parseRequest(data: Data) throws -> MCPRequest {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dict = jsonObject as? [String: Any] else {
            throw MCPCodecError(code: .parseError, message: "Parse error: invalid JSON")
        }
        return try parseRequest(dict: dict)
    }

    public static func parseRequest(dict: [String: Any]) throws -> MCPRequest {
        guard let method = dict["method"] as? String, !method.isEmpty else {
            throw MCPCodecError(code: .invalidRequest, message: "Invalid Request: missing or invalid method")
        }

        let rawId = dict["id"]
        var id: AnyHashable? = nil
        if let s = rawId as? String {
            id = s
        } else if let n = rawId as? NSNumber {
            id = n.intValue
        }

        let params = dict["params"] as? [String: Any] ?? [:]
        return MCPRequest(id: id, method: method, params: params)
    }

    // MARK: - JSON-RPC Responses

    public static func makeResponse(id: Any?, result: Any) -> [String: Any] {
        return [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
    }

    public static func makeErrorResponse(id: Any?, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var errDict: [String: Any] = [
            "code": code,
            "message": message
        ]
        if let data = data {
            errDict["data"] = data
        }
        return [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": errDict
        ]
    }

    public static func encodeJSON(_ object: Any, prettyPrinted: Bool = false) throws -> Data {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted] : []
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    // MARK: - Tool Results

    public static func makeToolTextContent(text: String, isError: Bool = false) -> [String: Any] {
        var dict: [String: Any] = [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ]
        ]
        if isError {
            dict["isError"] = true
        }
        return dict
    }

    // MARK: - SSE Framing

    public static func formatSSEEndpoint(sessionId: String) -> String {
        return "event: endpoint\r\ndata: /message?sessionId=\(sessionId)\r\n\r\n"
    }

    public static func formatSSEMessage(jsonString: String) -> String {
        return "event: message\r\ndata: \(jsonString)\r\n\r\n"
    }

    public static func parseSSEFrame(_ frame: String) -> (event: String?, data: String?) {
        var event: String? = nil
        var dataLines: [String] = []

        let normalized = frame.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("event:") {
                let val = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                event = val
            } else if line.hasPrefix("data:") {
                let val = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                dataLines.append(val)
            }
        }
        let data = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        return (event, data)
    }

    // MARK: - HTTP Header Parsing

    public struct HTTPHeaderInfo: Equatable, Sendable {
        public let method: String
        public let fullPath: String
        public let path: String
        public let queryItems: [String: String]
        public let contentLength: Int
    }

    public static func parseHTTPHeader(_ headerString: String) -> HTTPHeaderInfo? {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0].uppercased()
        let fullPath = requestParts[1]

        var contentLength = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 && parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1]) ?? 0
            }
        }

        let components = URLComponents(string: fullPath)
        let path = components?.path ?? fullPath
        var queries: [String: String] = [:]
        if let queryItems = components?.queryItems {
            for q in queryItems {
                queries[q.name] = q.value ?? ""
            }
        }

        return HTTPHeaderInfo(
            method: method,
            fullPath: fullPath,
            path: path,
            queryItems: queries,
            contentLength: contentLength
        )
    }
}
