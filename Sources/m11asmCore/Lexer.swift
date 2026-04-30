// Lexer.swift — character-level scanner for MACRO-11 source

// MARK: - Character helpers

private extension Character {
    var isASCIILetter:      Bool { (self >= "a" && self <= "z") || (self >= "A" && self <= "Z") }
    var isASCIIDigit:       Bool { self >= "0" && self <= "9" }
    var isOctalDigit:       Bool { self >= "0" && self <= "7" }
    var isASCIIHexDigit:    Bool { isASCIIDigit || (self >= "a" && self <= "f") || (self >= "A" && self <= "F") }
    var isASCIIAlphanumeric:Bool { isASCIILetter || isASCIIDigit }
    var isMacroNameChar:    Bool { isASCIIAlphanumeric || self == "$" || self == "_" }
}

// MARK: - Error

public struct LexError: Error, Sendable, CustomStringConvertible {
    public let location: SourceLocation
    public let message:  String
    public var description: String { "\(location): error: \(message)" }
}

// MARK: - Lexer

public struct Lexer: Sendable {
    private let source:   [Character]
    private let filename: String
    private var pos:    Int = 0
    private var line:   Int = 1
    private var column: Int = 1

    public init(source: String, filename: String = "<input>") {
        // Swift treats \r\n as a single grapheme cluster Character, which breaks
        // per-character scanning. Normalize all line endings to \n up front.
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
        self.source   = Array(normalized)
        self.filename = filename
    }

    // Produce the complete token stream. The final token is always .eof.
    public mutating func tokenize() throws -> [Located<Token>] {
        var result: [Located<Token>] = []
        while true {
            let tok = try nextToken()
            result.append(tok)
            if tok.value == .eof { break }
        }
        return result
    }

    // Read a raw string between matching delimiters (used by the parser for .ASCII etc.)
    // `delimiter` is the character immediately following the directive keyword.
    // Advances past the closing delimiter.
    public mutating func readDelimitedString() throws -> [UInt8] {
        guard let delim = advance() else {
            throw LexError(location: currentLocation, message: "expected string delimiter")
        }
        var bytes: [UInt8] = []
        while let ch = peek() {
            if ch == delim { _ = advance(); break }
            if ch == "\n"  { throw LexError(location: currentLocation, message: "unterminated string") }
            bytes.append(advance()!.asciiValue ?? 0x3F) // '?' for non-ASCII
        }
        return bytes
    }

    // MARK: Private helpers

    private var currentLocation: SourceLocation {
        SourceLocation(file: filename, line: line, column: column)
    }

    private func peek(_ offset: Int = 0) -> Character? {
        let i = pos + offset
        return i < source.count ? source[i] : nil
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard pos < source.count else { return nil }
        let ch = source[pos]
        pos += 1
        if ch == "\n" { line += 1; column = 1 } else { column += 1 }
        return ch
    }

    // MARK: Token dispatch

    private mutating func nextToken() throws -> Located<Token> {
        // Skip spaces and tabs
        while let ch = peek(), ch == " " || ch == "\t" { advance() }

        let loc = currentLocation

        guard let ch = peek() else { return Located(.eof, at: loc) }

        // Comment — consume to end of line, then recurse
        if ch == ";" {
            while let c = peek(), c != "\n" { advance() }
            return try nextToken()
        }

        // Newline — source is pre-normalized to \n only
        if ch == "\n" {
            advance()
            return Located(.newline, at: loc)
        }

        // Directive name (.WORD, .BYTE, …) — dot immediately followed by a letter
        if ch == "." && peek(1)?.isASCIILetter == true {
            return Located(lexSymbol(), at: loc)
        }

        // Standalone dot — location counter
        if ch == "." {
            advance()
            return Located(.dot, at: loc)
        }

        // Symbol: starts with letter, $ or _
        if ch.isASCIILetter || ch == "$" || ch == "_" {
            return Located(lexSymbol(), at: loc)
        }

        // Digit → octal number or local label (n$)
        if ch.isASCIIDigit {
            return try Located(lexNumberOrLocalLabel(at: loc), at: loc)
        }

        // Caret prefix — ^D ^O ^B ^X (radix) or ^A (ASCII char)
        if ch == "^" {
            return try Located(lexCaretPrefix(at: loc), at: loc)
        }

        // Single-quote character literal: 'A → asciiChar(65)
        // Bare tick (no following char / in macro concat context) → .tick
        if ch == "'" {
            advance()
            if let next = peek(), next.isASCIIAlphanumeric || next == "." || next == "$" {
                let c = advance()!
                return Located(.asciiChar(c.asciiValue ?? 0x3F), at: loc)
            }
            return Located(.tick, at: loc)
        }

        // Double-character: ==
        if ch == "=" && peek(1) == "=" {
            advance(); advance()
            return Located(.doubleEquals, at: loc)
        }

        // Single-character punctuation
        advance()
        let tok: Token
        switch ch {
        case ":":  tok = .colon
        case ",":  tok = .comma
        case "#":  tok = .hash
        case "@":  tok = .at
        case "+":  tok = .plus
        case "-":  tok = .minus
        case "*":  tok = .star
        case "/":  tok = .slash
        case "!":  tok = .bang
        case "&":  tok = .ampersand
        case "\\":  tok = .backslash
        case "(":  tok = .lparen
        case ")":  tok = .rparen
        case "<":  tok = .langle
        case ">":  tok = .rangle
        case "=":  tok = .equals
        default:
            throw LexError(location: loc, message: "unexpected character '\(ch)'")
        }
        return Located(tok, at: loc)
    }

    // MARK: Symbol / directive name lexer

    // Called when peek() is a letter, $, _, or . (directive).
    private mutating func lexSymbol() -> Token {
        var name = ""
        // Include leading dot for directive names
        if peek() == "." { name.append("."); advance() }
        // Accumulate alphanumeric + $ + _
        while let ch = peek(), ch.isMacroNameChar { name.append(ch); advance() }
        return .symbol(name.uppercased())
    }

    // MARK: Number and local-label lexer

    // Digit sequence → octal integer, OR digit+$ → local label symbol.
    private mutating func lexNumberOrLocalLabel(at loc: SourceLocation) throws -> Token {
        var digits = ""
        while let ch = peek(), ch.isASCIIDigit { digits.append(ch); advance() }

        // Local label: digit sequence immediately followed by $
        if peek() == "$" {
            advance()
            return .symbol(digits + "$")
        }

        guard let value = UInt16(digits, radix: 8) else {
            throw LexError(location: loc, message: "octal literal out of range: \(digits) (use ^D for decimal)")
        }
        return .integer(value)
    }

    // MARK: Caret prefix — ^D ^O ^B ^X ^A

    private mutating func lexCaretPrefix(at loc: SourceLocation) throws -> Token {
        advance() // consume ^
        guard let prefix = advance() else {
            throw LexError(location: loc, message: "unexpected end of input after ^")
        }
        switch prefix.uppercased() {
        case "D": return .integer(try lexRadixDigits(radix: 10, name: "decimal",     valid: { $0.isASCIIDigit },    at: loc))
        case "O": return .integer(try lexRadixDigits(radix: 8,  name: "octal",       valid: { $0.isOctalDigit },    at: loc))
        case "B": return .integer(try lexRadixDigits(radix: 2,  name: "binary",      valid: { $0 == "0" || $0 == "1" }, at: loc))
        case "X": return .integer(try lexRadixDigits(radix: 16, name: "hexadecimal", valid: { $0.isASCIIHexDigit }, at: loc))
        case "A": return .asciiChar(try lexCaretAscii(at: loc))
        default:
            throw LexError(location: loc, message: "unknown prefix ^'\(prefix)' (expected D, O, B, X, or A)")
        }
    }

    // Read digit characters passing `valid`, interpret with `radix`.
    private mutating func lexRadixDigits(radix: Int, name: String,
                                         valid: (Character) -> Bool,
                                         at loc: SourceLocation) throws -> UInt16 {
        var digits = ""
        while let ch = peek(), valid(ch) { digits.append(ch); advance() }
        guard !digits.isEmpty, let v = UInt16(digits, radix: radix) else {
            throw LexError(location: loc, message: "invalid \(name) literal")
        }
        return v
    }

    // ^A/x/ — single ASCII char between matching delimiters
    private mutating func lexCaretAscii(at loc: SourceLocation) throws -> UInt8 {
        guard let delim = advance() else {
            throw LexError(location: loc, message: "expected delimiter after ^A")
        }
        guard let ch = advance() else {
            throw LexError(location: loc, message: "unexpected end of input inside ^A literal")
        }
        guard let ascii = ch.asciiValue else {
            throw LexError(location: loc, message: "non-ASCII character in ^A literal")
        }
        if peek() == delim { advance() } // consume optional closing delimiter
        return ascii
    }
}
