import AppKit
import Foundation
import Observation

/// 从 GitHub Releases 检查新版本。
///
/// 项目开源，GitHub Release 是唯一的更新源：
///   正式版本打 tag（v1.0.0）并上传 DMG，这里用 `releases/latest` 比对版本号。
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    private struct ReleasePayload: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private(set) var status: Status = .idle
    private(set) var latestVersion: String?

    private let repo = "manzijian/lenso"
    private let lastCheckKey = "lenso.update.lastCheck"
    private let skippedVersionKey = "lenso.update.skippedVersion"
    private let checkInterval: TimeInterval = 24 * 60 * 60

    /// 当前运行的版本（来自 Info.plist，由发布脚本写入）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private init() {}

    /// 启动时调用：距上次检查满一天才请求；失败静默，发现新版本才提示。
    func checkIfDue() {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval { return }
        Task { await check(silent: true) }
    }

    /// 请求最新正式 Release，并与当前版本比较。
    func check(silent: Bool = false) async {
        guard status != .checking else { return }
        status = .checking

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            status = .failed("更新地址无效")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = .failed("网络响应异常")
                return
            }
            guard http.statusCode == 200 else {
                status = .failed(http.statusCode == 404 ? "暂无发布版本" : "GitHub 返回 \(http.statusCode)")
                return
            }

            let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
            let latest = payload.tagName.hasPrefix("v")
                ? String(payload.tagName.dropFirst())
                : payload.tagName

            latestVersion = latest
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if Self.compare(latest, currentVersion) == .orderedDescending {
                status = .updateAvailable(version: latest, url: payload.htmlURL)
                // 自动检查：同一版本被跳过后不再打扰
                if silent, UserDefaults.standard.string(forKey: skippedVersionKey) != latest {
                    presentUpdateAlert(version: latest, url: payload.htmlURL)
                }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed("检查失败，请稍后重试")
        }
    }

    /// 菜单或关于页主动检查：检查完给出明确反馈。
    func checkInteractively() async {
        await check(silent: false)
        switch status {
        case .updateAvailable(let version, let url):
            presentUpdateAlert(version: version, url: url)
        case .upToDate:
            presentInfo(
                title: "已是最新版本",
                message: "当前为 v\(currentVersion)，GitHub 上没有更新的正式版本。"
            )
        case .failed(let message):
            presentInfo(title: "检查更新失败", message: message)
        case .idle, .checking:
            break
        }
    }

    func openRelease(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - 提示

    private func presentUpdateAlert(version: String, url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 v\(version)"
        alert.informativeText = "当前版本 v\(currentVersion)。前往 GitHub 查看更新内容并下载？"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "跳过此版本")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openRelease(url)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(version, forKey: skippedVersionKey)
        default:
            break
        }
    }

    private func presentInfo(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 语义化版本比较：1.2.10 > 1.2.9 > 1.2
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parts(_ value: String) -> [Int] {
            value.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let lv = index < left.count ? left[index] : 0
            let rv = index < right.count ? right[index] : 0
            if lv != rv { return lv > rv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}
