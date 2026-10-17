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

    public init(name: String, isEnabled: Bool, entries: [VocabularyEntry] = []) {
        self.name = name
        self.isEnabled = isEnabled
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, entries, text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // 以前の形式（テキストで書いたリスト）も読む
        entries =
            try container.decodeIfPresent([VocabularyEntry].self, forKey: .entries)
            ?? Vocabulary.parse(container.decode(String.self, forKey: .text))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(entries, forKey: .entries)
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
