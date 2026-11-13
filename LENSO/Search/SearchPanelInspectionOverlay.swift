import SwiftUI
import AppKit

/// 搜索浮窗内置详情查看层（杜绝 borderless 窗口下系统 sheet 失效及失去焦点关闭）
struct SearchPanelInspectionOverlay: View {
    @Binding var item: SearchPanelView.FeedItem?
    let onCopyItem: (SearchPanelView.FeedItem) -> Void
    let onPinImage: (CGImage) -> Void

    var body: some View {
        if let currentItem = item {
            ZStack {
                // 半透明背景遮罩
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    item = nil
                                }
                            }
                        )
                        .frame(width: 800, height: 540)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 10)

                    case .image(let cgImage, _):
                        imageLightboxView(item: currentItem, cgImage: cgImage)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
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

                Text(DateFormatter.lensoFullDateTime.string(from: item.createdAt))
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
                    .buttonStyle(.plain)

                    Button {
                        onCopyItem(item)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("复制图片")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.item = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
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
                } else {
                    Text("无法加载图片内容")
                        .foregroundStyle(.secondary)
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
