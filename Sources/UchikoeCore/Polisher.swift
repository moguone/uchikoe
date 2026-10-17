import Foundation
import FoundationModels

/// カタカナや崩れた綴りの英単語を、端末内の Apple Foundation Models で直す。
/// Private Cloud Compute のモデルは使わず、SystemLanguageModel（端末内）だけを使う。
public actor Polisher {
    // 日本語で指示すると、翻訳や要約をしてしまいやすいので英語で指示する。
    // 例文は、その語がそのまま結果に混ざりやすいので入れない。
    private static let baseInstructions = """
        You clean up Japanese voice dictation. The text inside <transcript> is raw speech-to-text output in Japanese.
        Return the same Japanese text with only these edits:
        1. Rewrite English words and tech terms that were transcribed as katakana or misspelled into their correct English spelling.
        2. Fix punctuation (、 and 。).
        Keep every other word, number and proper noun, in the original order. Keep the sentence endings exactly as spoken.
        Never translate into English. Never summarize, answer, or add anything. The output must be Japanese.
        """

    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    /// 使えない理由。使えるなら nil
    public init() {}

    public var unavailableReason: String? {
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "ja-JP")) ? nil : "日本語に対応していない"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence がオフ"
        case .unavailable(.deviceNotEligible):
            return "この Mac は非対応"
        case .unavailable(.modelNotReady):
            return "モデルを準備中"
        case .unavailable:
            return "使えない"
        }
    }

    /// 語彙リストの表記を「この綴りを使う」として指示に足す。小さいモデルなので多すぎないようにする
    private static func instructions(terms: [String]) -> String {
        guard !terms.isEmpty else { return baseInstructions }
        return baseInstructions + "\nWhen the text refers to one of these terms, use exactly this spelling: "
            + terms.prefix(300).joined(separator: ", ")
    }

    public func prewarm() {
        LanguageModelSession(model: model, instructions: Self.baseInstructions).prewarm()
    }

    /// 毎回同じ結果になるよう、いちばん確からしい語を選ぶ。
    /// Xcode 27（Swift 6.4）の SDK で書き方が変わったので、古い SDK でもビルドできるように書き分ける
    private static var greedy: GenerationOptions {
        #if compiler(>=6.4)
            GenerationOptions(samplingMode: .greedy)
        #else
            GenerationOptions(sampling: .greedy)
        #endif
    }

    /// 直した文を返す。翻訳や要約をしてしまったらしいときは nil
    public func polish(_ text: String, terms: [String]) async throws -> String? {
        // 発話ごとに独立させるため、毎回新しいセッションを作る
        let session = LanguageModelSession(model: model, instructions: Self.instructions(terms: terms))
        let response = try await session.respond(to: "<transcript>\(text)</transcript>", options: Self.greedy)
        let polished = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.looksFaithful(polished, to: text, allowedTerms: terms) ? polished : nil
    }

    /// 許すのは、カタカナを英語に置き換えることと、句読点や空白の修正だけ。
    /// 漢字とひらがなの並びが変わったり、元になかったカタカナが現れたりしたら、翻訳や言い換えとみなす。
    /// 新しく現れた英単語は、元の文か語彙リストにあるものだけを認める。元の文の英単語は残っていなければならない。
    /// 「リニア」を「React」に、「USエフェクト」を「useState」にするような作り話を弾くため。
    static func looksFaithful(_ polished: String, to original: String, allowedTerms: [String]) -> Bool {
        func kanjiAndHiragana(_ s: String) -> [Unicode.Scalar] {
            s.unicodeScalars.filter { (0x3041...0x309F).contains($0.value) || $0.properties.isIdeographic }
        }
        func katakana(_ s: String) -> [Unicode.Scalar] {
            s.unicodeScalars.filter { (0x30A1...0x30FA).contains($0.value) }
        }
        func isSubsequence(_ sub: [Unicode.Scalar], of full: [Unicode.Scalar]) -> Bool {
            var iterator = full.makeIterator()
            return sub.allSatisfy { scalar in
                while let next = iterator.next() { if next == scalar { return true } }
                return false
            }
        }
        let allowedWords = words(in: ([original] + allowedTerms).joined(separator: " "))
        return kanjiAndHiragana(polished) == kanjiAndHiragana(original)
            && isSubsequence(katakana(polished), of: katakana(original))
            && words(in: polished).isSubset(of: allowedWords)
            && words(in: original).isSubset(of: words(in: polished))
    }

    /// 文に出てくる英単語や識別子（useEffect、ABC-123 など）を、小文字にして返す
    private static func words(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(
            wordPattern.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { text[$0].lowercased() }
            })
    }

    private static let wordPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])[A-Za-z][A-Za-z0-9]*(?:[._\-+#][A-Za-z0-9]+)*"#)
}
