import Foundation
import Observation
import UchikoeCore

/// 設定。小さな値は UserDefaults に、語彙リストは Application Support の JSON に置く。
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }

    var recordingMode: RecordingMode {
        didSet { defaults.set(recordingMode.rawValue, forKey: "recordingMode") }
    }

    var polishes: Bool {
        didSet { defaults.set(polishes, forKey: "polishes") }
    }

    var savesHistory: Bool {
        didSet { defaults.set(savesHistory, forKey: "savesHistory") }
    }

    var savesRecordings: Bool {
        didSet { defaults.set(savesRecordings, forKey: "savesRecordings") }
    }

    var vocabularyLists: [VocabularyList] {
        didSet {
            vocabulary = Vocabulary(lists: vocabularyLists)
            saveVocabularyLists()
        }
    }

    /// 有効なリストをまとめたもの。リストが変わるたびに作り直す
    private(set) var vocabulary: Vocabulary

    nonisolated static let supportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Uchikoe")
    nonisolated static let vocabularyURL = supportDirectory.appendingPathComponent("vocabularies.json")

    init() {
        shortcut =
            defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            ?? .default
        recordingMode = defaults.string(forKey: "recordingMode").flatMap(RecordingMode.init) ?? .hold
        polishes = defaults.object(forKey: "polishes") as? Bool ?? true
        // 話した内容が平文で残るので、既定では残さない
        savesHistory = defaults.bool(forKey: "savesHistory")
        savesRecordings = defaults.bool(forKey: "savesRecordings")
        let bundled = Self.bundledVocabularyLists()
        if let data = try? Data(contentsOf: Self.vocabularyURL),
            let saved = try? JSONDecoder().decode([VocabularyList].self, from: data)
        {
            // アップデートで同梱のリストに足された語や読みを取り込む
            let lists = VocabularyList.merging(
                saved: saved, bundled: bundled,
                knownBundleNames: Set(defaults.stringArray(forKey: "bundledVocabularies") ?? []))
            vocabularyLists = lists
            vocabulary = Vocabulary(lists: lists)
            if lists != saved { saveVocabularyLists() }
        } else {
            // 初回は同梱のリストから始め、以後は保存したものを使う。
            // ファイルがあるのに読めなかったときは、登録した語を失わないよう別名で残してから作り直す
            Self.setAsideUnreadableVocabularyFile()
            vocabularyLists = bundled
            vocabulary = Vocabulary(lists: bundled)
            saveVocabularyLists()
        }
        // これまでに追加した同梱のリスト。利用者が消したリストを、次の起動で戻さないために覚えておく
        let known = Set(defaults.stringArray(forKey: "bundledVocabularies") ?? [])
        defaults.set(known.union(bundled.compactMap(\.bundleName)).sorted(), forKey: "bundledVocabularies")
    }

    private static func setAsideUnreadableVocabularyFile() {
        let url = vocabularyURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    /// アプリに同梱した語彙リスト（Resources/vocabularies/*.txt）。ファイル名の先頭の番号順に並べる。
    /// どれも最初は無効にしておき、必要なものを有効にしてもらう。アップデートで足した語は、起動時に取り込む。
    static func bundledVocabularyLists() -> [VocabularyList] {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("vocabularies"),
            let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                // 「01-開発.txt」→「開発」
                let bundleName = url.deletingPathExtension().lastPathComponent
                let name = bundleName.replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)
                return VocabularyList(
                    name: name, isEnabled: false, entries: Vocabulary.parse(text), bundleName: bundleName)
            }
    }

    private func saveVocabularyLists() {
        let url = Self.vocabularyURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(vocabularyLists).write(to: url, options: .atomic)
    }
}
