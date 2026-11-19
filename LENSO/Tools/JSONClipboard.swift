import Foundation

/// 剪贴板 JSON 识别。
/// 保守判断：只认以 `{` / `[` 开头、且能被 JSONSerialization 解析的文本，
/// 避免把普通数字、纯字符串也当成 JSON。
enum JSONClipboard {
    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        // 超大文本不做即时校验，交给 JSON 工作台按自己的阈值处理
        guard trimmed.utf8.count <= 2_000_000 else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}
