import SwiftUI
import AppKit

/// 支持拖拽移动整个窗口的 NSView 代理层
struct WindowDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragHandleNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragHandleNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

extension DateFormatter {
    /// 卡片上的紧凑时间：月日 + 时分，避免年月日时分秒把卡片撑乱
    static let lensoCardTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM月dd日 HH:mm"
        df.locale = Locale(identifier: "zh_CN")
        return df
    }()
}

/// 统一卡片样式：统一圆角，高度由双指缩放的档位传入
private enum CardStyle {
    static let radius: CGFloat = 13
}

// MARK: - 来源应用图标

/// 按应用名解析图标：优先运行中的 App，其次常见应用目录，结果缓存
@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let cached = cache[name] { return cached }

        var result: NSImage?
        if name == "截图" {
            result = NSApp.applicationIconImage
        } else if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
            result = running.icon
        } else if let url = applicationURL(named: name) {
            result = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache[name] = result
        return result
    }

    private static func applicationURL(named name: String) -> URL? {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            if let hit = entries.first(where: {
                $0.lowercased() == "\(name.lowercased()).app"
            }) {
                return URL(fileURLWithPath: root).appendingPathComponent(hit)
            }
        }
        return nil
    }
}

/// 来源应用图标：解析不到时退化为类型图标
struct SourceAppIcon: View {
    let name: String?
    var size: CGFloat = 16

    private var fallbackSymbol: String {
        switch name {
        case "截图": return "camera.viewfinder"
        case "收纳": return "tray.full"
        default: return "doc.on.clipboard"
        }
    }

    var body: some View {
        Group {
            if let icon = AppIconProvider.icon(for: name) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: size, height: size)
                    .background(Color.black.opacity(0.05))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

// MARK: - 截图卡片

struct SearchPanelScreenshotTile: View {
    let item: SearchPanelView.FeedItem
    let cgImage: CGImage?
    let height: CGFloat
    let isCopied: Bool
    let onCopy: () -> Void
    let onInspect: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(red: 0.94, green: 0.95, blue: 0.965)

                if let cgImage {
                    Image(decorative: cgImage, scale: 2)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("截图")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if isCopied {
                    copiedOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // 信息行放在图片下方，不遮挡画面
            HStack(spacing: 5) {
                SourceAppIcon(name: item.sourceApp, size: 12)
                Text(item.sourceApp?.isEmpty == false ? item.sourceApp! : "剪贴板")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hovering {
                    HStack(spacing: 0) {
                        footerButton("doc.on.doc", help: "复制", action: onCopy)
                        footerButton("eye", help: "查看", action: onInspect)
                    }
                } else {
                    Text(DateFormatter.lensoCardTime.string(from: item.createdAt))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.white)
        }
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous)
                .strokeBorder(Color.black.opacity(hovering ? 0.16 : 0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.05), radius: hovering ? 10 : 4, y: hovering ? 4 : 2)
        .onHover { hovering = $0 }
        .onTapGesture { onInspect() }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.68))
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .help(help)
    }

    private var copiedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous)
                .fill(Color.black.opacity(0.42))
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("已复制")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.82)))
        }
        .transition(.opacity)
    }
}

// MARK: - 文字 / 代码 / 链接卡片

struct SearchPanelTextTile: View {
    let item: SearchPanelView.FeedItem
    let content: String
    let height: CGFloat
    let isCopied: Bool
    let onCopy: () -> Void
    let onInspect: () -> Void
    @ObservedObject var webStore: WebMetadataStore

    @State private var hovering = false

    /// 卡片被双指缩小后自动减少正文行数，避免内容溢出
    private var textLineLimit: Int { height < 160 ? 3 : 4 }
    private var titleLineLimit: Int { height < 160 ? 1 : 2 }

    var body: some View {
        let smartType = TextIntelligence.detect(content)

        VStack(alignment: .leading, spacing: 0) {
            header(for: smartType)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            body(for: smartType)
                .padding(.horizontal, 12)
                .padding(.top, 7)

            Spacer(minLength: 4)

            Rectangle()
                .fill(Color.black.opacity(0.055))
                .frame(height: 1)

            HStack(spacing: 6) {
                Text(DateFormatter.lensoCardTime.string(from: item.createdAt))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(content.count) 字")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous)
                .fill(Color.white)
        )
        .contentShape(RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverActionButtons(onCopy: onCopy, onInspect: onInspect)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous)
                .strokeBorder(hovering ? LensoColors.kleinBlueBright.opacity(0.22) : Color.black.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { onInspect() }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .overlay {
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: CardStyle.radius, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text("已复制")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: 顶部：类型 + 来源 + 操作

    private func header(for smartType: TextIntelligence.ContentType) -> some View {
        let badge: (label: String, symbol: String) = {
            switch smartType {
            case .url: return ("网址", "globe")
            case .json: return ("JSON", "curlybraces")
            case .code(let lang, _): return (lang, "chevron.left.forwardslash.chevron.right")
            case .plainText: return ("文字", "text.quote")
            }
        }()

        return HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: badge.symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(badge.label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(LensoColors.kleinBlueBright)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(LensoColors.kleinBlueSoft))

            if let app = item.sourceApp, !app.isEmpty {
                HStack(spacing: 4) {
                    SourceAppIcon(name: app, size: 13)
                    Text(app)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .frame(height: 22)
    }

    // MARK: 正文

    @ViewBuilder
    private func body(for smartType: TextIntelligence.ContentType) -> some View {
        switch smartType {
        case .url(let url, let original):
            let title = webStore.title(for: original) ?? url.host ?? original
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .lineLimit(titleLineLimit)
                Text(url.host ?? original)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 3) {
                        Text("打开网页")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(LensoColors.kleinBlueBright))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onAppear { webStore.fetchTitleIfNeeded(for: original) }

        case .json(let pretty, _):
            Text(pretty)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(red: 0.16, green: 0.2, blue: 0.3))
                .lineSpacing(2)
                .lineLimit(textLineLimit)
                .frame(maxWidth: .infinity, alignment: .topLeading)

        case .code(_, let formatted):
            Text(formatted)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(red: 0.16, green: 0.2, blue: 0.3))
                .lineSpacing(2)
                .lineLimit(textLineLimit)
                .frame(maxWidth: .infinity, alignment: .topLeading)

        case .plainText:
            Text(content)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.84))
                .lineSpacing(2.5)
                .lineLimit(textLineLimit)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - 悬停操作按钮（白底实心小胶囊，保证在任何画面上都看得清）

private struct HoverActionButtons: View {
    let onCopy: () -> Void
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 1) {
            HoverIconButton(symbol: "doc.on.doc", help: "复制", action: onCopy)
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1, height: 14)
            HoverIconButton(symbol: "eye", help: "查看", action: onInspect)
        }
        .padding(3)
        .background(
            Capsule().fill(Color.white)
        )
        .overlay(
            Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

private struct HoverIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hovering ? LensoColors.kleinBlueBright : Color.black.opacity(0.72))
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(hovering ? LensoColors.kleinBlueSoft : Color.clear)
            )
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture { action() }
            .help(help)
    }
}
