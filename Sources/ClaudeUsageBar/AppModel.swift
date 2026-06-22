import Foundation
import SwiftUI
import UserNotifications

/// Owns app state, drives the polling timer, derives the menu-bar headline and
/// its color, and fires the 90% notification on an edge.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var usage: Usage?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    /// Poll interval in minutes; persisted and editable from the dropdown.
    @AppStorage("pollIntervalMinutes") var pollIntervalMinutes: Int = 5 {
        didSet { restartTimer() }
    }

    /// Notify once when crossing into >= 90%; reset when it drops back below.
    @AppStorage("notifyAt90") var notifyAt90: Bool = true

    private let keychain = KeychainReader()
    private lazy var client: UsageProviding = HeaderUsageClient(
        tokenProvider: { [keychain] in try await keychain.validAccessToken() }
    )

    private var timer: Timer?
    private var hasNotifiedHigh = false

    // MARK: Lifecycle

    func start() {
        requestNotificationAuthorization()
        restartTimer()
        Task { await refresh() }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, pollIntervalMinutes) * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Polling

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await client.fetch()
            usage = fresh
            lastError = nil
            evaluateNotification(for: fresh)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Derived display

    /// Short menu-bar string, e.g. "42%" — or a placeholder while loading / on error.
    var titleString: String {
        if let pct = usage?.headline {
            return "\(Int(pct.rounded()))%"
        }
        return lastError == nil ? "…" : "—"
    }

    /// Title color from thresholds: green < 70, amber 70–89, red >= 90.
    var titleColor: Color {
        guard let pct = usage?.headline else { return .secondary }
        switch pct {
        case ..<70: return .green
        case ..<90: return .orange
        default: return .red
        }
    }

    // MARK: Notifications

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func evaluateNotification(for usage: Usage) {
        guard notifyAt90, let pct = usage.headline else { return }
        if pct >= 90 {
            if !hasNotifiedHigh {
                hasNotifiedHigh = true
                postHighUsageNotification(pct: pct)
            }
        } else {
            hasNotifiedHigh = false
        }
    }

    private func postHighUsageNotification(pct: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Claude usage high"
        content.body = "You're at \(Int(pct.rounded()))% of your limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Launch at login (proxied for the view)

    var launchAtLoginEnabled: Bool { LaunchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            objectWillChange.send()
        } catch {
            lastError = "Launch-at-login change failed: \(error.localizedDescription)"
        }
    }
}
