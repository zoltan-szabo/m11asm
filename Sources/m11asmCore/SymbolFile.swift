// SymbolFile.swift — reader for the m11asm `.sym` symbol table
//
// Written by `m11asm --symbol-file`. One symbol per line:
//
//     ; comment
//     START 001000 label
//     ON 000001 equate
//
// Values are octal. The type column is optional and defaults to `label`.
// Consumers such as the J11Terminal disassembler use the resulting map to
// print names instead of octal addresses.

import Foundation

public enum SymbolFile {

    public struct Entry: Sendable, Equatable {
        public let name:  String
        public let value: UInt16
        public let kind:  SymbolTable.Kind
    }

    /// Parse every well-formed line; malformed lines are skipped.
    public static func parseEntries(_ text: String) -> [Entry] {
        var out: [Entry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let value = UInt16(parts[1], radix: 8) else { continue }
            let kind: SymbolTable.Kind =
                parts.count >= 3 && parts[2].lowercased() == "equate" ? .directAssign : .label
            out.append(Entry(name: String(parts[0]), value: value, kind: kind))
        }
        return out
    }

    /// Address → name, for `disassemble(symbols:)`.
    ///
    /// Several symbols can share a value (a label and an equate, say). Labels
    /// win, because they name code and data the disassembler is walking;
    /// ties break alphabetically so the result is deterministic.
    public static func parse(_ text: String) -> [UInt32: String] {
        var best: [UInt32: Entry] = [:]
        for entry in parseEntries(text) {
            let key = UInt32(entry.value)
            guard let current = best[key] else { best[key] = entry; continue }
            if preferred(entry, over: current) { best[key] = entry }
        }
        return best.mapValues(\.name)
    }

    private static func preferred(_ a: Entry, over b: Entry) -> Bool {
        if a.kind != b.kind { return a.kind == .label }
        return a.name < b.name
    }
}
