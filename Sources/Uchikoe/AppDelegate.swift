import AVFoundation
import AppKit
import SwiftUI
import UchikoeCore

/// メニューバーに常駐し、設定したキーで録音して、文字にしたものを前面のアプリへ貼り付ける。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State {
        case idle
        case recording
        case processing
    }

    private static let minimumSamples = Int(SpeechRecognizer.format.sampleRate * 0.3)

    private let settings = AppSettings()
    private let recognizer = SpeechRecognizer()
    private let polisher = Polisher()
    private let recorder = Recorder()
    private let updater = AppUpdater()
    private lazy var keyMonitor = KeyMonitor(shortcut: settings.shortcut)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var state = State.idle
    private var recognizerStatus: String?
    private var polisherUnavailableReason: String?
    private var lastResult: String?
    private var lastDetail: String?

    /// 履歴と録音を置く場所（~/Library/Application Support/Uchikoe）
    private let outputDir = AppSettings.supportDirectory

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        keyMonitor.onPress = { [weak self] in self?.shortcutPressed() }
        keyMonitor.onRelease = { [weak self] in self?.shortcutReleased() }
        keyMonitor.onInterrupt = { [weak self] in self?.shortcutInterrupted() }
        observeSettings()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if !Paster.canSendKeys { Paster.requestAccessibility() }
        startKeyMonitor()
        prepare()
        rebuildMenu()
    }

    /// キーの見張りにはアクセシビリティの許可が要る。許可されるまで待って始める
    private func startKeyMonitor() {
        guard !keyMonitor.start() else { return }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.keyMonitor.start() else { return }
                timer.invalidate()
                self.rebuildMenu()
            }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.shortcut
            _ = settings.recordingMode
            _ = settings.polishes
            _ = settings.vocabularyLists
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.keyMonitor.shortcut = self.settings.shortcut
                self.rebuildMenu()
                self.observeSettings()
            }
        }
    }

    private func prepare() {
        recognizerStatus = "準備中…"
        Task {
            polisherUnavailableReason = await polisher.unavailableReason
            if polisherUnavailableReason == nil { await polisher.prewarm() }
            do {
                try await recognizer.prepare()
                recognizerStatus = nil
            } catch {
                recognizerStatus = "準備に失敗: \(error.localizedDescription)"
            }
            rebuildMenu()
        }
    }

    // MARK: - キー

    private var triggersOnRelease: Bool {
        // 修飾キーだけのキー（fn など）で切り替え式のときは、離したときに切り替える。
        // 押した時点で切り替えると、fn+← のような操作でも録音が始まってしまうため。
        settings.recordingMode == .toggle && settings.shortcut.isModifierOnly
    }

    private func shortcutPressed() {
        switch settings.recordingMode {
        case .hold: startRecording()
        case .toggle: if !triggersOnRelease { toggleRecording() }
        }
    }

    private func shortcutReleased() {
        switch settings.recordingMode {
        case .hold: if case .recording = state { finishRecording() }
        case .toggle: if triggersOnRelease { toggleRecording() }
        }
    }

    /// 押している間に別のキーが押された。押している間だけ録音するときは、録音を捨てる
    private func shortcutInterrupted() {
        guard settings.recordingMode == .hold, case .recording = state else { return }
        _ = recorder.stop()
        state = .idle
        updateIcon()
    }

    private func toggleRecording() {
        switch state {
        case .idle: startRecording()
        case .recording: finishRecording()
        case .processing: break
        }
    }

    // MARK: - 録音と文字起こし

    private func startRecording() {
        guard case .idle = state else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            show(result: nil, detail: "マイクの許可が必要（システム設定 › プライバシーとセキュリティ › マイク）")
            return
        }
        do {
            try recorder.start()
            state = .recording
            NSSound(named: "Tink")?.play()
        } catch {
            show(result: nil, detail: "録音を始められなかった: \(error.localizedDescription)")
        }
        updateIcon()
    }

    private func finishRecording() {
        let samples = recorder.stop()
        NSSound(named: "Pop")?.play()
        guard samples.count >= Self.minimumSamples else {
            state = .idle
            updateIcon()
            return
        }
        state = .processing
        updateIcon()

        Task {
            do {
                try await process(samples)
            } catch {
                show(result: nil, detail: "文字にできなかった: \(error.localizedDescription)")
            }
            state = .idle
            updateIcon()
        }
    }

    private func process(_ samples: [Float]) async throws {
        let vocabulary = settings.vocabulary
        let recognizeStart = ContinuousClock.now
        let raw = try await recognizer.transcribe(samples)
        let recognizeMs = Self.milliseconds(since: recognizeStart)
        let cleaned = normalize(raw, with: vocabulary)
        guard !cleaned.isEmpty else {
            show(result: nil, detail: "聞き取れる言葉がなかった")
            return
        }

        var polished: String?
        var polishMs: Int?
        var polishNote: String?
        if settings.polishes && polisherUnavailableReason == nil {
            let polishStart = ContinuousClock.now
            do {
                polished = try await polisher.polish(cleaned, terms: vocabulary.terms)
                    .map { normalize($0, with: vocabulary) }
                if polished == nil { polishNote = "清書は翻訳や言い換えの疑いがあったので使わなかった" }
            } catch {
                polishNote = "清書できなかった: \(error.localizedDescription)"
            }
            polishMs = Self.milliseconds(since: polishStart)
        }

        let text = polished ?? cleaned
        let pasted = Paster.paste(text)
        let seconds = Double(samples.count) / SpeechRecognizer.format.sampleRate
        // メニューには、知らせることがあるときだけ一言出す
        var notes = [polishNote].compactMap { $0 }
        if !pasted { notes.append("貼り付けられなかったので、クリップボードにコピーした") }
        show(result: text, detail: notes.isEmpty ? nil : notes.joined(separator: "・"))

        record(
            samples: samples,
            entry: [
                "audioSeconds": seconds, "raw": raw, "cleaned": cleaned, "polished": polished ?? NSNull(),
                "text": text, "recognizeMs": recognizeMs, "polishMs": polishMs ?? NSNull(),
            ])
    }

    /// フィラーと空白を消し、語彙の読みを表記に置き換える。
    /// 「ネクスト JS」のような空白入りの読みも当たるよう、空白を消す前と後の両方で置き換える
    private func normalize(_ text: String, with vocabulary: Vocabulary) -> String {
        vocabulary.apply(TextCleanup.apply(vocabulary.apply(text)))
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }

    private func record(samples: [Float], entry: [String: Any]) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var entry = entry
        entry["date"] = stamp
        entry["recording"] = NSNull()
        if settings.savesRecordings {
            let dir = outputDir.appendingPathComponent("recordings")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = stamp.replacingOccurrences(of: ":", with: "-") + ".wav"
            if (try? Recorder.writeWAV(samples, to: dir.appendingPathComponent(name))) != nil {
                entry["recording"] = name
            }
        }
        guard settings.savesHistory,
            var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("history.jsonl")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    // MARK: - メニューと設定画面

    private func show(result: String?, detail: String?) {
        lastResult = result
        lastDetail = detail
        rebuildMenu()
    }

    private func updateIcon() {
        let style: StatusIcon.Style =
            switch state {
            case .idle: .idle
            case .recording: .recording
            case .processing: .processing
            }
        statusItem.button?.image = StatusIcon.image(style)
        statusItem.button?.contentTintColor = if case .recording = state { .systemRed } else { nil }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let how = settings.recordingMode == .hold ? "押している間だけ録音" : "押すたびに録音を開始・終了"
        menu.addItem(disabled: "\(settings.shortcut.displayName)：\(how)")
        if let recognizerStatus { menu.addItem(disabled: "音声認識: \(recognizerStatus)") }
        if !keyMonitor.isRunning || !Paster.canSendKeys {
            menu.addItem(
                withTitle: "キー入力と貼り付けにはアクセシビリティの許可が必要…", action: #selector(openAccessibility),
                keyEquivalent: "")
        }
        if let lastResult {
            menu.addItem(.separator())
            menu.addItem(disabled: String(lastResult.prefix(40)) + (lastResult.count > 40 ? "…" : ""))
        }
        if let lastDetail { menu.addItem(disabled: lastDetail) }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "語彙リスト"))
        for list in settings.vocabularyLists {
            let item = menu.addItem(
                withTitle: list.name, action: #selector(toggleVocabularyList(_:)), keyEquivalent: "")
            item.representedObject = list.id
            item.state = list.isEnabled ? .on : .off
        }
        menu.addItem(.separator())
        let polish = menu.addItem(
            withTitle: "Apple Intelligence で清書", action: #selector(togglePolish), keyEquivalent: "")
        polish.state = settings.polishes && polisherUnavailableReason == nil ? .on : .off
        polish.isEnabled = polisherUnavailableReason == nil

        menu.addItem(.separator())
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        if updater.isAvailable {
            menu.addItem(withTitle: "アップデートを確認…", action: #selector(checkForUpdates), keyEquivalent: "")
        }
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func toggleVocabularyList(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
            let index = settings.vocabularyLists.firstIndex(where: { $0.id == id })
        else { return }
        settings.vocabularyLists[index].isEnabled.toggle()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func togglePolish() {
        settings.polishes.toggle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings, updater: updater, polisherUnavailableReason: polisherUnavailableReason,
                captureShortcut: { [weak self] completion in self?.keyMonitor.captureShortcut(completion) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Uchikoe の設定"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 720, height: 520))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        Paster.requestAccessibility()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension NSMenu {
    fileprivate func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
