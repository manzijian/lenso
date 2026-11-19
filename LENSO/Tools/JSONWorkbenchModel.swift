import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - 模式定义

enum JSONViewMode: String, CaseIterable, Identifiable, Sendable {
    case edit = "编辑"
    case tree = "树"
    case table = "表格"
    case type = "类型"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .edit: "chevron.left.forwardslash.chevron.right"
        case .tree: "list.bullet.indent"
        case .table: "tablecells"
        case .type: "curlybraces.square"
        }
    }
}

enum JSONIndent: String, CaseIterable, Identifiable, Sendable {
    case two = "2 空格"
    case four = "4 空格"
    case tab = "Tab"
    var id: String { rawValue }

    var unit: String {
        switch self {
        case .two: "  "
        case .four: "    "
        case .tab: "\t"
        }
    }
}

enum JSONAction: String, CaseIterable, Identifiable, Sendable {
    case compress = "压缩"
    case sort = "排序键"
    case escape = "转义"
    case unescape = "反转义"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .sort: "arrow.up.arrow.down"
        case .escape: "text.badge.plus"
        case .unescape: "text.badge.minus"
        }
    }
}

// MARK: - 结果模型

struct JSONErrorInfo: Sendable, Equatable {
    let message: String
    let line: Int?
    let column: Int?
    let fatal: Bool
}

struct JSONMetrics: Sendable, Equatable {
    let nodes: Int
    let inputBytes: Int
    let outputBytes: Int
    let lines: Int
    let durationMS: Int
}

struct JSONTable: Sendable, Equatable {
    let columns: [String]
    let rows: [[String]]
    let totalRows: Int
    let truncated: Bool

    var tsv: String {
        ([columns] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }
}

struct JSONTreeNode: Identifiable, Sendable {
    let id = UUID()
    let key: String?
    let value: JSONValue
    let children: [JSONTreeNode]?
    let truncated: Bool

    var isContainer: Bool { children != nil }
}

/// 与 UI 无关的解析结果。全部在后台线程生成，主线程只做赋值。
struct JSONAnalysis: Sendable {
    let output: String
    let highlighted: AttributedString?
    let error: JSONErrorInfo?
    let metrics: JSONMetrics?
    let tree: JSONTreeNode?
    let table: JSONTable?
    let types: String

    static func failure(_ error: JSONErrorInfo) -> JSONAnalysis {
        JSONAnalysis(
            output: "", highlighted: nil, error: error,
            metrics: nil, tree: nil, table: nil, types: ""
        )
    }
}

// MARK: - 可观察模型

@Observable
@MainActor
final class JSONWorkbenchModel {
    var input: String = "" {
        didSet { if input != oldValue { schedule() } }
    }
    var viewMode: JSONViewMode = .edit {
        didSet { if viewMode != oldValue { schedule(immediate: true) } }
    }
    var indent: JSONIndent = .two {
        didSet { if indent != oldValue { schedule() } }
    }

    private(set) var output = ""
    private(set) var actionOutput: String?
    private(set) var actionLabel: String?
    private(set) var highlighted: AttributedString?
    private(set) var tree: JSONTreeNode?
    private(set) var table: JSONTable?
    private(set) var types = ""
    private(set) var error: JSONErrorInfo?
    private(set) var metrics: JSONMetrics?
    private(set) var isWorking = false
    private(set) var copied = false

    /// 超过该大小暂停自动处理，避免瞬时内存峰值拖慢整机。
    static let maxBytes = 4 * 1024 * 1024

    private var job: Task<Void, Never>?
    private var copyResetJob: Task<Void, Never>?

    init() {}

    var hasInput: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前展示的结果：一次性动作的结果优先，否则为自动格式化结果。
    var displayedOutput: String {
        actionOutput ?? output
    }

    var statusText: String {
        if let error {
            if let line = error.line, let column = error.column {
                return "第 \(line) 行，第 \(column) 列"
            }
            return error.message
        }
        guard let metrics else { return "等待输入" }
        return "JSON 有效 · \(metrics.nodes) 个节点"
    }

    // MARK: 调度

    func schedule(immediate: Bool = false) {
        job?.cancel()
        actionOutput = nil
        actionLabel = nil

        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearResult()
            return
        }
        guard text.utf8.count <= Self.maxBytes else {
            clearResult()
            error = JSONErrorInfo(
                message: "内容超过 4 MB，为保持流畅已暂停自动处理",
                line: nil, column: nil, fatal: true
            )
            return
        }

        isWorking = true
        let mode = viewMode
        let indent = indent

        job = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled else { return }

            let analysis = await Task.detached(priority: .userInitiated) {
                JSONToolEngine.analyze(text: text, mode: mode, indent: indent)
            }.value

            guard !Task.isCancelled, let self else { return }
            self.apply(analysis)
        }
    }

    private func apply(_ analysis: JSONAnalysis) {
        output = analysis.output
        highlighted = analysis.highlighted
        tree = analysis.tree
        table = analysis.table
        types = analysis.types
        error = analysis.error
        metrics = analysis.metrics
        isWorking = false
    }

    private func clearResult() {
        output = ""
        actionOutput = nil
        actionLabel = nil
        highlighted = nil
        tree = nil
        table = nil
        types = ""
        error = nil
        metrics = nil
        isWorking = false
    }

    // MARK: 一次性处理动作

    func perform(_ action: JSONAction) {
        guard hasInput else { return }
        guard input.utf8.count <= Self.maxBytes else { return }

        let source = action == .escape ? displayedOutput : input
        let unit = indent
        isWorking = true

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                JSONToolEngine.transform(source, action: action, indent: unit)
            }.value

            guard let self else { return }
            self.isWorking = false
            if let result {
                self.actionOutput = result
                self.actionLabel = action.rawValue
            } else {
                self.error = JSONErrorInfo(
                    message: "\(action.rawValue)失败，请检查输入内容",
                    line: nil, column: nil, fatal: false
                )
            }
        }
    }

    func resetAction() {
        actionOutput = nil
        actionLabel = nil
    }

    func paste(_ string: String) {
        input = string
    }

    func clear() {
        job?.cancel()
        input = ""
        clearResult()
    }

    // MARK: 复制

    func copyCurrent() {
        let text: String
        switch viewMode {
        case .type: text = types
        case .table: text = table?.tsv ?? ""
        case .tree, .edit: text = displayedOutput
        }
        guard !text.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        copyResetJob?.cancel()
        copyResetJob = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            self?.copied = false
        }
    }

    // MARK: 文件

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            input = text
        } catch {
            self.error = JSONErrorInfo(
                message: "无法读取文件：\(error.localizedDescription)",
                line: nil, column: nil, fatal: true
            )
        }
    }

    func saveFile() {
        let content = displayedOutput.isEmpty ? input : displayedOutput
        guard !content.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "formatted.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            self.error = JSONErrorInfo(
                message: "保存失败：\(error.localizedDescription)",
                line: nil, column: nil, fatal: true
            )
        }
    }

    func loadSample() {
        input = """
        {
          "name": "LENSO",
          "version": "1.0.0",
          "features": ["截图", "搜索", "JSON 工作台"],
          "author": { "name": "lenso", "email": "hi@lenso.app" },
          "stars": 1280,
          "active": true,
          "meta": null
        }
        """
    }
}

// MARK: - JSON 值

indirect enum JSONValue: Sendable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var typeName: String {
        switch self {
        case .object: "Object"
        case .array: "Array"
        case .string: "String"
        case .number: "Number"
        case .bool: "Boolean"
        case .null: "Null"
        }
    }

    var preview: String {
        switch self {
        case .object(let pairs): "{ \(pairs.count) 个字段 }"
        case .array(let items): "[ \(items.count) 项 ]"
        case .string(let value):
            value.count > 90 ? "\"\(value.prefix(90))…\"" : "\"\(value)\""
        case .number(let value): value
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        }
    }
}

// MARK: - 引擎

enum JSONToolEngine {
    private static let highlightLimit = 300 * 1024

    // MARK: 分析

    static func analyze(text: String, mode: JSONViewMode, indent: JSONIndent) -> JSONAnalysis {
        let clock = ContinuousClock()
        let start = clock.now
        let data = Data(text.utf8)

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let formatted = pretty(text, unit: indent.unit)
            let nodes = countNodes(object)
            let highlighted = (mode == .edit && formatted.utf8.count <= highlightLimit)
                ? JSONSyntaxHighlighter.highlight(formatted)
                : nil

            var tree: JSONTreeNode?
            var table: JSONTable?
            var types = ""

            switch mode {
            case .edit:
                break
            case .tree:
                tree = JSONTreeBuilder.build(object)
            case .table:
                table = JSONTableBuilder.build(object)
            case .type:
                types = JSONTypeBuilder.build(object)
            }

            let elapsed = clock.now - start
            let duration = Int(elapsed.components.seconds) * 1000
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            let metrics = JSONMetrics(
                nodes: nodes,
                inputBytes: data.count,
                outputBytes: formatted.utf8.count,
                lines: formatted.reduce(into: 1) { partial, char in if char == "\n" { partial += 1 } },
                durationMS: max(duration, 1)
            )

            return JSONAnalysis(
                output: formatted,
                highlighted: highlighted,
                error: nil,
                metrics: metrics,
                tree: tree,
                table: table,
                types: types
            )
        } catch {
            return .failure(parseError(error, text: text))
        }
    }

    private static func parseError(_ error: Error, text: String) -> JSONErrorInfo {
        let nsError = error as NSError
        let detail = (nsError.userInfo[NSDebugDescriptionErrorKey] as? String)
            ?? nsError.localizedDescription
        let (line, column) = extractPosition(from: detail)
        return JSONErrorInfo(message: detail, line: line, column: column, fatal: false)
    }

    private static func extractPosition(from message: String) -> (Int?, Int?) {
        let pattern = #"line (\d+), column (\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              match.numberOfRanges == 3,
              let lineRange = Range(match.range(at: 1), in: message),
              let columnRange = Range(match.range(at: 2), in: message)
        else { return (nil, nil) }
        return (Int(message[lineRange]), Int(message[columnRange]))
    }

    // MARK: 一次性动作

    static func transform(_ text: String, action: JSONAction, indent: JSONIndent) -> String? {
        let data = Data(text.utf8)

        switch action {
        case .escape:
            return escapeStringLiteral(text)

        case .unescape:
            return unescapeStringLiteral(text)

        case .compress:
            guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                return nil
            }
            return minify(text)

        case .sort:
            guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            return serializeSorted(object, unit: indent.unit)
        }
    }

    // MARK: 漂亮排版

    static func pretty(_ text: String, unit: String) -> String {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 3)
        let indentBytes = Array(unit.utf8)

        var depth = 0
        var inString = false
        var escaped = false
        var i = 0

        func newline(_ depth: Int) {
            out.append(0x0A)
            for _ in 0..<depth { out.append(contentsOf: indentBytes) }
        }

        while i < bytes.count {
            let b = bytes[i]

            if inString {
                out.append(b)
                if escaped { escaped = false }
                else if b == 0x5C { escaped = true }
                else if b == 0x22 { inString = false }
                i += 1
                continue
            }

            switch b {
            case 0x22:
                inString = true
                out.append(b)

            case 0x7B, 0x5B:
                var j = i + 1
                while j < bytes.count, isWhitespace(bytes[j]) { j += 1 }
                let isObject = b == 0x7B
                if j < bytes.count,
                   (isObject && bytes[j] == 0x7D) || (!isObject && bytes[j] == 0x5D) {
                    out.append(b)
                    out.append(bytes[j])
                    i = j
                } else {
                    depth += 1
                    out.append(b)
                    newline(depth)
                }

            case 0x7D, 0x5D:
                depth = max(depth - 1, 0)
                newline(depth)
                out.append(b)

            case 0x2C:
                out.append(b)
                newline(depth)

            case 0x3A:
                out.append(0x3A)
                out.append(0x20)

            case 0x20, 0x0A, 0x0D, 0x09:
                break

            default:
                out.append(b)
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func minify(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var inString = false
        var escaped = false

        for b in bytes {
            if inString {
                out.append(b)
                if escaped { escaped = false }
                else if b == 0x5C { escaped = true }
                else if b == 0x22 { inString = false }
                continue
            }
            switch b {
            case 0x22:
                inString = true
                out.append(b)
            case 0x20, 0x0A, 0x0D, 0x09:
                break
            default:
                out.append(b)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09
    }

    // MARK: 排序后序列化

    private static func serializeSorted(_ value: Any, unit: String) -> String {
        var out = ""
        write(value, level: 0, unit: unit, into: &out)
        return out
    }

    private static func write(_ value: Any, level: Int, unit: String, into out: inout String) {
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty {
                out += "{}"
                return
            }
            out += "{\n"
            let keys = dictionary.keys.sorted()
            for (index, key) in keys.enumerated() {
                out += String(repeating: unit, count: level + 1)
                out += escapeStringLiteral(key)
                out += ": "
                write(dictionary[key] as Any, level: level + 1, unit: unit, into: &out)
                if index != keys.count - 1 { out += "," }
                out += "\n"
            }
            out += String(repeating: unit, count: level) + "}"
            return
        }

        if let array = value as? [Any] {
            if array.isEmpty {
                out += "[]"
                return
            }
            out += "[\n"
            for (index, item) in array.enumerated() {
                out += String(repeating: unit, count: level + 1)
                write(item, level: level + 1, unit: unit, into: &out)
                if index != array.count - 1 { out += "," }
                out += "\n"
            }
            out += String(repeating: unit, count: level) + "]"
            return
        }

        if value is NSNull {
            out += "null"
            return
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                out += number.boolValue ? "true" : "false"
            } else {
                out += numberText(number)
            }
            return
        }

        if let string = value as? String {
            out += escapeStringLiteral(string)
            return
        }

        out += "null"
    }

    private static func numberText(_ number: NSNumber) -> String {
        let double = number.doubleValue
        if double.isFinite,
           double == double.rounded(),
           abs(double) < 9_007_199_254_740_992 {
            return String(Int64(double))
        }
        return number.stringValue
    }

    static func escapeStringLiteral(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    static func unescapeStringLiteral(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        }

        var out = ""
        var iterator = trimmed.makeIterator()
        while let char = iterator.next() {
            guard char == "\\" else {
                out.append(char)
                continue
            }
            guard let next = iterator.next() else { return nil }
            switch next {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "/": out.append("/")
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    guard let digit = iterator.next() else { return nil }
                    hex.append(digit)
                }
                guard let value = UInt32(hex, radix: 16),
                      let scalar = UnicodeScalar(value) else { return nil }
                out.unicodeScalars.append(scalar)
            default:
                out.append(next)
            }
        }
        return out
    }

    // MARK: 统计

    private static func countNodes(_ value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            return dictionary.count + dictionary.values.reduce(0) { $0 + countNodes($1) }
        }
        if let array = value as? [Any] {
            return array.count + array.reduce(0) { $0 + countNodes($1) }
        }
        return 1
    }
}

// MARK: - 树构建

enum JSONTreeBuilder {
    private static let nodeLimit = 20_000

    static func build(_ value: Any) -> JSONTreeNode? {
        var remaining = nodeLimit
        return node(value, key: nil, remaining: &remaining)
    }

    private static func node(_ value: Any, key: String?, remaining: inout Int) -> JSONTreeNode? {
        guard remaining > 0 else { return nil }
        remaining -= 1

        if let dictionary = value as? [String: Any] {
            if remaining <= 0 {
                return JSONTreeNode(key: key, value: .object([]), children: [], truncated: true)
            }
            let children = dictionary.keys.sorted().compactMap { childKey in
                node(dictionary[childKey] as Any, key: childKey, remaining: &remaining)
            }
            return JSONTreeNode(
                key: key,
                value: .object(children.map { ($0.key ?? "", $0.value) }),
                children: children.isEmpty ? nil : children,
                truncated: remaining <= 0
            )
        }

        if let array = value as? [Any] {
            if remaining <= 0 {
                return JSONTreeNode(key: key, value: .array([]), children: [], truncated: true)
            }
            let children = array.enumerated().compactMap { index, item in
                node(item, key: "[\(index)]", remaining: &remaining)
            }
            return JSONTreeNode(
                key: key,
                value: .array(children.map(\.value)),
                children: children.isEmpty ? nil : children,
                truncated: remaining <= 0
            )
        }

        return JSONTreeNode(key: key, value: leaf(value), children: nil, truncated: false)
    }

    private static func leaf(_ value: Any) -> JSONValue {
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            if double.isFinite, double == double.rounded(), abs(double) < 9_007_199_254_740_992 {
                return .number(String(Int64(double)))
            }
            return .number(number.stringValue)
        }
        if let string = value as? String { return .string(string) }
        return .null
    }
}

// MARK: - 表格构建

enum JSONTableBuilder {
    private static let rowLimit = 300

    static func build(_ value: Any) -> JSONTable? {
        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            if !array.isEmpty, dictionaries.count == array.count {
                var columns: [String] = []
                for dictionary in dictionaries.prefix(100) {
                    for key in dictionary.keys.sorted() where !columns.contains(key) {
                        columns.append(key)
                    }
                }
                let rows = dictionaries.prefix(rowLimit).map { dictionary in
                    columns.map { display(dictionary[$0]) }
                }
                return JSONTable(
                    columns: columns,
                    rows: rows,
                    totalRows: array.count,
                    truncated: array.count > rowLimit
                )
            }

            let rows = array.prefix(rowLimit).map { [display($0)] }
            return JSONTable(
                columns: ["值"],
                rows: rows,
                totalRows: array.count,
                truncated: array.count > rowLimit
            )
        }

        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.sorted()
            return JSONTable(
                columns: ["字段", "值"],
                rows: keys.map { [$0, display(dictionary[$0])] },
                totalRows: keys.count,
                truncated: false
            )
        }

        return JSONTable(columns: ["值"], rows: [[display(value)]], totalRows: 1, truncated: false)
    }

    private static func display(_ value: Any?) -> String {
        guard let value else { return "null" }
        if value is NSNull { return "null" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            if double.isFinite, double == double.rounded(), abs(double) < 9_007_199_254_740_992 {
                return String(Int64(double))
            }
            return number.stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}

// MARK: - TypeScript 类型生成

enum JSONTypeBuilder {
    static func build(_ value: Any) -> String {
        var generator = Generator()
        let rootType = generator.type(of: value, nameHint: "Root")
        var parts = generator.interfaces
        // 根接口排在最前，嵌套接口跟随其后
        if let rootIndex = parts.firstIndex(where: { $0.hasPrefix("interface Root ") }) {
            let root = parts.remove(at: rootIndex)
            parts.insert(root, at: 0)
        }
        if rootType != "Root" || !generator.didEmitRootInterface {
            parts.append("type Root = \(rootType);")
        }
        return parts.joined(separator: "\n\n")
    }

    private struct Generator {
        var interfaces: [String] = []
        var emitted: Set<String> = []
        var didEmitRootInterface = false

        mutating func type(of value: Any, nameHint: String) -> String {
            if value is NSNull { return "null" }

            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return "boolean" }
                return "number"
            }
            if value is String { return "string" }

            if let array = value as? [Any] {
                if array.isEmpty { return "any[]" }
                var seen: [String] = []
                for item in array {
                    let itemType = type(of: item, nameHint: nameHint + "Item")
                    if !seen.contains(itemType) { seen.append(itemType) }
                }
                if seen.count == 1 { return "\(seen[0])[]" }
                return "(\(seen.joined(separator: " | ")))[]"
            }

            if let dictionary = value as? [String: Any] {
                let name = sanitize(nameHint)
                if emitted.contains(name) { return name }

                emitted.insert(name)
                if name == "Root" { didEmitRootInterface = true }

                var lines: [String] = []
                for key in dictionary.keys.sorted() {
                    let childName = name + sanitize(key, firstUpper: true)
                    let childType = type(of: dictionary[key] as Any, nameHint: childName)
                    let safeKey = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
                        ? key
                        : "\"\(key)\""
                    lines.append("  \(safeKey): \(childType);")
                }

                let body = lines.isEmpty ? "{}" : "{\n\(lines.joined(separator: "\n"))\n}"
                interfaces.append("interface \(name) \(body)")
                return name
            }

            return "any"
        }

        private func sanitize(_ raw: String, firstUpper: Bool = false) -> String {
            var result = ""
            var upperNext = firstUpper
            for char in raw {
                if char.isLetter || char.isNumber {
                    if result.isEmpty, char.isNumber { result.append("_") }
                    if upperNext {
                        result += String(char).uppercased()
                    } else {
                        result.append(char)
                    }
                    upperNext = false
                } else {
                    upperNext = true
                }
            }
            if result.isEmpty { result = "Type" }
            return result
        }
    }
}
