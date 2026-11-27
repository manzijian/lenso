import Foundation
import SwiftUI
import WidgetKit

enum WidgetPalette {
    /// 克莱因蓝 #0538E0
    static let brand = Color(red: 5.0 / 255, green: 56.0 / 255, blue: 224.0 / 255)
    static let positive = Color(red: 0.04, green: 0.48, blue: 0.27)
}

struct WidgetCardBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        scheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color.white
    }
}

enum WidgetFormats {
    static func time(_ date: Date?) -> String {
        guard let date else { return "--:--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func legendStamp(_ date: Date, lastCapture: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d EEE"
        let head = formatter.string(from: date)
        guard let lastCapture else { return head }
        return head + " · " + time(lastCapture)
    }

    static func storage(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 小号：今日概览

struct SmallOverviewView: View {
    let snapshot: WidgetSnapshot

    private var delta: Int { snapshot.todayCount - snapshot.yesterdayCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("今日截图")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Circle()
                    .fill(WidgetPalette.brand)
                    .frame(width: 5, height: 5)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(snapshot.todayCount)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("张")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 1)

            deltaPill
                .padding(.top, 3)

            Spacer(minLength: 4)

            weekBars
                .frame(height: 30)

            HStack(spacing: 4) {
                Text("最近 \(WidgetFormats.time(snapshot.lastCaptureAt))")
                Spacer(minLength: 0)
                Text("7 日")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .padding(.top, 5)
        }
        .padding(13)
    }

    @ViewBuilder
    private var deltaPill: some View {
        if snapshot.todayCount == 0 && snapshot.yesterdayCount == 0 {
            pill("还没有记录", color: .secondary)
        } else if delta > 0 {
            pill("↑ 比昨日 +\(delta)", color: WidgetPalette.positive)
        } else if delta < 0 {
            pill("↓ 比昨日 \(delta)", color: .secondary)
        } else {
            pill("与昨日持平", color: .secondary)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var weekBars: some View {
        GeometryReader { geo in
            let maxValue = max(snapshot.last7Days.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(snapshot.last7Days.indices, id: \.self) { index in
                    let value = snapshot.last7Days[index]
                    let height = value == 0
                        ? 3.0
                        : max(7.0, geo.size.height * CGFloat(value) / CGFloat(maxValue))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == snapshot.last7Days.count - 1
                              ? WidgetPalette.brand
                              : WidgetPalette.brand.opacity(0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - 中号：今日时段分布

struct MediumHoursView: View {
    let snapshot: WidgetSnapshot

    private var peakIndex: Int {
        snapshot.hourlyToday.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    private var peakRange: String {
        guard (snapshot.hourlyToday.max() ?? 0) > 0 else { return "—" }
        let hour = snapshot.peakHour
        return String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24)
    }

    private var intervalText: String {
        guard let average = snapshot.averageIntervalMinutes else { return "—" }
        return "\(Int(average.rounded())) 分"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日时段分布")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer(minLength: 8)
                Text("共 \(snapshot.todayCount) 张")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            bars
                .frame(height: 62)
                .padding(.top, 10)

            hourLabels
                .padding(.top, 4)

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                footItem("高峰", peakRange)
                dot
                footItem("平均间隔", intervalText)
                Spacer(minLength: 4)
                Text(WidgetFormats.time(snapshot.lastCaptureAt))
                    .monospacedDigit()
            }
            .font(.system(size: 8.5))
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    private var bars: some View {
        GeometryReader { geo in
            let maxValue = max(snapshot.hourlyToday.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(snapshot.hourlyToday.indices, id: \.self) { index in
                    let value = snapshot.hourlyToday[index]
                    let height = value == 0
                        ? 3.0
                        : max(6.0, geo.size.height * CGFloat(value) / CGFloat(maxValue))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == peakIndex && value > 0
                              ? WidgetPalette.brand
                              : WidgetPalette.brand.opacity(0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
            }
        }
    }

    private var hourLabels: some View {
        let labels = ["0", "3", "6", "9", "12", "15", "18", "21", "23"]
        return HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .font(.system(size: 7.5))
                    .foregroundStyle(.secondary)
                if index < labels.count - 1 { Spacer(minLength: 0) }
            }
        }
    }

    private func footItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private var dot: some View {
        Circle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 2, height: 2)
    }
}

// MARK: - 大号：本月热力图

struct LargeHeatmapView: View {
    let snapshot: WidgetSnapshot
    let date: Date

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    private var rowCount: Int {
        max(1, Int(ceil(Double(snapshot.leadingBlanks + snapshot.monthDays) / 7.0)))
    }

    private var dailyAverage: Double {
        guard snapshot.todayDay > 0 else { return 0 }
        return Double(snapshot.monthTotal) / Double(snapshot.todayDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .bottom, spacing: 18) {
                stat("\(snapshot.monthTotal)", label: "本月截图")
                stat("\(snapshot.todayCount)", label: "今日")
                stat(String(format: "%.1f", dailyAverage), label: "日均")
            }
            .padding(.top, 9)
            .padding(.bottom, 9)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            calendarGrid
                .padding(.top, 8)

            Spacer(minLength: 6)

            legendRow

            footer
                .padding(.top, 8)
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(snapshot.monthNumber) 月热力图")
                .font(.system(size: 12, weight: .bold))
            Text("\(snapshot.monthYear)")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text("今日 \(snapshot.todayCount)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetPalette.brand)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WidgetPalette.brand.opacity(0.09), in: Capsule())
        }
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 7.5))
                .foregroundStyle(.secondary)
        }
    }

    private var calendarGrid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column - snapshot.leadingBlanks
                        if index >= 0 && index < snapshot.monthDays {
                            dayCell(day: index + 1, count: snapshot.monthDaily[index])
                        } else {
                            Color.clear
                                .frame(height: 28)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(day: Int, count: Int) -> some View {
        let isFuture = day > snapshot.todayDay
        let isToday = day == snapshot.todayDay
        let level = heatLevel(count, isFuture: isFuture)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(fillColor(level: level, isFuture: isFuture))
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .overlay {
                if isFuture {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("\(day)")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(numberColor(level: level, isFuture: isFuture))
                    .padding(.leading, 4)
                    .padding(.top, 3)
            }
    }

    private func heatLevel(_ count: Int, isFuture: Bool) -> Int {
        guard !isFuture, count > 0 else { return 0 }
        switch count {
        case 1: return 1
        case 2...3: return 2
        case 4...6: return 3
        default: return 4
        }
    }

    private func fillColor(level: Int, isFuture: Bool) -> Color {
        if isFuture { return .clear }
        switch level {
        case 0: return WidgetPalette.brand.opacity(0.05)
        case 1: return WidgetPalette.brand.opacity(0.14)
        case 2: return WidgetPalette.brand.opacity(0.30)
        case 3: return WidgetPalette.brand.opacity(0.52)
        default: return WidgetPalette.brand
        }
    }

    private func numberColor(level: Int, isFuture: Bool) -> Color {
        if isFuture { return Color.primary.opacity(0.15) }
        if level >= 3 { return .white }
        return Color.primary.opacity(0.55)
    }

    private var legendRow: some View {
        HStack(spacing: 3) {
            Text("少")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fillColor(level: level, isFuture: false))
                    .frame(width: 9, height: 9)
            }
            Text("多")
            Spacer(minLength: 6)
            Text(WidgetFormats.legendStamp(date, lastCapture: snapshot.lastCaptureAt))
                .monospacedDigit()
        }
        .font(.system(size: 7.5))
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            metaItem("存储", WidgetFormats.storage(snapshot.storageBytes))
            dot
            metaItem("保留", snapshot.retentionLabel)
            Spacer(minLength: 4)
            metaItem("共", "\(snapshot.totalCount) 张")
        }
        .font(.system(size: 8.5))
    }

    private func metaItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private var dot: some View {
        Circle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 2, height: 2)
    }
}

// MARK: - 入口

struct LensoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LensoEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallOverviewView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumHoursView(snapshot: entry.snapshot)
        default:
            LargeHeatmapView(snapshot: entry.snapshot, date: entry.date)
        }
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        generatedAt: Date(),
        todayCount: 12,
        yesterdayCount: 9,
        last7Days: [3, 5, 2, 7, 4, 9, 12],
        hourlyToday: [
            0, 0, 0, 0, 0, 1, 2, 1, 3, 4, 2, 5,
            3, 6, 8, 4, 2, 1, 1, 0, 0, 0, 0, 0
        ],
        peakHour: 14,
        averageIntervalMinutes: 42,
        monthYear: 2026,
        monthNumber: 11,
        monthDays: 30,
        leadingBlanks: 6,
        todayDay: 17,
        monthDaily: [
            0, 1, 3, 0, 5, 2, 0, 3, 4, 6, 2, 0, 0, 4, 3,
            2, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ],
        monthTotal: 47,
        lastCaptureAt: Date(),
        storageBytes: 1_240_000_000,
        totalCount: 386,
        retentionLabel: "30 天"
    )
}
