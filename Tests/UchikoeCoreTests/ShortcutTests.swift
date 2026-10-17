import Carbon.HIToolbox
import Testing

@testable import UchikoeCore

struct ShortcutTests {
    private let rightOption = UInt16(kVK_RightOption)
    private let leftOption = UInt16(kVK_Option)
    private let space = UInt16(kVK_Space)
    private let function = UInt16(kVK_Function)

    @Test func defaultIsFunctionKey() {
        #expect(Shortcut.default.keys == [function])
        #expect(Shortcut.default.isModifierOnly)
        #expect(Shortcut.default.displayName == "fn")
    }

    @Test func singleModifierDistinguishesSides() {
        let shortcut = Shortcut(keys: [rightOption])
        #expect(shortcut.isSatisfied(by: [rightOption]))
        #expect(!shortcut.isSatisfied(by: [leftOption]))
        #expect(shortcut.displayName == "右⌥")
    }

    @Test func combinationIgnoresModifierSides() {
        let shortcut = Shortcut(keys: [leftOption, space])
        #expect(shortcut.isSatisfied(by: [leftOption, space]))
        #expect(shortcut.isSatisfied(by: [rightOption, space]))
        #expect(shortcut.contains(rightOption))
        #expect(!shortcut.isModifierOnly)
        #expect(shortcut.displayName == "⌥ Space")
    }

    @Test func requiresExactlyTheseKeys() {
        let shortcut = Shortcut(keys: [leftOption, space])
        #expect(!shortcut.isSatisfied(by: [space]))
        #expect(!shortcut.isSatisfied(by: [leftOption, space, UInt16(kVK_Shift)]))
    }
}
