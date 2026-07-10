// IncludeExpander.swift — .INCLUDE /file/ source inclusion
//
// Runs on the token stream between the lexer and the macro expander.
// Each .INCLUDE directive is replaced by the tokens of the named file
// (lexed with its own filename, so diagnostics point at the right
// source). Paths are resolved relative to the including file; includes
// nest up to a fixed depth.

import Foundation

public struct IncludeError: Error, CustomStringConvertible {
    public let description: String
    init(_ s: String) { description = s }
}

public enum IncludeExpander {
    public static let maxDepth = 16

    public static func expand(tokens: [Located<Token>],
                              baseDirectory: URL?,
                              depth: Int = 0) throws -> [Located<Token>] {
        guard depth < maxDepth else {
            throw IncludeError(".INCLUDE nesting exceeds \(maxDepth) levels")
        }
        var out: [Located<Token>] = []
        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if case .symbol(".INCLUDE") = tok.value {
                guard i + 1 < tokens.count,
                      case .stringLiteral(let bytes) = tokens[i + 1].value else {
                    throw IncludeError("\(tok.location): .INCLUDE requires a delimited file name, e.g. .INCLUDE /dm8ba10.mac/")
                }
                let name = String(decoding: bytes, as: UTF8.self)
                let url: URL = name.hasPrefix("/")
                    ? URL(fileURLWithPath: name)
                    : (baseDirectory ?? URL(fileURLWithPath: ".")).appendingPathComponent(name)
                guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                    throw IncludeError("\(tok.location): cannot read included file \(url.path)")
                }
                var lexer = Lexer(source: source, filename: name)
                let inner = try lexer.tokenize()
                let expanded = try expand(tokens: inner.filter { $0.value != .eof },
                                          baseDirectory: url.deletingLastPathComponent(),
                                          depth: depth + 1)
                out.append(contentsOf: expanded)
                // ensure statement separation after the spliced file
                out.append(Located(.newline, at: tok.location))
                i += 2
                continue
            }
            out.append(tok)
            i += 1
        }
        return out
    }
}
