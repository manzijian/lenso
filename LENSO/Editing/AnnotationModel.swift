import SwiftUI
import CoreGraphics

/// 标注类型
enum AnnotationKind: CaseIterable {
    case rect, ellipse, arrow, brush, text, mosaic, highlight

    var icon: String {
        switch self {
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .brush: "pencil.tip"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.square"
        case .highlight: "drop"
        }
    }

    var label: String {
        switch self {
        case .rect: "矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .brush: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        case .highlight: "高亮"
        }
    }
}

/// 单个标注：基于归一化坐标（0-1，相对选区）
struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    var start: CGPoint   // 归一化
    var end: CGPoint     // 归一化
    var colorIndex: Int
    var strokeWidth: CGFloat
    var text: String = ""
}

/// 标注颜色盘（参考图 7 色）
let AnnotationPalette: [Color] = [
    .red, .orange, .yellow, .blue, .purple, .black, .white
]

let AnnotationPaletteNS: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemBlue, .systemPurple, .black, .white
]

/// 编辑器状态
@Observable
@MainActor
final class AnnotationState {
    var annotations: [Annotation] = []
    var undoStack: [[Annotation]] = []
    var redoStack: [[Annotation]] = []
    var activeKind: AnnotationKind? = nil
    var colorIndex = 3 // 默认蓝
    var strokeWidth: CGFloat = 2
    var mosaicEnabled = false
    var highlightEnabled = false
    var draft: Annotation? = nil   // 正在绘制的
    /// 正在输入文字的标注落点（归一化坐标）；非 nil 时编辑器显示输入框
    var textEditingPoint: CGPoint? = nil

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func push(_ annotation: Annotation) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.append(annotation)
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = last
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = last
    }

    func reset() {
        annotations = []
        undoStack = []
        redoStack = []
        draft = nil
        textEditingPoint = nil
    }
}
