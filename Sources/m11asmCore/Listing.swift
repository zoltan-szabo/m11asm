// Listing.swift — MACRO-11 assembly listing (.LST) and symbol output
//
// The line-printer listing format follows the PDP-11 MACRO-11 Language
// Reference Manual (AA-KX10A-TC), Figure 6-1:
//
//   line#  address  word [word [word]]   source text
//
// Line numbers are decimal and count source lines as assembled. The
// address is the 6-digit octal location counter. Generated code follows
// as 6-digit octal words, or 3-digit octal bytes for .BYTE/.ASCII data
// (Figure 6-1 lists byte data as bytes). Statements generating more than
// three values continue on following lines, with the line-number and
// address columns blank. Source lines that generate no code — comments,
// equates, .END — show no address.
//
// Section 6.1 specifies the page header: title, assembler version, day of
// week, date, time of day, and page number; the second line carries the
// subtitle. m11asm has no .TITLE/.SBTTL yet, so the input file name is
// used as the title.
//
// MACRO-11 has no separate symbol file: the symbol table is a section at
// the end of the listing. (A standalone .STB comes from the RSX Task
// Builder, and .MAP from the linker — neither applies to an absolute
// assembler.) `symbolFileText` is therefore an m11asm extension, a simple
// machine-readable table for tools such as the J11Terminal disassembler.

import Foundation

public enum Listing {

    public static let linesPerPage = 58

    /// Render a complete assembly listing.
    ///
    /// - Parameters:
    ///   - mainFile: name of the top-level source, as it appears in `SourceLocation.file`
    ///   - sources: file name → full text, including every `.INCLUDE`d file
    ///   - timestamp: header date/time; pass a fixed date for reproducible output
    ///   - paginated: DEC line-printer pagination (form-feed page breaks and a
    ///     per-page header). When false, one header and a continuous body — no
    ///     form feeds — for reading on a screen rather than a printer.
    public static func text(mainFile: String,
                            sources: [String: String],
                            program: ParsedProgram,
                            emitted: [EmittedItem],
                            errorCount: Int,
                            version: String,
                            timestamp: Date = Date(),
                            paginated: Bool = true) -> String {
        // Items keyed by source position; macro expansions and .REPT can put
        // several items on one line, so keep them queued in order.
        var byLine: [String: [EmittedItem]] = [:]
        for item in emitted {
            byLine[key(item.location), default: []].append(item)
        }

        var body: [String] = []
        var lineNo = 0
        for (file, line, text) in flatten(mainFile: mainFile, sources: sources) {
            lineNo += 1
            let items = byLine["\(file):\(line)"] ?? []
            body.append(contentsOf: render(lineNo: lineNo, source: text, items: items))
        }

        var out = paginate(body, title: mainFile, version: version,
                           timestamp: timestamp, paginated: paginated)
        out += "\n" + symbolTableSection(program.symbols)
        out += "\nERRORS DETECTED: \(errorCount)\n"
        return out
    }

    /// m11asm extension: machine-readable symbol table.
    public static func symbolFileText(_ symbols: SymbolTable, source: String) -> String {
        var out = "; m11asm symbol file — \(source)\n"
        out += "; name value(octal) type\n"
        for (name, value, kind) in symbols.definedWithKind {
            let type = kind == .directAssign ? "equate" : "label"
            out += "\(name) \(String(format: "%06o", value)) \(type)\n"
        }
        return out
    }

    // MARK: - Source assembly order

    private static func key(_ loc: SourceLocation) -> String { "\(loc.file):\(loc.line)" }

    /// Reproduce the order in which lines were assembled: `.INCLUDE` splices
    /// the named file's lines in place, exactly as the token expander did.
    static func flatten(mainFile: String, sources: [String: String],
                        depth: Int = 0) -> [(file: String, line: Int, text: String)] {
        guard depth < IncludeExpander.maxDepth, let text = sources[mainFile] else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }   // trailing newline is not a line
        var out: [(String, Int, String)] = []
        for (i, raw) in lines.enumerated() {
            let line = i + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces).uppercased()
            out.append((mainFile, line, raw))
            guard trimmed.hasPrefix(".INCLUDE") else { continue }
            let rest = raw.trimmingCharacters(in: .whitespaces).dropFirst(".INCLUDE".count)
                          .trimmingCharacters(in: .whitespaces)
            guard let delim = rest.first else { continue }
            let inner = rest.dropFirst()
            guard let end = inner.firstIndex(of: delim) else { continue }
            let name = String(inner[..<end])
            out.append(contentsOf: flatten(mainFile: name, sources: sources, depth: depth + 1))
        }
        return out
    }

    // MARK: - Line rendering

    private static let blankLineNo = String(repeating: " ", count: 6)
    private static let blankAddr   = String(repeating: " ", count: 6)

    private static func render(lineNo: Int, source: String, items: [EmittedItem]) -> [String] {
        guard let first = items.first else {
            return ["\(pad(lineNo))\(blankAddr)\(String(repeating: " ", count: 24))\(source)"]
        }
        var values: [String] = []
        var byteData = false
        for item in items {
            byteData = byteData || item.isByteData
            if item.isByteData {
                values += item.bytes.map { String(format: "%03o", $0) }
            } else {
                for i in stride(from: 0, to: item.bytes.count - 1, by: 2) {
                    let w = UInt16(item.bytes[i]) | UInt16(item.bytes[i + 1]) << 8
                    values.append(String(format: "%06o", w))
                }
            }
        }
        let width = byteData ? 3 : 6
        let perLine = 3
        var lines: [String] = []
        var index = 0
        repeat {
            let chunk = Array(values[index ..< min(index + perLine, values.count)])
            var cols = chunk.joined(separator: "  ")
            cols = cols.padding(toLength: max(24, perLine * (width + 2)), withPad: " ", startingAt: 0)
            if index == 0 {
                lines.append("\(pad(lineNo))\(String(format: "%06o", first.address))  \(cols)\(source)")
            } else {
                lines.append("\(blankLineNo)\(blankAddr)  \(cols)")
            }
            index += perLine
        } while index < values.count
        return lines
    }

    private static func pad(_ n: Int) -> String {
        let s = String(n)
        return String(repeating: " ", count: max(1, 5 - s.count)) + s + " "
    }

    // MARK: - Pagination and header

    private static func paginate(_ body: [String], title: String,
                                 version: String, timestamp: Date,
                                 paginated: Bool = true) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE dd-MMM-yy HH:mm:ss"
        let stamp = fmt.string(from: timestamp).uppercased()

        // Continuous: a single header, then the whole body, no form feeds.
        if !paginated {
            var out = "\(title)  m11asm \(version)  \(stamp)\n\n"
            if !body.isEmpty { out += body.joined(separator: "\n") + "\n" }
            return out
        }

        var out = ""
        var page = 1
        var index = 0
        while index < body.count {
            if page > 1 { out += "\u{0C}" }   // form feed between pages
            out += "\(title)  m11asm \(version)  \(stamp)  Page \(page)\n\n"
            let end = min(index + linesPerPage, body.count)
            out += body[index ..< end].joined(separator: "\n") + "\n"
            index = end
            page += 1
        }
        return out
    }

    // MARK: - Symbol table section

    static func symbolTableSection(_ symbols: SymbolTable) -> String {
        var out = "SYMBOL TABLE\n\n"
        let entries = symbols.definedWithKind.map { (name, value, kind) -> String in
            let n = name.padding(toLength: 8, withPad: " ", startingAt: 0)
            let mark = kind == .directAssign ? "= " : "  "
            return "\(n)\(mark)\(String(format: "%06o", value))"
        }
        for row in stride(from: 0, to: entries.count, by: 3) {
            let chunk = entries[row ..< min(row + 3, entries.count)]
            out += chunk.map { $0.padding(toLength: 22, withPad: " ", startingAt: 0) }
                        .joined().trimmingCharacters(in: .whitespaces) + "\n"
        }
        if entries.isEmpty { out += "(none)\n" }
        return out
    }
}
