import Testing

@testable import UchikoeCore

/// アプリを更新したときに、同梱の語彙リストの新しい版を取り込む
struct BundledVocabularyTests {
    private func bundled(_ text: String, name: String = "開発") -> VocabularyList {
        VocabularyList(name: name, isEnabled: false, entries: Vocabulary.parse(text), bundleName: "01-\(name)")
    }

    private func readings(_ list: VocabularyList) -> [String: String] {
        Dictionary(uniqueKeysWithValues: list.entries.map { ($0.term, $0.readings) })
    }

    @Test func readsNameFromTheHeaderAndKeepsTheIdentifier() {
        let list = VocabularyList.bundled(fileName: "01-development.txt", text: "# name: 開発\n# 説明\nGitHub = ギットハブ")
        #expect(list.name == "開発")
        #expect(list.bundleName == "01-開発")
        #expect(!list.isEnabled)
        #expect(list.entries.map(\.term) == ["GitHub"])
    }

    @Test func addsNewTermsAndUpdatesUneditedReadings() {
        var saved = bundled("useEffect = ユーズエフェクト\nGitHub = ギットハブ")
        saved.isEnabled = true
        saved.name = "仕事"
        let latest = bundled("useEffect = ユーズエフェクト, 有数エフェクト\nGitHub = ギットハブ\nZod = ゾッド")
        let merged = VocabularyList.merging(saved: [saved], bundled: [latest], knownBundleNames: ["01-開発"])
        #expect(merged.count == 1)
        #expect(merged[0].isEnabled)
        #expect(merged[0].name == "仕事")
        #expect(readings(merged[0]) == ["useEffect": "ユーズエフェクト, 有数エフェクト", "GitHub": "ギットハブ", "Zod": "ゾッド"])
    }

    @Test func keepsWhatTheUserChanged() {
        var saved = bundled("useEffect = ユーズエフェクト\nGitHub = ギットハブ\nRust")
        saved.entries[0].readings = "ユースエフェクト"  // 読みを書き換えた
        saved.entries.remove(at: 1)  // GitHub を消した
        saved.entries.append(VocabularyEntry(term: "F360", readings: "エフサンロクマル"))  // 自分で足した
        let latest = bundled("useEffect = ユーズエフェクト, 有数エフェクト\nGitHub = ギットハブ, キットハブ\nRust")
        let merged = VocabularyList.merging(saved: [saved], bundled: [latest], knownBundleNames: ["01-開発"])
        #expect(readings(merged[0]) == ["useEffect": "ユースエフェクト", "Rust": "", "F360": "エフサンロクマル"])
    }

    @Test func addsNewListsButNotDeletedOnes() {
        let latest = [bundled("GitHub", name: "開発"), bundled("KPI", name: "ビジネス")]
        let merged = VocabularyList.merging(saved: [], bundled: latest, knownBundleNames: ["01-開発"])
        #expect(merged.map(\.name) == ["ビジネス"])
        #expect(!merged[0].isEnabled)
    }

    @Test func adoptsListsSavedBeforeTrackingBundles() {
        let saved = VocabularyList(name: "開発", isEnabled: true, entries: Vocabulary.parse("GitHub = ギットハブ"))
        let latest = bundled("GitHub = ギットハブ\nZod = ゾッド")
        let merged = VocabularyList.merging(saved: [saved], bundled: [latest], knownBundleNames: [])
        #expect(merged.count == 1)
        #expect(merged[0].bundleName == "01-開発")
        #expect(merged[0].entries.map(\.term) == ["GitHub", "Zod"])
    }

    @Test func leavesUserListsWithTheSameNameAlone() {
        // 同梱の「開発」を消したあとに、自分で「開発」を作った
        let mine = VocabularyList(name: "開発", isEnabled: true, entries: Vocabulary.parse("F360"))
        let merged = VocabularyList.merging(saved: [mine], bundled: [bundled("GitHub")], knownBundleNames: ["01-開発"])
        #expect(merged == [mine])
    }
}
