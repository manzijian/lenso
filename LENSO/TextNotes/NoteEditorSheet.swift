import SwiftUI

/// 编辑文字片段
struct NoteEditorSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var originalText: String = ""
    @State private var showDiscardConfirm = false

    private var isDirty: Bool {
        text != originalText
    }

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
                Text("⌘↵ 保存")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: requestCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onSave)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(isDirty)
        .onAppear {
            originalText = text
        }
        .alert("放弃未保存的更改？", isPresented: $showDiscardConfirm) {
            Button("放弃更改", role: .destructive, action: onCancel)
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("当前内容已修改，放弃后将无法恢复。")
        }
        .lensoColorScheme()
    }

    private func requestCancel() {
        if isDirty {
            showDiscardConfirm = true
        } else {
            onCancel()
        }
    }
}
