// Output.swift — binary and octal load file writers

import Foundation

/// Write assembled bytes as a flat binary file at the given path.
public func writeBinary(bytes: [UInt8], to path: String) throws {
    try Data(bytes).write(to: URL(fileURLWithPath: path))
}

/// Return an octal load string in self-contained `@address / word-per-line` format.
///
/// Format:
/// ```
/// @001000
/// 012700
/// 000377
/// 000240
/// ```
/// The `@address` line sets the load origin; subsequent lines are 16-bit data
/// words in little-endian memory order, one per line, in 6-digit octal.
public func octalLoadString(bytes: [UInt8], origin: UInt16) -> String {
    var lines: [String] = [String(format: "@%06o", origin)]
    var i = 0
    while i < bytes.count {
        let lo = UInt16(bytes[i])
        let hi = i + 1 < bytes.count ? UInt16(bytes[i + 1]) : 0
        lines.append(String(format: "%06o", lo | (hi << 8)))
        i += 2
    }
    return lines.joined(separator: "\n") + "\n"
}

/// Write an octal load file to disk.
public func writeOctalLoad(bytes: [UInt8], origin: UInt16, to path: String) throws {
    try octalLoadString(bytes: bytes, origin: origin).write(toFile: path, atomically: true, encoding: .ascii)
}
