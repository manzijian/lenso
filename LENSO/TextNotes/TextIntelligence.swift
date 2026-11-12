import Foundation
import SwiftUI
import AppKit

/// 网页元数据异步抓取与缓存单例
@MainActor
final class WebMetadataStore: ObservableObject {
    static let shared = WebMetadataStore()

    @Published var titles: [String: String] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    func title(for urlString: String) -> String? {
        titles[urlString]
    }

    func fetchTitleIfNeeded(for urlString: String) {
        guard !urlString.isEmpty else { return }
        guard titles[urlString] == nil else { return }
        guard !inFlight.contains(urlString) else { return }

        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        inFlight.insert(urlString)

        Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                    inFlight.remove(urlString)
                    return
                }

                // 取前 32KB 足够解析 <title> 标签
                let prefixData = data.prefix(32768)
                if let html = String(data: prefixData, encoding: .utf8) ?? String(data: prefixData, encoding: .ascii) {
                    if let title = extractTitle(from: html) {
                        self.titles[urlString] = title
                        NotificationCenter.default.post(name: .webTitleUpdated, object: urlString)
                    }
                }
            } catch {
                // 忽略超时或网络失败，保持域名兜底
            }
            inFlight.remove(urlString)
        }
    }

    private func extractTitle(from html: String) -> String? {
        let pattern = "(?i)<title[^>]*>(.*?)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsString = html as NSString
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: min(html.utf16.count, 32768))) else {
            return nil
        }
        let rawTitle = nsString.substring(with: match.range(at: 1))
        let cleaned = rawTitle
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }
}

extension Notification.Name {
    static let webTitleUpdated = Notification.Name("lenso.webTitleUpdated")
}

/// 智能文本内容识别与格式化引擎
enum TextIntelligence {

    enum ContentType: Equatable {
        case url(url: URL, originalString: String)
        case json(pretty: String, minified: String)
        case code(language: String, formatted: String)
        case plainText
    }

    // MARK: - 智能识别

    static func detect(_ raw: String) -> ContentType {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .plainText }

        // 1. 网址识别 (http/https 或纯正网站域名)
        if isLikelyURL(text) {
            let candidate = text.hasPrefix("http://") || text.hasPrefix("https://") ? text : "https://" + text
            if let url = URL(string: candidate), let host = url.host, host.contains(".") {
                return .url(url: url, originalString: text)
            }
        }

        // 2. JSON 识别与格式化
        if let jsonKind = detectAndFormatJSON(text) {
            return jsonKind
        }

        // 3. 代码语言识别与美化格式化 (C / C++ / Swift / Python / SQL 等)
        if let codeKind = detectAndFormatCode(text) {
            return codeKind
        }

        return .plainText
    }

    private static func isLikelyURL(_ text: String) -> Bool {
        // 单行无换行
        if text.contains("\n") || text.contains(" ") { return false }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return true }
        if text.hasPrefix("www.") && text.count > 6 { return true }
        return false
    }

    // MARK: - JSON 智能处理

    private static func detectAndFormatJSON(_ text: String) -> ContentType? {
        guard (text.hasPrefix("{") && text.hasSuffix("}")) ||
              (text.hasPrefix("[") && text.hasSuffix("]")) else {
            return nil
        }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }

        // 格式化美化版本 (2 空格缩进)
        let prettyData = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? data
        let prettyStr = String(data: prettyData, encoding: .utf8) ?? text

        // 紧凑单行版本
        let miniData = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? data
        let miniStr = String(data: miniData, encoding: .utf8) ?? text

        return .json(pretty: prettyStr, minified: miniStr)
    }

    // MARK: - 代码识别与格式化

    private static func detectAndFormatCode(_ text: String) -> ContentType? {
        // C / C++ 特征
        let cKeywords = ["#include", "int main", "printf(", "void ", "char* ", "typedef struct", "malloc(", "NULL", "std::cout", "int ", "return 0;"]
        var cMatchCount = 0
        for kw in cKeywords {
            if text.contains(kw) { cMatchCount += 1 }
        }
        if cMatchCount >= 2 || text.contains("#include <") {
            let formatted = formatCCode(text)
            return .code(language: "C/C++", formatted: formatted)
        }

        // Swift 特征
        let swiftKeywords = ["import SwiftUI", "import Foundation", "var body: some View", "@State", "@Binding", "guard let ", "func ", "extension "]
        var swiftCount = 0
        for kw in swiftKeywords {
            if text.contains(kw) { swiftCount += 1 }
        }
        if swiftCount >= 2 {
            return .code(language: "Swift", formatted: text)
        }

        // Python 特征
        let pyKeywords = ["def ", "class ", "import ", "from ", "if __name__ == '__main__':", "elif ", "print("]
        var pyCount = 0
        for kw in pyKeywords {
            if text.contains(kw) { pyCount += 1 }
        }
        if pyCount >= 2 && (text.contains(":\n") || text.contains(": ")) {
            return .code(language: "Python", formatted: text)
        }

        // SQL 特征
        let sqlKeywords = ["SELECT ", "FROM ", "WHERE ", "INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE TABLE"]
        var sqlCount = 0
        for kw in sqlKeywords {
            if text.localizedCaseInsensitiveContains(kw) { sqlCount += 1 }
        }
        if sqlCount >= 2 {
            return .code(language: "SQL", formatted: text)
        }

        // 通用多行代码判断 (含有花括号与分号排布)
        let openBraces = text.filter { $0 == "{" }.count
        let semicolons = text.filter { $0 == ";" }.count
        if openBraces >= 2 && semicolons >= 3 {
            let formatted = formatCCode(text)
            return .code(language: "代码", formatted: formatted)
        }

        return nil
    }

    // MARK: - C 语言与花括号代码格式化对齐

    static func formatCCode(_ code: String) -> String {
        let lines = code.components(separatedBy: .newlines)
        var result: [String] = []
        var indentLevel = 0
        let indentStr = "    " // 4 空格缩进

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                result.append("")
                continue
            }

            // 若本行以闭合括号开头，先减少自身缩进
            if line.hasPrefix("}") || line.hasPrefix("};") || line.hasPrefix("})") {
                indentLevel = max(0, indentLevel - 1)
            }

            let currentIndent = String(repeating: indentStr, count: indentLevel)
            result.append(currentIndent + line)

            // 统计该行花括号增减（简易解析）
            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            if !line.hasPrefix("}") {
                indentLevel = max(0, indentLevel + (opens - closes))
            } else {
                indentLevel = max(0, indentLevel + (opens - (closes - 1)))
            }
        }

        return result.joined(separator: "\n")
    }

    // MARK: - 语法高亮 AttributedString 生成

    static func highlight(code: String, language: String) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        attributed.foregroundColor = Color(red: 0.15, green: 0.15, blue: 0.2)

        // 简易关键字着色
        let keywords: [String]
        switch language.lowercased() {
        case "c/c++":
            keywords = ["#include", "int", "void", "char", "float", "double", "struct", "typedef", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "default", "const", "static", "unsigned", "sizeof", "NULL", "true", "false"]
        case "swift":
            keywords = ["import", "func", "var", "let", "struct", "class", "enum", "protocol", "extension", "guard", "if", "else", "return", "some", "private", "public", "static", "init", "self", "Self", "true", "false", "nil"]
        case "python":
            keywords = ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "as", "try", "except", "with", "None", "True", "False"]
        case "sql":
            keywords = ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "JOIN", "LEFT", "RIGHT", "GROUP", "BY", "ORDER", "AND", "OR", "LIMIT", "CREATE", "TABLE"]
        default:
            keywords = ["func", "var", "let", "return", "if", "else", "for", "while", "class", "struct"]
        }

        let nsString = code as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // 1. 高亮关键字 (克莱因蓝/紫罗兰)
        for kw in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: code, options: [], range: fullRange)
                for m in matches {
                    if let range = Range(m.range, in: code),
                       let attrRange = Range(range, in: attributed) {
                        attributed[attrRange].foregroundColor = LensoColors.kleinBlueBright
                        attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
                    }
                }
            }
        }

        // 2. 高亮字符串 ("..." 或 '...') (翠绿/橙色)
        if let stringRegex = try? NSRegularExpression(pattern: "\"[^\"]*\"|'[^']*'") {
            let matches = stringRegex.matches(in: code, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range, in: code),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = Color(red: 0.15, green: 0.58, blue: 0.35)
                }
            }
        }

        // 3. 高亮数字 (蓝色)
        if let numRegex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b") {
            let matches = numRegex.matches(in: code, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range, in: code),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = Color(red: 0.1, green: 0.45, blue: 0.8)
                }
            }
        }

        // 4. 高亮注释 (// ... 或 /* ... */) (灰度)
        if let commentRegex = try? NSRegularExpression(pattern: "//.*|/\\*[\\s\\S]*?\\*/") {
            let matches = commentRegex.matches(in: code, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range, in: code),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = Color.secondary.opacity(0.7)
                }
            }
        }

        return attributed
    }

    static func highlightJSON(_ json: String) -> AttributedString {
        var attributed = AttributedString(json)
        attributed.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        attributed.foregroundColor = Color(red: 0.18, green: 0.18, blue: 0.22)

        let nsString = json as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // 高亮 JSON Key: "key":
        if let keyRegex = try? NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:") {
            let matches = keyRegex.matches(in: json, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range(at: 1), in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = LensoColors.kleinBlueBright
                    attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
                }
            }
        }

        // 高亮 JSON 字符串值: : "value"
        if let valRegex = try? NSRegularExpression(pattern: ":\\s*\"([^\"]*)\"") {
            let matches = valRegex.matches(in: json, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range(at: 1), in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = Color(red: 0.15, green: 0.58, blue: 0.35)
                }
            }
        }

        // 高亮数字/布尔值
        if let literalRegex = try? NSRegularExpression(pattern: "\\b(true|false|null|-?\\d+(\\.\\d+)?)\\b") {
            let matches = literalRegex.matches(in: json, options: [], range: fullRange)
            for m in matches {
                if let range = Range(m.range, in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = Color(red: 0.85, green: 0.45, blue: 0.1)
                }
            }
        }

        return attributed
    }
}
