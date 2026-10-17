import Testing

@testable import UchikoeCore

struct TextCleanupTests {
    @Test func removesFillersBetweenPunctuation() {
        #expect(TextCleanup.apply("えーと、あの、明日の会議なんですけど、まあ、11時からにできますか？") == "明日の会議なんですけど、11時からにできますか？")
    }

    @Test func keepsWordsThatOnlyLookLikeFillers() {
        #expect(TextCleanup.apply("あの人が言ってたその件、まあいいか。") == "あの人が言ってたその件、まあいいか。")
    }

    @Test func removesSpacesBetweenJapaneseAndEnglish() {
        #expect(TextCleanup.apply("V2の Reactjsを GitHubにプッシュして。") == "V2のReactjsをGitHubにプッシュして。")
    }

    @Test func keepsSpacesBetweenEnglishWords() {
        #expect(TextCleanup.apply("VS Code で開く") == "VS Codeで開く")
    }
}
