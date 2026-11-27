import SwiftUI
import AppKit

/// 搜索浮窗内置详情查看层（杜绝 borderless 窗口下系统 sheet 失效及失去焦点关闭）
struct SearchPanelInspectionOverlay: View {
    @Binding var item: SearchPanelView.FeedItem?
    let onCopyItem: (SearchPanelView.FeedItem) -> Void
    let onPinImage: (CGImage) -> Void

    @State private var fullImage: CGImage?
    @State private var isLoadingFullImage = false
    @State private var loadFailed = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let currentItem = item {
            ZStack {
                // 半透明背景遮罩
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                            item = nil
                        }
                    }

                // 内容卡片
                Group {
                    switch currentItem.kind {
                    case .text(let content):
                        TextDetailInspectorSheet(
                            rawContent: content,
                            sourceApp: currentItem.sourceApp,
                            createdAt: currentItem.createdAt,
                            onDismiss: {
                                LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                                    item = nil
                                }
                            }
                        )
                        .frame(width: 800, height: 540)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)

                    case .image(let cgImage, _):
                        imageLightboxView(item: currentItem, cgImage: fullImage ?? cgImage)
                            .task(id: currentItem.id) {
                                fullImage = nil
                                copied = false
                                loadFailed = false
                                guard let record = currentItem.record else {
                                    isLoadingFullImage = false
                                    loadFailed = (cgImage == nil)
                                    return
                                }
                                isLoadingFullImage = true
                                let image = await ScreenshotStore.loadImageAsync(record)
                                if !Task.isCancelled {
                                    isLoadingFullImage = false
                                    if let image {
                                        LensoAnimations.withMotion(LensoAnimations.fade, reduceMotion: reduceMotion) {
                                            fullImage = image
                                        }
                                    } else if cgImage == nil {
                                        loadFailed = true
                                    }
                                }
                            }
                    }
                }
                .transition(LensoTransitions.overlayCard(reduceMotion: reduceMotion))
            }
            .transition(.opacity)
        }
    }

    private func imageLightboxView(item: SearchPanelView.FeedItem, cgImage: CGImage?) -> some View {
        VStack(spacing: 0) {
            // 顶部信息与操作栏
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(LensoColors.kleinBlueBright)

                Text("截图详情")
                    .font(.system(size: 13, weight: .bold))

                if let app = item.sourceApp, !app.isEmpty {
                    Text(app)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }

                Spacer()

                Text(item.createdAt.lensoRelativeDayTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if let cgImage {
                    Button {
                        onPinImage(cgImage)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                            Text("置顶预览")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(LensoPressButtonStyle())

                    Button {
                        onCopyItem(item)
                        LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                            copied = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            await MainActor.run {
                                LensoAnimations.withMotion(LensoAnimations.snappy, reduceMotion: reduceMotion) {
                                    copied = false
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: copied ? .semibold : .regular))
                                .foregroundStyle(copied ? Color.green : Color.primary.opacity(0.85))
                                .lensoSymbolReplace()
                            Text(copied ? "已复制" : "复制图片")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(copied ? Color.green : Color.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(copied ? Color.green.opacity(0.12) : Color.black.opacity(0.06)))
                    }
                    .buttonStyle(LensoPressButtonStyle())
                }

                HStack(spacing: 4) {
                    Text("Esc")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    Text("关闭")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Button {
                    LensoAnimations.withMotion(LensoAnimations.panel, reduceMotion: reduceMotion) {
                        self.item = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(LensoPressButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

            Divider()

            // 图片预览区
            ZStack {
                Color(red: 0.95, green: 0.955, blue: 0.97)

                if let cgImage {
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                        .transition(.opacity)
                } else if isLoadingFullImage {
                    ProgressView()
                        .controlSize(.small)
                } else if loadFailed {
                    Text("无法加载图片内容")
                        .foregroundStyle(.secondary)
                }

                if cgImage != nil && isLoadingFullImage {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("正在加载高清原图…")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 530)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)
    }
}
