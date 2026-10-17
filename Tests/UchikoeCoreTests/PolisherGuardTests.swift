import Testing

@testable import UchikoeCore

/// 清書の結果を採用するかの判定。端末内のモデル自体は呼ばない
struct PolisherGuardTests {
    @Test func acceptsKatakanaRewrittenAsKnownTerms() {
        #expect(
            Polisher.looksFaithful(
                "Reactの書き方について、Slackで共有した", to: "リアクトの書き方について、スラックで共有した",
                allowedTerms: ["React", "Slack"]))
    }

    @Test func acceptsPunctuationFixes() {
        #expect(Polisher.looksFaithful("送るのに使います。", to: "送るのに使い。ます。", allowedTerms: []))
    }

    @Test func rejectsTranslation() {
        #expect(
            !Polisher.looksFaithful(
                "tomorrowのregularなんですけど", to: "明日の定例なんですけど", allowedTerms: []))
    }

    @Test func rejectsNewKatakana() {
        #expect(!Polisher.looksFaithful("カタログが出ている", to: "カタイラーが出ている", allowedTerms: []))
    }

    @Test func rejectsReplacingEnglishWordsInTheOriginal() {
        #expect(
            !Polisher.looksFaithful(
                "ReactのuseStateをGitHubに", to: "ReactのUSエフェクトをGitHubに", allowedTerms: ["useState", "useEffect"]))
    }

    @Test func rejectsUnknownEnglishWords() {
        #expect(!Polisher.looksFaithful("Reactのチケット", to: "リニアのチケット", allowedTerms: ["Linear"]))
    }
}
