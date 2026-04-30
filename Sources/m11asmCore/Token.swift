// Token.swift — token types produced by the MACRO-11 lexer

public enum Token: Sendable, Equatable {

    // MARK: - Identifiers
    // Labels, instruction mnemonics, register names, directive names.
    // Directive names carry the leading dot: e.g. ".WORD", ".BYTE".
    // All symbols are uppercased by the lexer.
    case symbol(String)

    // MARK: - Literals
    case integer(UInt16)   // numeric literal — radix decoded (default: octal)
    case asciiChar(UInt8)  // 'A  or  ^A/A/

    // MARK: - Operators and punctuation
    case colon          // :   label terminator
    case comma          // ,   operand separator
    case hash           // #   immediate prefix
    case at             // @   deferred / indirect prefix
    case plus           // +
    case minus          // -
    case star           // *   multiply
    case slash          // /   divide  (string delimiters are handled by the parser)
    case bang           // !   bitwise OR
    case ampersand      // &   bitwise AND
    case backslash      // \   macro argument substitution prefix
    case tick           // '   concatenation in macro body (char literal handled as .asciiChar)
    case lparen         // (
    case rparen         // )
    case langle         // <   macro argument bracket open
    case rangle         // >   macro argument bracket close
    case equals         // =   equate
    case doubleEquals   // ==  permanent equate
    case dot            // .   standalone location counter

    // MARK: - Structure
    case newline
    case eof
}
