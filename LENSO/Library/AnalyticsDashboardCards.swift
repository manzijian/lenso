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
                            .monospacedDigit()
                    }
                    Text("共产生 \(totalPeriod) 次操作 · 日均产生 \(String(format: "%.1f", avgDaily)) 条记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
                                .fill(Color.primary.opacity(0.05))
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
                            .lensoAnimation(LensoAnimations.gentle, value: item.totalCount, reduceMotion: reduceMotion)
                        }
                        .frame(maxWidth: .infinity)
                        .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1.0)
                        .lensoAnimation(LensoAnimations.hover, value: isHovered, reduceMotion: reduceMotion)

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

            // 悬浮条目提示详情（固定高度占位，避免悬浮抖动）
            ZStack(alignment: .leading) {
                if let idx = hoveredDailyIndex, idx < stats.count {
                    let cur = stats[idx]
                    HStack(spacing: 12) {
                        Text(cur.fullDateString)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .monospacedDigit()
                        Text("截图: \(cur.screenshotsCount) 张")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .monospacedDigit()
                        Text("复制文字: \(cur.textCount) 条")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .monospacedDigit()
                        Text("当日合计: \(cur.totalCount) 次")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .monospacedDigit()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(LensoColors.kleinBlueSoft))
                } else {
                    Text("将鼠标悬停在柱状图上可查看当日明细")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .padding(.horizontal, 4)
                }
            }
            .frame(height: 28)
            .lensoAnimation(LensoAnimations.quickFade, value: hoveredDailyIndex, reduceMotion: reduceMotion)
        }
        .padding(20)
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

    // MARK: - 模块 2：具体每小时的数据量分布 (00:00 - 23:00)

    func hourlyDistributionCard(_ data: ScreenshotStore.AnalyticsData) -> some View {
        let stats = data.hourlyStats
        let rawMaxHourlyCount = stats.map(\.totalCount).max() ?? 0
        let maxHourlyCount = max(1, rawMaxHourlyCount)
        let peakHourText = rawMaxHourlyCount > 0
            ? String(format: "%02d:00 - %02d:59", data.peakHour, data.peakHour)
            : "—"

        // 时段统计
        let morningSum = stats[6..<12].map(\.totalCount).reduce(0, +)
        let afternoonSum = stats[12..<18].map(\.totalCount).reduce(0, +)
        let eveningSum = stats[18..<24].map(\.totalCount).reduce(0, +)
        let nightSum = stats[0..<6].map(\.totalCount).reduce(0, +)
        let maxPeriodSum = [morningSum, afternoonSum, eveningSum, nightSum].max() ?? 0

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
                    Text("统计全天 00:00 至 23:00 的操作频次，最高峰时段为 \(peakHourText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                // 时段轻胶囊
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        periodTag("早晨 06-12", count: morningSum, isHighlight: maxPeriodSum > 0 && morningSum == maxPeriodSum)
                        periodTag("下午 12-18", count: afternoonSum, isHighlight: maxPeriodSum > 0 && afternoonSum == maxPeriodSum)
                        periodTag("晚上 18-24", count: eveningSum, isHighlight: maxPeriodSum > 0 && eveningSum == maxPeriodSum)
                        periodTag("深夜 00-06", count: nightSum, isHighlight: maxPeriodSum > 0 && nightSum == maxPeriodSum)
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            periodTag("早晨 06-12", count: morningSum, isHighlight: maxPeriodSum > 0 && morningSum == maxPeriodSum)
                            periodTag("下午 12-18", count: afternoonSum, isHighlight: maxPeriodSum > 0 && afternoonSum == maxPeriodSum)
                        }
                        HStack(spacing: 6) {
                            periodTag("晚上 18-24", count: eveningSum, isHighlight: maxPeriodSum > 0 && eveningSum == maxPeriodSum)
                            periodTag("深夜 00-06", count: nightSum, isHighlight: maxPeriodSum > 0 && nightSum == maxPeriodSum)
                        }
                    }
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
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 120)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isPeak ? LensoColors.kleinBlueBright : (isHovered ? Color.blue : Color(red: 0.65, green: 0.75, blue: 0.9)))
                                .frame(height: barH)
                                .lensoAnimation(LensoAnimations.gentle, value: hItem.totalCount, reduceMotion: reduceMotion)
                        }
                        .frame(maxWidth: .infinity)
                        .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1.0)
                        .lensoAnimation(LensoAnimations.hover, value: isHovered, reduceMotion: reduceMotion)

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

            // 悬浮小时详情提示（固定高度占位，避免悬浮抖动）
            ZStack(alignment: .leading) {
                if let h = hoveredHour, h < stats.count {
                    let cur = stats[h]
                    HStack(spacing: 12) {
                        Text(String(format: "时段 %02d:00 - %02d:59", cur.hour, cur.hour))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LensoColors.kleinBlueBright)
                            .monospacedDigit()
                        Text("截图: \(cur.screenshotsCount) 张")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .monospacedDigit()
                        Text("复制文字: \(cur.textCount) 条")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .monospacedDigit()
                        Text("总计: \(cur.totalCount) 次")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .monospacedDigit()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(LensoColors.kleinBlueSoft))
                } else {
                    Text("将鼠标悬停在时段柱上可查看该小时明细")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .padding(.horizontal, 4)
                }
            }
            .frame(height: 28)
            .lensoAnimation(LensoAnimations.quickFade, value: hoveredHour, reduceMotion: reduceMotion)
        }
        .padding(20)
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

    private func periodTag(_ label: String, count: Int, isHighlight: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(isHighlight ? LensoColors.kleinBlueSoft : Color.primary.opacity(0.05)))
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
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                        Text("暂无应用数据")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .padding(.vertical, 12)
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
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", app.percentage))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(LensoColors.kleinBlueBright)
                                    .frame(width: 48, alignment: .trailing)
                            }

                            // 进度条：按第一名归一化，最大 100%，不会超出卡片
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 6)
                                    Capsule()
                                        .fill(LensoColors.kleinBlueBright)
                                        .frame(
                                            width: max(6, geo.size.width * CGFloat(app.count) / CGFloat(maxCount)),
                                            height: 6
                                        )
                                        .lensoAnimation(LensoAnimations.gentle, value: app.count, reduceMotion: reduceMotion)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                            .monospacedDigit()
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
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("所有记录将永久保留")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if settings.retentionCutoffDate != nil {
                        Button {
                            showCleanupConfirm = true
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
                        .buttonStyle(LensoPressButtonStyle())
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}
