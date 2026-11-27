import SwiftUI
import AppKit

/// LENSO 统计分析看板
/// 提供每日数据变化趋势、24小时每小时数据量分布、来源应用排行与存储清理状态
struct AnalyticsDashboardView: View {
    @State var scopeDays: Int = 14
    @State private var data: ScreenshotStore.AnalyticsData?
    @State var hoveredDailyIndex: Int?
    @State var hoveredHour: Int?
    @State var showCleanupConfirm = false

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private let store = ScreenshotStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 顶部标题栏与周期切换
                headerView

                if let data {
                    Group {
                        // 核心 4 大指标卡片 (KPI Cards)
                        metricsGrid(data)

                        // 模块 1：每日数据变化趋势
                        dailyTrendCard(data)

                        // 模块 2：具体每小时的数据量分布 (00:00 - 23:00)
                        hourlyDistributionCard(data)

                        // 模块 3：来源应用排行榜与存储概览
                        HStack(alignment: .top, spacing: 16) {
                            topAppsCard(data)
                                .frame(maxHeight: .infinity, alignment: .top)
                            storageAndRetentionCard(data)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                } else {
                    loadingView
                        .transition(.opacity)
                }
            }
            .padding(24)
            .lensoAnimation(LensoAnimations.fade, value: data != nil, reduceMotion: reduceMotion)
            .lensoAnimation(LensoAnimations.snappy, value: scopeDays, reduceMotion: reduceMotion)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadData() }
        .onChange(of: scopeDays) { _ in loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryChanged)) { _ in
            loadData()
        }
        .alert("确定立即清理过期数据？", isPresented: $showCleanupConfirm) {
            Button("立即清理", role: .destructive) {
                if let res = AppSettings.shared.runAutoCleanup() {
                    if res.totalDeleted > 0 {
                        SaveToastController.shared.show(
                            title: "清理完成",
                            subtitle: "已删除 \(res.totalDeleted) 项过期数据",
                            thumbnail: nil
                        )
                    } else {
                        SaveToastController.shared.show(
                            title: "已是最新",
                            subtitle: "暂无符合期限的过期记录",
                            thumbnail: nil
                        )
                    }
                    loadData()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将根据当前保存期限设置删除过期数据，此操作不可撤销。")
        }
    }

    private func loadData() {
        data = store.fetchAnalyticsData(scopeDays: scopeDays)
    }

    // MARK: - 顶部标题与周期选择

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("数据看板与统计分析")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.92))

                    Text("实时追踪")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                }

                Text("深入洞悉每日截图与文字复制趋势、24小时活跃时段及数据留存状态")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 范围切换器
            Picker("", selection: $scopeDays) {
                Text("近 7 天").tag(7)
                Text("近 14 天").tag(14)
                Text("近 30 天").tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            // 刷新按钮
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LensoColors.kleinBlueBright)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
            }
            .buttonStyle(LensoPressButtonStyle())
            .help("刷新看板统计")
        }
    }

    // MARK: - 核心 KPI 指标卡

    private func metricsGrid(_ data: ScreenshotStore.AnalyticsData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 14)], spacing: 14) {
            metricCard(
                title: "截图归集总数",
                value: "\(data.totalScreenshots)",
                unit: "张",
                badge: data.todayScreenshots > 0 ? "今日 +\(data.todayScreenshots)" : "今日暂无",
                badgeColor: data.todayScreenshots > 0 ? LensoColors.kleinBlueBright : .secondary,
                icon: "camera.viewfinder",
                accentColor: LensoColors.kleinBlueBright
            )

            metricCard(
                title: "文字复制记录",
                value: "\(data.totalTextClips)",
                unit: "条",
                badge: data.todayTextClips > 0 ? "今日 +\(data.todayTextClips)" : "今日暂无",
                badgeColor: data.todayTextClips > 0 ? Color(red: 0.1, green: 0.65, blue: 0.45) : .secondary,
                icon: "doc.text.fill",
                accentColor: Color(red: 0.1, green: 0.65, blue: 0.45)
            )

            metricCard(
                title: "文字收纳便签",
                value: "\(data.totalNotes)",
                unit: "条",
                badge: "常驻精选",
                badgeColor: Color(red: 0.95, green: 0.55, blue: 0.1),
                icon: "note.text",
                accentColor: Color(red: 0.95, green: 0.55, blue: 0.1)
            )

            metricCard(
                title: "占用磁盘空间",
                value: String(format: "%.1f", Double(data.totalDiskBytes) / (1024 * 1024)),
                unit: "MB",
                badge: "原图+缩略",
                badgeColor: Color.purple,
                icon: "externaldrive.fill",
                accentColor: Color.purple
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        unit: String,
        badge: String,
        badgeColor: Color,
        icon: String,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accentColor.opacity(0.12)))

                Spacer()

                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(badgeColor.opacity(0.1)))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .lensoNumericTransition()

                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在聚合统计分析数据…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
