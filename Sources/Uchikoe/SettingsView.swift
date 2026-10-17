import ServiceManagement
import SwiftUI
import UchikoeCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let updater: AppUpdater
    let polisherUnavailableReason: String?
    /// 次に押されたキーをショートカットとして記録する。取り消されたら nil
    let captureShortcut: (@escaping (Shortcut?) -> Void) -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(
                settings: settings, updater: updater, polisherUnavailableReason: polisherUnavailableReason,
                captureShortcut: captureShortcut
            )
            .tabItem { Label("一般", systemImage: "gearshape") }
            VocabularySettingsView(settings: settings)
                .tabItem { Label("語彙", systemImage: "character.book.closed") }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let updater: AppUpdater
    let polisherUnavailableReason: String?
    let captureShortcut: (@escaping (Shortcut?) -> Void) -> Void
    @State private var isCapturing = false

    /// システム設定の「🌐 キーを押して」が「何もしない」（0）以外か。未設定のときも OS の既定の動作がある
    private static var fnKeyHasSystemAction: Bool {
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int) != 0
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版"
    }

    var body: some View {
        Form {
            Section("録音") {
                LabeledContent("キー") {
                    HStack {
                        Text(isCapturing ? "1〜2 個のキーを押してください（Esc で取り消し）" : settings.shortcut.displayName)
                            .foregroundStyle(isCapturing ? .secondary : .primary)
                        Button(isCapturing ? "記録中…" : "変更") {
                            isCapturing = true
                            captureShortcut { shortcut in
                                if let shortcut { settings.shortcut = shortcut }
                                isCapturing = false
                            }
                        }
                        .disabled(isCapturing)
                        Button("fn に戻す") { settings.shortcut = .default }
                            .disabled(isCapturing || settings.shortcut == .default)
                    }
                }
                Picker("録音のしかた", selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if settings.shortcut == .default && Self.fnKeyHasSystemAction {
                    Text("システム設定 › キーボードの「🌐 キーを押して」が「何もしない」以外になっているため、fn を押すとその動作も一緒に起きます。「何もしない」にしてください。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("起動") {
                LaunchAtLoginToggle()
            }
            Section("清書") {
                Toggle("Apple Intelligence で英単語と句読点を整える", isOn: $settings.polishes)
                    .disabled(polisherUnavailableReason != nil)
                if let polisherUnavailableReason {
                    Text("使えない: \(polisherUnavailableReason)").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("記録") {
                Toggle("文字にした結果を履歴に残す", isOn: $settings.savesHistory)
                Toggle("話した音声を残す", isOn: $settings.savesRecordings)
                LabeledContent("保存先") {
                    Button("Finder で開く") {
                        let directory = AppSettings.supportDirectory
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }
                }
                Text("どちらも Mac の中（~/Library/Application Support/Uchikoe）にだけ保存します。話した内容がそのまま残るので、既定ではオフです。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("アップデート") {
                if updater.isAvailable {
                    Toggle(
                        "アップデートを自動で確認する",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.setAutomaticallyChecksForUpdates($0) }))
                    LabeledContent("バージョン \(Self.version)") {
                        Button("今すぐ確認") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                    Text("確認のときだけ GitHub の Releases に問い合わせます。入れ替えるときは確認を求め、署名を検証します。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("このビルドは開発用なので、アップデートを確認しません。").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct VocabularySettingsView: View {
    @Bindable var settings: AppSettings
    @State private var selection: VocabularyList.ID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection) {
                    ForEach($settings.vocabularyLists) { $list in
                        HStack {
                            Toggle("", isOn: $list.isEnabled).labelsHidden()
                            TextField("名前", text: $list.name)
                        }
                        .tag(list.id)
                    }
                    .onMove { settings.vocabularyLists.move(fromOffsets: $0, toOffset: $1) }
                }
                HStack(spacing: 4) {
                    Button {
                        let list = VocabularyList(name: "新しいリスト", isEnabled: true)
                        settings.vocabularyLists.append(list)
                        selection = list.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        settings.vocabularyLists.removeAll { $0.id == selection }
                        selection = settings.vocabularyLists.first?.id
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Text("\(settings.vocabulary.entries.count) 語が有効").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            Group {
                if let index = settings.vocabularyLists.firstIndex(where: { $0.id == selection }) {
                    VocabularyEntriesView(list: $settings.vocabularyLists[index])
                } else {
                    Text("左でリストを選んでください").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear { selection = selection ?? settings.vocabularyLists.first?.id }
    }
}

/// 1 つのリストの語を、表で 1 語ずつ編集する
private struct VocabularyEntriesView: View {
    @Binding var list: VocabularyList
    @State private var selection: Set<VocabularyEntry.ID> = []
    @State private var query = ""

    private var visibleEntries: [VocabularyEntry] {
        guard !query.isEmpty else { return list.entries }
        return list.entries.filter {
            $0.term.localizedCaseInsensitiveContains(query) || $0.readings.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("検索", text: $query)
                    .textFieldStyle(.roundedBorder)
                Text("\(list.entries.count) 語").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)

            Table(of: VocabularyEntry.self, selection: $selection) {
                TableColumn("表記") { entry in
                    TextField("GitHub", text: binding(entry.id, \.term)).textFieldStyle(.plain)
                }
                .width(min: 120, ideal: 160)
                TableColumn("読み（「,」で区切る）") { entry in
                    TextField("ギットハブ, キットハブ", text: binding(entry.id, \.readings)).textFieldStyle(.plain)
                }
            } rows: {
                ForEach(visibleEntries) { TableRow($0) }
            }
            .onDeleteCommand(perform: deleteSelected)

            HStack(spacing: 4) {
                Button {
                    let entry = VocabularyEntry(term: "", readings: "")
                    list.entries.insert(entry, at: 0)
                    query = ""
                    selection = [entry.id]
                } label: {
                    Image(systemName: "plus")
                }
                Button(action: deleteSelected) { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                Spacer()
                Text("音声認識が読みのように書いたら、表記に置き換えます。読みが空なら大文字小文字の違いだけを直します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func binding(_ id: VocabularyEntry.ID, _ keyPath: WritableKeyPath<VocabularyEntry, String>) -> Binding<
        String
    > {
        Binding(
            get: { list.entries.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = list.entries.firstIndex(where: { $0.id == id }) else { return }
                list.entries[index][keyPath: keyPath] = value
            })
    }

    private func deleteSelected() {
        list.entries.removeAll { selection.contains($0.id) }
        selection = []
    }
}

/// ログイン時に起動するか。状態はアプリに保存せず、毎回システムに問い合わせる
private struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        Toggle("ログイン時に起動", isOn: Binding(get: { status == .enabled }, set: update))
        if status == .requiresApproval {
            HStack {
                Text("システム設定 › 一般 › ログイン項目で許可が必要です。").font(.callout).foregroundStyle(.secondary)
                Button("開く") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let errorMessage {
            Text(errorMessage).font(.callout).foregroundStyle(.red)
        }
    }

    private func update(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "切り替えられなかった: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}
