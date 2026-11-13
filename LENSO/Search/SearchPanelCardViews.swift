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

/// 截图方块卡片（类似相册照片，满铺 + 年月日时分秒）
struct SearchPanelScreenshotTile: View {
    let item: SearchPanelView.FeedItem
    let cgImage: CGImage?
    let isCopied: Bool
    let onCopy: () -> Void
    let onInspect: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景与图片主体
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.94, blue: 0.96))

                if let cgImage {
                    Image(decorative: cgImage, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 185)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("图片记录")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 185)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 顶部浮动栏：来源应用胶囊 + 快速动作（预览/复制）
            VStack {
                HStack(spacing: 6) {
                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    Spacer()
                    if cgImage != nil {
                        Button {
                            onInspect()
                        } label: {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .help("查看图片详情")
                    }
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .help("复制图片到剪贴板")
                }
                .padding(8)
                Spacer()
            }

            // 底部暗色渐变层 + 年月日时分秒时间
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                HStack {
                    Text(DateFormatter.lensoFullDateTime.string(from: item.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 28)
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // 复制成功的覆盖反馈
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.green)
                        Text("已复制")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                }
                .transition(.opacity)
            }
        }
        .frame(height: 185)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onCopy() }
    }
}

/// 智能文字方块卡片（支持网址识别富卡片、代码/JSON美化、长文本查看与年月日时分秒）
struct SearchPanelTextTile: View {
    let item: SearchPanelView.FeedItem
    let content: String
    let isCopied: Bool
    let onCopy: () -> Void
    let onInspect: () -> Void
    @ObservedObject var webStore: WebMetadataStore

    var body: some View {
        let smartType = TextIntelligence.detect(content)

        ZStack(alignment: .topLeading) {
            // 便签卡片底板
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                // 顶部：类型标签 + 来源应用 + 查看/格式化 + 复制
                HStack(spacing: 5) {
                    switch smartType {
                    case .url:
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                            Text("网址")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))

                    case .json:
                        HStack(spacing: 3) {
                            Image(systemName: "curlybraces")
                            Text("JSON")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))

                    case .code(let lang, _):
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text(lang)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))

                    case .plainText:
                        Image(systemName: "text.quote")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                    }

                    if let app = item.sourceApp, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.04)))
                            .lineLimit(1)
                    }

                    Spacer()

                    // 查看全文 / 格式化按钮
                    Button {
                        onInspect()
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                    .help(smartType != .plainText ? "查看详情与代码美化格式化" : "查看全文并排版")

                    // 复制按钮
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("复制文本")
                }

                // 核心卡片正文区域
                switch smartType {
                case .url(let url, let origStr):
                    let title = webStore.title(for: origStr) ?? url.host ?? origStr

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .lineLimit(2)

                        if let host = url.host {
                            Text(host)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(LensoColors.kleinBlueBright)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Text("打开网页")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(LensoColors.kleinBlueBright))
                        }
                        .buttonStyle(.plain)
                        .help("在默认浏览器中打开此网页")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        webStore.fetchTitleIfNeeded(for: origStr)
                    }

                case .json(let pretty, _):
                    Text(pretty)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.3))
                        .lineSpacing(2)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                case .code(_, let formatted):
                    Text(formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.3))
                        .lineSpacing(2)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                case .plainText:
                    Text(content)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.88))
                        .lineSpacing(3)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                Divider().opacity(0.5)

                // 底部精准时间：年月日时分秒
                HStack {
                    Text(DateFormatter.lensoFullDateTime.string(from: item.createdAt))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(content.count) 字")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .padding(12)

            // 复制成功的覆盖反馈
            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.green)
                        Text("已复制")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                }
                .transition(.opacity)
            }
        }
        .frame(height: 185)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onCopy() }
    }
}
