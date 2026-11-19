import Foundation
import WidgetKit

/// 数据变化后写入小组件快照并刷新时间线。
/// 事件驱动（截图 / 图库变更）+ 定时兜底。
@MainActor
final class WidgetSnapshotCoordinator {
    static let shared = WidgetSnapshotCoordinator()

    private var scheduled: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        for name in [Notification.Name.screenshotSaved, .libraryChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRefresh()
                }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        refresh()
    }

    /// 合并短时间内的连续变更，避免批量删除时反复汇总。
    func scheduleRefresh() {
        scheduled?.cancel()
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        let retentionLabel = Self.retentionLabel(for: AppSettings.shared.effectiveRetentionHours)
        Task.detached(priority: .utility) {
            let snapshot = ScreenshotStore.shared.makeWidgetSnapshot(retentionLabel: retentionLabel)
            do {
                try WidgetSnapshotStore.save(snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: LensoWidgetKind.identifier)
            } catch {
                storeLog.error("Failed to write widget snapshot: \(error.localizedDescription)")
            }
        }
    }

    private static func retentionLabel(for hours: Int?) -> String {
        guard let hours else { return "永久保存" }
        if hours % 24 == 0 { return "\(hours / 24) 天" }
        return "\(hours) 小时"
    }
}
