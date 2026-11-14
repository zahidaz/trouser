import AppKit
import Testing
@testable import Trouser

struct KeyMapTests {
    @Test func parsesNamedKeys() throws {
        let enter = try KeyCombo(parsing: "Enter")
        #expect(enter.keyCode == 36)
        #expect(enter.modifiers.isEmpty)
        #expect(try KeyCombo(parsing: "tab").keyCode == 48)
    }

    @Test func parsesModifierCombos() throws {
        let selectAll = try KeyCombo(parsing: "cmd+a")
        #expect(selectAll.keyCode == 0)
        #expect(selectAll.modifiers == .command)
        #expect(try KeyCombo(parsing: "cmd+shift+z").modifiers == [.command, .shift])
    }

    @Test func rejectsUnknownKeys() {
        #expect(throws: CommandError.self) { try KeyCombo(parsing: "hyper+a") }
        #expect(throws: CommandError.self) { try KeyCombo(parsing: "cmd+") }
        #expect(throws: CommandError.self) { try KeyCombo(parsing: "f13") }
    }

    @Test func mapsEditingShortcutsToPageCommands() {
        #expect(KeyMap.editingCommand(characters: "a", modifiers: .command) == #selector(NSText.selectAll(_:)))
        #expect(KeyMap.editingCommand(characters: "z", modifiers: [.command, .shift]) == Selector(("redo:")))
        #expect(KeyMap.editingCommand(characters: "a", modifiers: []) == nil)
        #expect(KeyMap.editingCommand(characters: "\u{8}", modifiers: [.command, .shift]) == nil)
    }

    @Test func mapsTypedCharacters() {
        #expect(KeyMap.code(for: "A") == 0)
        #expect(KeyMap.code(for: "1") == 18)
        #expect(KeyMap.code(for: "é") == 0)
    }
}
