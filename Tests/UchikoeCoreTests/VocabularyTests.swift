import Foundation
import Testing

@testable import UchikoeCore

struct VocabularyTests {
    private func vocabulary(_ text: String, isEnabled: Bool = true) -> Vocabulary {
        Vocabulary(lists: [VocabularyList(name: "テスト", isEnabled: isEnabled, entries: Vocabulary.parse(text))])
    }

    @Test func parsesTermsAndReadings() {
        let entries = Vocabulary.parse(
            """
            # コメントは読まない
            GitHub = ギットハブ, キットハブ、Gitハブ
            Rust

            """)
        #expect(entries.map(\.term) == ["GitHub", "Rust"])
        #expect(entries[0].readingList == ["ギットハブ", "キットハブ", "Gitハブ"])
        #expect(entries[1].readingList.isEmpty)
    }

    @Test func replacesReadingsWithTerms() {
        let vocabulary = vocabulary("GitHub = ギットハブ\nuseEffect = ユーズエフェクト")
        #expect(vocabulary.apply("ユーズエフェクトをギットハブに") == "useEffectをGitHubに")
    }

    @Test func doesNotReplaceInsideLongerKatakanaWords() {
        let vocabulary = vocabulary("Linear = リニア")
        #expect(vocabulary.apply("リニアのチケット") == "Linearのチケット")
        #expect(vocabulary.apply("リニアモーターカー") == "リニアモーターカー")
    }

    @Test func doesNotReplaceInsideLongerEnglishWords() {
        let vocabulary = vocabulary("Go")
        #expect(vocabulary.apply("go で書く") == "Go で書く")
        #expect(vocabulary.apply("Google で調べる") == "Google で調べる")
    }

    @Test func normalizesLetterCase() {
        let vocabulary = vocabulary("GitHub\nTypeScript")
        #expect(vocabulary.apply("githubとtypescript") == "GitHubとTypeScript")
    }

    @Test func prefersLongerReadings() {
        let vocabulary = vocabulary("Next.js = ネクストジェーエス\nNext = ネクスト")
        #expect(vocabulary.apply("ネクストジェーエスで") == "Next.jsで")
    }

    @Test func ignoresDisabledLists() {
        let vocabulary = vocabulary("GitHub = ギットハブ", isEnabled: false)
        #expect(vocabulary.apply("ギットハブ") == "ギットハブ")
        #expect(vocabulary.terms.isEmpty)
    }

    @Test func skipsEntriesWithoutTerm() {
        let list = VocabularyList(
            name: "テスト", isEnabled: true, entries: [VocabularyEntry(term: "  ", readings: "なにか")])
        #expect(Vocabulary(lists: [list]).entries.isEmpty)
    }

    @Test func savesAndRestoresLists() throws {
        let lists = [
            VocabularyList(name: "開発", isEnabled: true, entries: Vocabulary.parse("GitHub = ギットハブ\nRust"))
        ]
        let encoded = try JSONEncoder().encode(lists)
        #expect(try JSONDecoder().decode([VocabularyList].self, from: encoded) == lists)
    }
}
