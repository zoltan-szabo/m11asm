import Foundation
import Testing
@testable import m11asmCore

@Suite struct IncludeExpansion {
    func makeTemp(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("m11asm-inc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    func assembleMain(_ dir: URL, _ main: String) throws -> [UInt8] {
        var lexer = Lexer(source: main, filename: "main.mac")
        let tokens = try IncludeExpander.expand(tokens: try lexer.tokenize(), baseDirectory: dir)
        var diag = DiagnosticEngine()
        var expander = MacroExpander()
        let expanded = expander.expand(tokens: tokens, diagnostics: &diag)
        let program = parse(tokens: expanded, origin: 0o1000, diagnostics: &diag)
        let bytes = assemble(program: program, diagnostics: &diag)
        #expect(!diag.hasErrors, "diagnostics: \(diag.diagnostics)")
        return bytes
    }

    @Test func includesSubroutineFile() throws {
        let dir = try makeTemp([
            "lib.mac": "DOUBLE:\tASL\tR0\n\tRTS\tPC\n",
        ])
        let bytes = try assembleMain(dir, """
        \tJSR\tPC, DOUBLE
        \tHALT
        .INCLUDE /lib.mac/
        """)
        // JSR PC,DOUBLE(2w) HALT(1w) ASL R0(1w) RTS PC(1w) = 10 bytes
        #expect(bytes.count == 10)
    }

    @Test func nestedIncludeResolvesRelativeToIncluder() throws {
        let dir = try makeTemp([
            "a.mac": ".INCLUDE \"sub/b.mac\"\n",   // path contains / — use another delimiter
        ])
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "C = 42\n.INCLUDE /c.mac/\n".write(to: sub.appendingPathComponent("b.mac"),
                                               atomically: true, encoding: .utf8)
        try "D:\tNOP\n".write(to: sub.appendingPathComponent("c.mac"),
                              atomically: true, encoding: .utf8)
        let bytes = try assembleMain(dir, ".INCLUDE /a.mac/\n\tHALT\n")
        #expect(bytes.count == 4)   // NOP + HALT
    }

    @Test func missingFileThrows() throws {
        var lexer = Lexer(source: ".INCLUDE /nope.mac/\n", filename: "main.mac")
        let tokens = try lexer.tokenize()
        #expect(throws: IncludeError.self) {
            try IncludeExpander.expand(tokens: tokens, baseDirectory: FileManager.default.temporaryDirectory)
        }
    }

    @Test func recursionDepthLimited() throws {
        let dir = try makeTemp(["loop.mac": ".INCLUDE /loop.mac/\n"])
        var lexer = Lexer(source: ".INCLUDE /loop.mac/\n", filename: "main.mac")
        let tokens = try lexer.tokenize()
        #expect(throws: IncludeError.self) {
            try IncludeExpander.expand(tokens: tokens, baseDirectory: dir)
        }
    }
}
