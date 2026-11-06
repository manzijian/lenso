import SwiftUI

/// Spotlight 风格搜索浮动窗口 — 居中胶囊输入 + 展开结果缩略图
struct SearchPanelView: View {
    @State private var searchText = ""
    @State private var focused = false

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let appName: String
        let snippet: String
    }

    private let demoResults: [SearchResult] = [
        SearchResult(title: "架构评审会议记录", appName: "预览", snippet: "……FTS5 中文分词需要验证召回率……"),
        SearchResult(title: "CaptureService.swift", appName: "Xcode", snippet: "……捕获完成后优先保存流程……"),
        SearchResult(title: "产品设计讨论", appName: "微信", snippet: "……玻璃材质只用于悬浮层……"),
    ]

    private var filtered: [SearchResult] {
        searchText.isEmpty ? [] : demoResults.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.snippet.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: LensoSpacing.s) {
            LensoMaterials.glassContainer {
                HStack(spacing: LensoSpacing.m) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("搜索截图内容、应用、标签…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(LensoTypography.title)
                        .onSubmit { }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LensoSpacing.l)
                .frame(height: 56)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LensoRadius.panel))
            }

            if !filtered.isEmpty {
                VStack(spacing: 0) {
                    ForEach(filtered) { result in
                        HStack(spacing: LensoSpacing.m) {
                            RoundedRectangle(cornerRadius: LensoRadius.control)
                                .fill(LensoColors.accent.opacity(0.25))
                                .frame(width: 56, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(LensoTypography.callout)
                                Text(result.snippet).font(LensoTypography.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(result.appName).font(LensoTypography.caption).foregroundStyle(.tertiary)
                        }
                        .padding(LensoSpacing.m)
                        .background {
                            RoundedRectangle(cornerRadius: LensoRadius.control)
                                .fill(.clear)
                        }
                        .contentShape(Rectangle())
                    }
                    if filtered.count > 1 { Divider().padding(.horizontal, LensoSpacing.m) }
                }
                .frame(width: 620)
                .background {
                    RoundedRectangle(cornerRadius: LensoRadius.panel)
                        .fill(.bar.opacity(0.85))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(LensoAnimations.panel, value: filtered.map(\.id))
        .padding(.horizontal, LensoSpacing.xxl)
    }
}
