import SwiftUI

/// 编辑文字片段
struct NoteEditorSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("编辑文字").font(.system(size: 15, weight: .semibold))
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minWidth: 420, minHeight: 220)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.08)))
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .environment(\.colorScheme, .light)
    }
}
