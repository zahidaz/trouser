enum RunScript {
    static let separator = ";"

    static func steps(_ arguments: [String]) -> [[String]] {
        arguments.split(separator: separator, omittingEmptySubsequences: true).map(Array.init)
    }

    static func expandingStandardInput(_ arguments: [String], readLine: () -> String?) throws -> [String] {
        let start = arguments.first == "-p" || arguments.first == "--profile" ? 2 : 0
        guard arguments.count == start + 2, arguments[start] == "run", arguments[start + 1] == "-" else { return arguments }
        var lines: [[String]] = []
        while let line = readLine() {
            let words = try tokenize(line)
            if !words.isEmpty, !words[0].hasPrefix("#") {
                lines.append(words)
            }
        }
        return Array(arguments[..<(start + 1)]) + lines.joined(separator: [separator])
    }

    static func tokenize(_ line: String) throws -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                word.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
                inWord = true
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    word.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord {
                    words.append(word)
                }
                word = ""
                inWord = false
            } else {
                word.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaped else { throw CommandError.invalid("unterminated quote in “\(line)”") }
        if inWord {
            words.append(word)
        }
        return words
    }
}
