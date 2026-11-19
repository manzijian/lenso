import SwiftUI
import AppKit

extension AnalyticsDashboardView {

    // MARK: - 模块 1：每日数据变化趋势 (Daily Activity Trend)

    func dailyTrendCard(_ data: ScreenshotStore.AnalyticsData) -> some View {
        let stats = data.dailyStats
        let maxCount = max(1, stats.map(\.totalCount).max() ?? 1)
        let totalPeriod = stats.map(\.totalCount).reduce(0, +)
        let avgDaily = Double(totalPeriod) / Double(max(1, stats.count))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("每日数据变化趋势")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.9))
                        Text("(近 \(scopeDays) 天)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text("共产生 \(totalPeriod) 次操作 · 日均产生 \(String(format: "%.1f", avgDaily)) 条记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 图例说明 (Legend)
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(LensoColors.kleinBlueBright).frame(width: 10, height: 10)
                        Text("截图").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.35, green: 0.65, blue: 0.95)).frame(width: 10, height: 10)
                        Text("复制文字").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            Divider().opacity(0.5)

            // 柱状图主体
            HStack(alignment: .bottom, spacing: scopeDays <= 7 ? 20 : (scopeDays <= 14 ? 10 : 4)) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, item in
                    let isHovered = hoveredDailyIndex == index
                    let ratio = CGFloat(item.totalCount) / CGFloat(maxCount)
                    let barHeight = max(6, ratio * 140)

                    VStack(spacing: 6) {
                        // 柱子主体（堆叠：上层复制文字，下层截图）
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .frame(height: 140)

                            VStack(spacing: 1) {
                                // 文字部分
                                if item.textCount > 0 {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(red: 0.35, green: 0.65, blue: 0.95))
                                        .frame(height: max(3, CGFloat(item.textCount) / CGFloat(maxCount) * 140))
                                }
                                // 截图部分
                                if item.screenshotsCount > 0 {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(LensoColors.kleinBlueBright)
                                        .frame(height: max(3, CGFloat(item.screenshotsCount) / CGFloat(maxCount) * 140))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)

                        // X 轴日期文本
                        Text(item.dateString)
                            .font(.system(size: scopeDays <= 14 ? 10 : 9, weight: isHovered ? .bold : .regular))
                            .foregroundStyle(isHovered ? LensoColors.kleinBlueBright : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { h in
                        hoveredDailyIndex = h ? index : (hoveredDailyIndex == index ? nil : hoveredDailyIndex)
                    }
                    .help("\(item.fullDateString): 截图 \(item.screenshotsCount) 张 · 复制文字 \(item.textCount) 条 (合计 \(item.totalCount) 次)")
                }
            }
            .frame(height: 175)

            // 悬浮条目提示详情
            if let idx = hoveredDailyIndex, idx < stats.count {
                let cur = stats[idx]
                HStack(spacing: 12) {
                    Text(cur.fullDateString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                    Text("截图: \(cur.screenshotsCount) 张")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Text("复制文字: \(cur.textCount) 条")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Text("当日合计: \(cur.totalCount) 次")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(LensoColors.kleinBlueSoft))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }

    // MARK: - 模块 2：具体每小时的数据量分布 (00:00 - 23:00)

    func hourlyDistributionCard(_ data: ScreenshotStore.AnalyticsData) -> some View {
        let stats = data.hourlyStats
        let maxHourlyCount = max(1, stats.map(\.totalCount).max() ?? 1)

        // 时段统计
        let morningSum = stats[6..<12].map(\.totalCount).reduce(0, +)
        let afternoonSum = stats[12..<18].map(\.totalCount).reduce(0, +)
        let eveningSum = stats[18..<24].map(\.totalCount).reduce(0, +)
        let nightSum = stats[0..<6].map(\.totalCount).reduce(0, +)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("每小时数据量分布")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.9))
                        Text("(24 小时全天时段)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text("统计全天 00:00 至 23:00 的操作频次，最高峰时段为 \(String(format: "%02d:00 - %02d:59", data.peakHour, data.peakHour))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 时段轻胶囊
                HStack(spacing: 6) {
                    periodTag("早晨 06-12", count: morningSum)
                    periodTag("下午 12-18", count: afternoonSum, isHighlight: true)
                    periodTag("晚上 18-24", count: eveningSum)
                    periodTag("深夜 00-06", count: nightSum)
                }
            }

            Divider().opacity(0.5)

            // 24 小时直方图
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(stats) { hItem in
                    let isHovered = hoveredHour == hItem.hour
                    let isPeak = hItem.hour == data.peakHour && hItem.totalCount > 0
                    let ratio = CGFloat(hItem.totalCount) / CGFloat(maxHourlyCount)
                    let barH = max(4, ratio * 120)

                    VStack(spacing: 5) {
                        // 柱体
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .frame(height: 120)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isPeak ? LensoColors.kleinBlueBright : (isHovered ? Color.blue : Color(red: 0.65, green: 0.75, blue: 0.9)))
                                .frame(height: barH)
                        }
                        .frame(maxWidth: .infinity)
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)

                        // 小时刻度标签（每两小时标一次或全标）
                        Text(String(format: "%02d", hItem.hour))
                            .font(.system(size: 9, weight: isPeak ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isPeak ? LensoColors.kleinBlueBright : (hItem.hour % 3 == 0 ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.4)))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { h in
                        hoveredHour = h ? hItem.hour : (hoveredHour == hItem.hour ? nil : hoveredHour)
                    }
                    .help("\(String(format: "%02d:00", hItem.hour)) - \(String(format: "%02d:59", hItem.hour)): 共 \(hItem.totalCount) 次 (截图 \(hItem.screenshotsCount) 张，复制文字 \(hItem.textCount) 条)")
                }
            }
            .frame(height: 150)

            // 悬浮小时详情提示
            if let h = hoveredHour, h < stats.count {
                let cur = stats[h]
                HStack(spacing: 12) {
                    Text(String(format: "时段 %02d:00 - %02d:59", cur.hour, cur.hour))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                    Text("截图: \(cur.screenshotsCount) 张")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Text("复制文字: \(cur.textCount) 条")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.85))
                    Text("总计: \(cur.totalCount) 次")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(LensoColors.kleinBlueSoft))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }

    private func periodTag(_ label: String, count: Int, isHighlight: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(isHighlight ? LensoColors.kleinBlueSoft : Color.black.opacity(0.04)))
        .foregroundStyle(isHighlight ? LensoColors.kleinBlueBright : Color.secondary)
    }

    // MARK: - 模块 3：来源应用排行榜

    func topAppsCard(_ data: ScreenshotStore.AnalyticsData) -> some View {
        // 只展示前 5 个，和副标题一致；条形长度按第一名归一化，避免溢出卡片
        let apps = Array(data.topApps.prefix(5))
        let maxCount = max(1, apps.map(\.count).max() ?? 1)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("高频来源应用排行")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.9))
                Text("统计产生截图与剪贴板内容最活跃的前 5 个应用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            VStack(spacing: 10) {
                if apps.isEmpty {
                    Text("暂无应用数据")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(apps) { app in
                        VStack(spacing: 4) {
                            HStack {
                                Text(app.appName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.85))
                                Spacer()
                                Text("\(app.count) 次")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", app.percentage))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(LensoColors.kleinBlueBright)
                                    .frame(width: 48, alignment: .trailing)
                            }

                            // 进度条：按第一名归一化，最大 100%，不会超出卡片
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.black.opacity(0.05))
                                        .frame(height: 6)
                                    Capsule()
                                        .fill(LensoColors.kleinBlueBright)
                                        .frame(
                                            width: max(6, geo.size.width * CGFloat(app.count) / CGFloat(maxCount)),
                                            height: 6
                                        )
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }

    // MARK: - 模块 4：存储概览与自动清理看板

    func storageAndRetentionCard(_ data: ScreenshotStore.AnalyticsData) -> some View {
        let settings = AppSettings.shared

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("数据留存与自动清理状态")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.9))
                Text("自动删除达到设定期限的历史数据，释放磁盘")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前保存期限")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(settings.retentionPreset.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.9))
                    }
                    Spacer()
                    if let hours = settings.effectiveRetentionHours {
                        Text("(\(hours) 小时到期)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "star.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("星标收藏保护")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(settings.preserveFavoritesOnCleanup ? "已开启（收藏内容永不删除）" : "未开启（一同按时间清理）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.85))
                    }
                }

                Divider().opacity(0.4)

                HStack {
                    if let cutoff = settings.retentionCutoffDate {
                        Text("截止时间: \(DateFormatter.lensoFullDateTime.string(from: cutoff))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("所有记录将永久保留")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let res = settings.runAutoCleanup() {
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
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("立即清理")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LensoColors.kleinBlueBright)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(LensoColors.kleinBlueSoft))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
    }
}
