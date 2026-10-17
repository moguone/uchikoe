import Carbon.HIToolbox
import CoreGraphics

/// 録音の始め方
public enum RecordingMode: String, CaseIterable, Sendable {
    /// 押している間だけ録音する
    case hold
    /// 押すたびに録音を始める・止める
    case toggle

    public var displayName: String {
        switch self {
        case .hold: "押している間だけ録音"
        case .toggle: "押すたびに録音を開始・終了"
        }
    }
}

/// 録音を始めるキー。1 つか 2 つの物理キーの組み合わせ。
/// 修飾キー 1 つだけ（右⌥など）のときは左右を区別し、2 キーの組み合わせでは区別しない。
public struct Shortcut: Codable, Equatable, Sendable {
    public var keys: [UInt16]

    public init(keys: [UInt16]) {
        self.keys = keys
    }

    public static let `default` = Shortcut(keys: [UInt16(kVK_Function)])

    /// 修飾キーだけでできているか（fn、右⌥、⌃⌥ など）
    public var isModifierOnly: Bool { keys.allSatisfy(Self.isModifier) }

    /// 修飾キーの keyCode と、flagsChanged で押されているかを判定するデバイス別のフラグ
    public static let modifierFlags: [UInt16: UInt64] = [
        UInt16(kVK_Command): 0x08, UInt16(kVK_RightCommand): 0x10,
        UInt16(kVK_Shift): 0x02, UInt16(kVK_RightShift): 0x04,
        UInt16(kVK_Option): 0x20, UInt16(kVK_RightOption): 0x40,
        UInt16(kVK_Control): 0x01, UInt16(kVK_RightControl): 0x2000,
        UInt16(kVK_Function): CGEventFlags.maskSecondaryFn.rawValue,
    ]

    public static func isModifier(_ key: UInt16) -> Bool { modifierFlags[key] != nil }

    /// 左右の修飾キーを左側の keyCode にまとめる
    public static func family(_ key: UInt16) -> UInt16 {
        switch Int(key) {
        case kVK_RightCommand: UInt16(kVK_Command)
        case kVK_RightShift: UInt16(kVK_Shift)
        case kVK_RightOption: UInt16(kVK_Option)
        case kVK_RightControl: UInt16(kVK_Control)
        default: key
        }
    }

    private func normalized(_ keys: some Sequence<UInt16>) -> Set<UInt16> {
        self.keys.count == 1 ? Set(keys) : Set(keys.map(Self.family))
    }

    public func contains(_ key: UInt16) -> Bool {
        normalized(keys).contains(normalized([key]).first!)
    }

    /// 押されているキーがちょうどこの組み合わせか
    public func isSatisfied(by held: Set<UInt16>) -> Bool {
        held.count == keys.count && normalized(held) == normalized(keys)
    }

    public var displayName: String {
        if keys.count == 1 { return Self.name(of: keys[0], sided: true) }
        let ordered = keys.sorted { Self.isModifier($0) && !Self.isModifier($1) }
        return ordered.map { Self.name(of: $0, sided: false) }.joined(separator: " ")
    }

    public static func name(of key: UInt16, sided: Bool) -> String {
        let left = sided ? "左" : ""
        let right = sided ? "右" : ""
        switch Int(key) {
        case kVK_Command: return left + "⌘"
        case kVK_RightCommand: return right + "⌘"
        case kVK_Shift: return left + "⇧"
        case kVK_RightShift: return right + "⇧"
        case kVK_Option: return left + "⌥"
        case kVK_RightOption: return right + "⌥"
        case kVK_Control: return left + "⌃"
        case kVK_RightControl: return right + "⌃"
        case kVK_Function: return "fn"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "Esc"
        case kVK_JIS_Eisu: return "英数"
        case kVK_JIS_Kana: return "かな"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PageUp"
        case kVK_PageDown: return "PageDown"
        default:
            if let index = functionKeys.firstIndex(of: Int(key)) { return "F\(index + 1)" }
            return character(of: key) ?? "キー\(key)"
        }
    }

    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// 今のキーボード配列で、そのキーが打つ文字
    private static func character(of key: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, key, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count,
                &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
