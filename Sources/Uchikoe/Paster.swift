import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 文字列をクリップボード経由で前面のアプリに貼り付け、元のクリップボードを戻す
enum Paster {
    /// クリップボード管理アプリに履歴として残さないよう頼む印（nspasteboard.org の慣習）
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static var canSendKeys: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 貼り付けまでできたら true。次のときは貼り付けず、クリップボードに残すだけにする。
    /// - アクセシビリティが未許可
    /// - パスワード欄などでセキュア入力が有効（入力が保護されている場所に勝手に入れない）
    @MainActor
    static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transient)
        pasteboard.setData(Data(), forType: concealed)
        guard canSendKeys, !IsSecureEventInputEnabled() else { return false }

        let changeCount = pasteboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        // 貼り付け先が読み終わるのを待ってから戻す。その間に別のコピーがあれば戻さない。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == changeCount else { return }
            restore(saved, to: pasteboard)
        }
        return true
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(
            items.map { data in
                let item = NSPasteboardItem()
                for (type, value) in data { item.setData(value, forType: type) }
                return item
            })
    }
}
