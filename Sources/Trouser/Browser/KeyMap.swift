import AppKit

struct KeyCombo: Equatable {
    let name: String
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16
    let characters: String

    init(parsing text: String) throws {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.last, let key = KeyMap.key(named: keyName) else {
            throw CommandError.invalid("unknown key “\(text)”")
        }
        var modifiers = NSEvent.ModifierFlags()
        for name in parts.dropLast() {
            guard let flag = KeyMap.modifiers[name] else { throw CommandError.invalid("unknown modifier “\(name)”") }
            modifiers.insert(flag)
        }
        self.name = text.lowercased()
        self.modifiers = modifiers
        self.keyCode = key.code
        self.characters = key.characters
    }
}

enum KeyMap {
    typealias Key = (code: UInt16, characters: String)

    static let enter: Key = (36, "\r")

    static let modifiers: [String: NSEvent.ModifierFlags] = [
        "cmd": .command, "command": .command,
        "shift": .shift,
        "alt": .option, "option": .option,
        "ctrl": .control, "control": .control
    ]

    static func key(named name: String) -> Key? {
        if let key = named[name] { return key }
        guard name.count == 1, let character = name.first, let code = characterCodes[character] else { return nil }
        return (code, name)
    }

    static func editingCommand(characters: String, modifiers: NSEvent.ModifierFlags) -> Selector? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        switch (characters, flags) {
        case ("a", [.command]): return #selector(NSText.selectAll(_:))
        case ("c", [.command]): return #selector(NSText.copy(_:))
        case ("v", [.command]): return #selector(NSText.paste(_:))
        case ("x", [.command]): return #selector(NSText.cut(_:))
        case ("z", [.command]): return Selector(("undo:"))
        case ("z", [.command, .shift]): return Selector(("redo:"))
        default: return nil
        }
    }

    static func code(for character: Character) -> UInt16 {
        characterCodes[Character(character.lowercased())] ?? 0
    }

    private static let named: [String: Key] = [
        "enter": enter, "return": enter,
        "tab": (48, "\t"),
        "space": (49, " "),
        "escape": (53, "\u{1b}"), "esc": (53, "\u{1b}"),
        "backspace": (51, "\u{7f}"),
        "delete": (117, "\u{f728}"),
        "up": (126, "\u{f700}"),
        "down": (125, "\u{f701}"),
        "left": (123, "\u{f702}"),
        "right": (124, "\u{f703}"),
        "home": (115, "\u{f729}"),
        "end": (119, "\u{f72b}"),
        "pageup": (116, "\u{f72c}"),
        "pagedown": (121, "\u{f72d}"),
        "plus": (24, "+")
    ]

    private static let characterCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50, " ": 49
    ]
}
