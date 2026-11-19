import Foundation
import SwiftUI

/// 轻量 JSON 语法着色：单次字节扫描，无正则、无对象图。
/// 仅在格式化结果不超过 300 KB 时启用，超大文本退回纯文本显示。
enum JSONSyntaxHighlighter {
    private static let keyColor = Color(red: 0.02, green: 0.22, blue: 0.88)
    private static let stringColor = Color(red: 0.10, green: 0.48, blue: 0.30)
    private static let numberColor = Color(red: 0.69, green: 0.30, blue: 0.10)
    private static let keywordColor = Color(red: 0.47, green: 0.22, blue: 0.72)
    private static let punctuationColor = Color.secondary.opacity(0.72)

    static func highlight(_ text: String) -> AttributedString {
        let bytes = Array(text.utf8)
        var result = AttributedString()
        var index = 0

        func append(_ range: Range<Int>, _ color: Color) {
            guard range.lowerBound < range.upperBound else { return }
            var piece = AttributedString(String(decoding: bytes[range], as: UTF8.self))
            piece.foregroundColor = color
            result += piece
        }

        while index < bytes.count {
            let byte = bytes[index]

            // 空白原样输出
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                let start = index
                while index < bytes.count,
                      bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 {
                    index += 1
                }
                append(start..<index, .primary)
                continue
            }

            // 字符串 / 键
            if byte == 0x22 {
                let start = index
                index += 1
                var escaped = false
                while index < bytes.count {
                    let current = bytes[index]
                    if escaped {
                        escaped = false
                    } else if current == 0x5C {
                        escaped = true
                    } else if current == 0x22 {
                        index += 1
                        break
                    }
                    index += 1
                }

                var lookahead = index
                while lookahead < bytes.count,
                      bytes[lookahead] == 0x20 || bytes[lookahead] == 0x0A || bytes[lookahead] == 0x0D || bytes[lookahead] == 0x09 {
                    lookahead += 1
                }
                let isKey = lookahead < bytes.count && bytes[lookahead] == 0x3A
                append(start..<index, isKey ? keyColor : stringColor)
                continue
            }

            // 数字
            if (byte >= 0x30 && byte <= 0x39) || byte == 0x2D {
                let start = index
                index += 1
                while index < bytes.count {
                    let current = bytes[index]
                    let isNumberByte = (current >= 0x30 && current <= 0x39)
                        || current == 0x2E || current == 0x2D
                        || current == 0x2B || current == 0x65 || current == 0x45
                    if isNumberByte {
                        index += 1
                    } else {
                        break
                    }
                }
                append(start..<index, numberColor)
                continue
            }

            // true / false / null
            if byte == 0x74 || byte == 0x66 || byte == 0x6E {
                let start = index
                while index < bytes.count {
                    let current = bytes[index]
                    if (current >= 0x61 && current <= 0x7A) {
                        index += 1
                    } else {
                        break
                    }
                }
                append(start..<index, keywordColor)
                continue
            }

            // 标点
            let start = index
            index += 1
            append(start..<index, punctuationColor)
        }

        return result
    }
}
