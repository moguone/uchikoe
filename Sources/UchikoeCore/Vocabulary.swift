import Foundation

/// 語彙の 1 語。音声認識が読みのように書いたら、表記に置き換える
public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var term: String
    /// 読み。「,」か「、」で区切る。空なら大文字小文字の違いだけを直す
    public var readings: String

    public init(id: UUID = UUID(), term: String, readings: String) {
        self.id = id
        self.term = term
        self.readings = readings
    }

    public var readingList: [String] {
        readings.split(whereSeparator: { $0 == "," || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

public struct VocabularyList: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var isEnabled: Bool
    public var entries: [VocabularyEntry]
    /// アプリに同梱したリストから作ったときの、元のファイル名（例: 01-開発）。利用者が作ったリストは nil
    public var bundleName: String?
    /// 前回取り込んだときの、同梱のリストの内容（表記 → 読み）。アップデートで足された語や読みを見分けるのに使う
    public var bundledEntries: [String: String]?

    public init(name: String, isEnabled: Bool, entries: [VocabularyEntry] = [], bundleName: String? = nil) {
        self.name = name
        self.isEnabled = isEnabled
        self.entries = entries
        self.bundleName = bundleName
        if bundleName != nil { bundledEntries = Self.snapshot(of: entries) }
    }

    /// 保存していたリストに、アプリに同梱したリストの新しい版を取り込む。
    /// - 同梱のリストに新しく足された語は追加する。前回の版にあって今はない語は、利用者が消したとみなして戻さない
    /// - 読みが前回の版のままなら新しい読みにする。利用者が書き換えた読みは残す
    /// - 名前、オン・オフ、利用者が足した語はそのまま
    /// - knownBundleNames にない同梱のリストは追加する（無効の状態で）。ある同梱のリストが保存したものにないなら、利用者が消したとみなす
    public static func merging(
        saved: [VocabularyList], bundled: [VocabularyList], knownBundleNames: Set<String>
    ) -> [VocabularyList] {
        var lists = saved
        for latest in bundled {
            guard let bundleName = latest.bundleName else { continue }
            var index = lists.firstIndex { $0.bundleName == bundleName }
            if index == nil && knownBundleNames.isEmpty {
                // 元のファイル名を記録する前に保存したリストは、名前で対応づける
                index = lists.firstIndex { $0.bundleName == nil && $0.bundledEntries == nil && $0.name == latest.name }
            }
            if let index {
                lists[index].bundleName = bundleName
                lists[index].mergeBundled(latest.entries)
            } else if !knownBundleNames.contains(bundleName) {
                lists.append(latest)
            }
        }
        return lists
    }

    private mutating func mergeBundled(_ latest: [VocabularyEntry]) {
        let previous = bundledEntries ?? [:]
        for entry in latest {
            if let index = entries.firstIndex(where: { $0.term == entry.term }) {
                if previous[entry.term] == entries[index].readings {
                    entries[index].readings = entry.readings
                }
            } else if previous[entry.term] == nil {
                entries.append(VocabularyEntry(term: entry.term, readings: entry.readings))
            }
        }
        bundledEntries = Self.snapshot(of: latest)
    }

    private static func snapshot(of entries: [VocabularyEntry]) -> [String: String] {
        Dictionary(entries.map { ($0.term, $0.readings) }, uniquingKeysWith: { first, _ in first })
    }
}

/// 有効な語彙リストをまとめたもの
public struct Vocabulary: Sendable {
    public let entries: [VocabularyEntry]
    private let replacements: [(NSRegularExpression, String)]

    public var terms: [String] { entries.map(\.term) }

    public init(lists: [VocabularyList]) {
        entries = lists.filter(\.isEnabled).flatMap(\.entries)
            .map {
                VocabularyEntry(id: $0.id, term: $0.term.trimmingCharacters(in: .whitespaces), readings: $0.readings)
            }
            .filter { !$0.term.isEmpty }

        var pairs: [(alias: String, term: String)] = []
        for entry in entries {
            for alias in entry.readingList { pairs.append((alias, entry.term)) }
            // 「Github」「typescript」のような大文字小文字の違いも直す
            if entry.term.allSatisfy(\.isASCII) { pairs.append((entry.term, entry.term)) }
        }
        // 長い読みから先に置き換える（「ネクストジェーエス」を「ネクスト」より先に）
        replacements = pairs.sorted { $0.alias.count > $1.alias.count }.compactMap { pair in
            Self.regex(for: pair.alias).map { ($0, NSRegularExpression.escapedTemplate(for: pair.term)) }
        }
    }

    public func apply(_ text: String) -> String {
        replacements.reduce(text) { text, replacement in
            replacement.0.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement.1)
        }
    }

    /// 「表記 = 読み, 読み」を 1 行に 1 語で書いたテキストを読む。# で始まる行はコメント
    public static func parse(_ text: String) -> [VocabularyEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "=", maxSplits: 1)
            let term = parts[0].trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return nil }
            let readings = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            return VocabularyEntry(term: term, readings: readings)
        }
    }

    /// 単語の途中に当たらないよう、前後が同じ種類の文字（カタカナどうし、英数字どうし）なら置き換えない。
    /// 「リニア」で「リニアモーター」を、「Go」で「Google」を置き換えないため。
    private static func regex(for alias: String) -> NSRegularExpression? {
        func boundary(_ character: Character?) -> String? {
            guard let character else { return nil }
            if character.isASCII && (character.isLetter || character.isNumber) { return "[A-Za-z0-9]" }
            if character.unicodeScalars.allSatisfy({ (0x30A1...0x30FC).contains($0.value) }) {
                return "[\\p{Katakana}ー]"
            }
            return nil
        }
        var pattern = NSRegularExpression.escapedPattern(for: alias)
        if let before = boundary(alias.first) { pattern = "(?<!\(before))" + pattern }
        if let after = boundary(alias.last) { pattern += "(?!\(after))" }
        let options: NSRegularExpression.Options = alias.allSatisfy(\.isASCII) ? [.caseInsensitive] : []
        return try? NSRegularExpression(pattern: pattern, options: options)
    }
}
