import SwiftUI
import AppKit

/// 把宿主窗口变成透明浮窗（圆角内容浮在桌面上，带系统阴影）
struct WindowConfigurator: NSViewRepresentable {
    var movableByBackground = true

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = movableByBackground
            window.titlebarAppearsTransparent = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
