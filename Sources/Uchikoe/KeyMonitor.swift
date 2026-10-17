import AppKit
import Carbon.HIToolbox
import CoreGraphics
import UchikoeCore

/// キー入力をイベントタップで見張り、ショートカットの押下・解放と、ショートカットの記録を扱う。
/// 修飾キーだけのショートカット（右⌥など）も扱える。アクセシビリティの許可が必要。
@MainActor
final class KeyMonitor {
    var shortcut: Shortcut
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// 押している間に別のキーが押された（右⌥ で特殊文字を打つときなど）
    var onInterrupt: () -> Void = {}

    private var tap: CFMachPort?
    private var held: Set<UInt16> = []
    private var isActive = false
    /// 飲み込んだ keyDown。対応する keyUp も飲み込む
    private var swallowed: Set<UInt16> = []
    private var capture: (keys: [UInt16], completion: (Shortcut?) -> Void)?

    var isRunning: Bool { tap != nil }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    /// タップを作る。アクセシビリティが未許可なら false
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
                    let pass = MainActor.assumeIsolated { monitor.handle(type, event) }
                    return pass ? Unmanaged.passUnretained(event) : nil
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 次に押された 1〜2 キーを記録する。Esc だけを押すと取り消し（nil）
    func captureShortcut(_ completion: @escaping (Shortcut?) -> Void) {
        capture = ([], completion)
    }

    func cancelCapture() {
        capture?.completion(nil)
        capture = nil
    }

    /// イベントを通すなら true
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        // ほかのアプリが送ったキーは見ない。BetterTouchTool は ⌥⌘← などを送るときに fn の押下も添え、
        // ⌥⌘ には左右のフラグを付けないため、fn だけが押されたように見えてしまう。
        // キーボードからの入力は、Karabiner-Elements を通したものも含めて送り元が 0 になる。
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return true }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        var pressed: Bool
        switch type {
        case .keyDown: pressed = true
        case .keyUp: pressed = false
        case .flagsChanged:
            guard let flag = Shortcut.modifierFlags[key] else { return true }
            pressed = event.flags.rawValue & flag != 0
        default: return true
        }
        let wasHeld = held.contains(key)
        if pressed { held.insert(key) } else { held.remove(key) }

        if capture != nil { return handleCapture(type: type, key: key, pressed: pressed) }

        if type == .keyUp, swallowed.remove(key) != nil {
            if isActive && shortcut.contains(key) { release() }
            return false
        }
        if isActive {
            if !pressed && shortcut.contains(key) {
                release()
            } else if pressed && !wasHeld && !shortcut.contains(key) {
                isActive = false
                onInterrupt()
            } else if type == .keyDown && shortcut.contains(key) {
                swallowed.insert(key)  // キーリピート
                return false
            }
            return true
        }
        if pressed && !isRepeat && shortcut.isSatisfied(by: held) {
            isActive = true
            onPress()
            if type == .keyDown {
                swallowed.insert(key)
                return false
            }
        }
        return true
    }

    private func release() {
        isActive = false
        onRelease()
    }

    private func handleCapture(type: CGEventType, key: UInt16, pressed: Bool) -> Bool {
        guard var current = capture else { return true }
        if pressed && type != .keyUp {
            if current.keys.isEmpty && key == UInt16(kVK_Escape) {
                swallowed.insert(key)
                capture = nil
                current.completion(nil)
                return false
            }
            if !current.keys.contains(key) && current.keys.count < 2 { current.keys.append(key) }
            capture = current
        }
        if held.isEmpty && !current.keys.isEmpty {
            capture = nil
            current.completion(Shortcut(keys: current.keys))
        }
        if type == .keyDown { swallowed.insert(key) }
        if type == .keyUp { swallowed.remove(key) }
        return type == .flagsChanged
    }
}
