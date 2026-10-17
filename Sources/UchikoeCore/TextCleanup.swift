import Foundation

/// 規則で確実に直せるものを直す。フィラーの除去と、日本語と英数字の間の空白の除去。
public enum TextCleanup {
    /// 読点・文頭・文末に挟まれたフィラーを消す（「あの人」の「あの」や「まあいいか」は残す）
    private static let fillers = regex(
        #"(?<=^|[、。？！\s])(えーっと|えーと|えっと|えー+|あのー*|まあ|そのー+|うーん|んー)(、|\s+|(?=[。？！]|$))"#)
    /// ほかの言葉になりようがないフィラーは、読点がなくても消す。音声認識は読点を付けないことが多い
    private static let unambiguousFillers = regex(#"(えーっと|えーと|えっと|うーん|あのー+|そのー+)(、|\s+)?"#)
    /// 「あの」「えと」は、すぐあとに英単語が続くときだけフィラーとみなす（「あのReact」「えとGitHub」）
    private static let fillersBeforeEnglish = regex(#"(あの|えと)\s*(?=[A-Za-z])"#)
    private static let spaceBetweenScripts = regex(
        #"(?<=[\p{Han}\p{Hiragana}\p{Katakana}ー、。])\s+(?=[A-Za-z0-9])|(?<=[A-Za-z0-9.])\s+(?=[\p{Han}\p{Hiragana}\p{Katakana}ー、。])"#
    )
    private static let leadingSeparators = regex(#"^[、\s]+"#)

    public static func apply(_ text: String) -> String {
        var result = text
        // 「えー、あの、」のように続くことがあるので、変わらなくなるまで繰り返す
        while true {
            let next = remove(
                fillers, from: remove(fillersBeforeEnglish, from: remove(unambiguousFillers, from: result)))
            if next == result { break }
            result = next
        }
        result = remove(spaceBetweenScripts, from: result)
        return remove(leadingSeparators, from: result)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func remove(_ regex: NSRegularExpression, from text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
