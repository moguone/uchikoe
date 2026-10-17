import Testing

@testable import UchikoeCore

struct TextCleanupTests {
    @Test func removesFillersBetweenPunctuation() {
        #expect(TextCleanup.apply("えーと、あの、明日の会議なんですけど、まあ、11時からにできますか？") == "明日の会議なんですけど、11時からにできますか？")
    }

    @Test func removesFillersWithoutPunctuation() {
        // 音声認識は、フィラーのあとに読点を付けないことが多い
        #expect(
            TextCleanup.apply("あのReactのえーと有数エフェクトをえとGitHubにプッシュして。")
                == "Reactの有数エフェクトをGitHubにプッシュして。")
    }

    @Test func removesFillersBeforeEnglishAfterParticles() {
        #expect(TextCleanup.apply("ReactのuseEffectをんとGitHubにプッシュして") == "ReactのuseEffectをGitHubにプッシュして")
    }

    @Test func keepsWordEndingsBeforeEnglish() {
        #expect(TextCleanup.apply("考えとAIの提案を比べる") == "考えとAIの提案を比べる")
        #expect(TextCleanup.apply("ちゃんとAWSで動かす") == "ちゃんとAWSで動かす")
    }

    @Test func keepsWordsThatOnlyLookLikeFillers() {
        #expect(TextCleanup.apply("あの人が言ってたその件、まあいいか。") == "あの人が言ってたその件、まあいいか。")
    }

    @Test func removesSpacesBetweenJapaneseAndEnglish() {
        #expect(TextCleanup.apply("V2の Reactjsを GitHubにプッシュして。") == "V2のReactjsをGitHubにプッシュして。")
    }

    @Test func removesSpacesBeforePunctuation() {
        #expect(TextCleanup.apply("動くか見てもらえますか ？") == "動くか見てもらえますか？")
    }

    @Test func keepsSpacesBetweenEnglishWords() {
        #expect(TextCleanup.apply("VS Code で開く") == "VS Codeで開く")
    }
}
