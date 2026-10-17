import AppKit
import Observation
import Sparkle

/// Sparkle で更新を確認し、署名を検証してから入れ替える。
/// 更新情報の URL と公開鍵は配布用のビルド（scripts/package-app.sh）だけが Info.plist に入れるので、
/// それがない開発中のビルドでは何もしない。
@MainActor
@Observable
final class AppUpdater: NSObject {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    let isAvailable: Bool
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        isAvailable =
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
            && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
        super.init()
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor in self?.automaticallyChecksForUpdates = value }
            },
        ]
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        // Sparkle が設定を保存する。ここで別に持ったり、起動時に上書きしたりしない
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
