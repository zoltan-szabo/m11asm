import Foundation
import Testing
@testable import m11asmCore

// The listing format follows the PDP-11 MACRO-11 Language Reference Manual
// (AA-KX10A-TC) Figure 6-1: line number, 6-digit octal address, generated
// words (or 3-digit bytes for byte data), then the source line.

private func build(_ source: String, file: String = "t.mac", origin: UInt16 = 0o1000)
    -> (ParsedProgram, [EmittedItem], DiagnosticEngine) {
    var lexer = Lexer(source: source, filename: file)
    let tokens = try! lexer.tokenize()
    var diag = DiagnosticEngine()
    var expander = MacroExpander()
    let expanded = expander.expand(tokens: tokens, diagnostics: &diag)
    let program = parse(tokens: expanded, origin: origin, diagnostics: &diag)
    let (_, items) = assembleWithItems(program: program, diagnostics: &diag)
    return (program, items, diag)
}

@Suite struct ListingFormat {
    let source = """
    TEN\t= ^D10
    ; comment
    START:\tMOV\t#TEN, R0
    \tHALT
    TBL:\t.WORD\t1, 2, 3, 4
    MSG:\t.ASCIZ\t/Hi/
    """

    func listing() -> String {
        let (program, items, diag) = build(source)
        return Listing.text(mainFile: "t.mac", sources: ["t.mac": source],
                            program: program, emitted: items,
                            errorCount: diag.errorCount, version: "test",
                            timestamp: Date(timeIntervalSince1970: 0))
    }

    @Test func codeLineHasNumberAddressAndWords() throws {
        let lines = listing().components(separatedBy: "\n")
        let start = try #require(lines.first { $0.contains("START:") })
        // "    3 001000  012700  000012  ..."
        #expect(start.hasPrefix("    3 001000  012700  000012"))
    }

    @Test func nonCodeLinesHaveNoAddress() throws {
        let lines = listing().components(separatedBy: "\n")
        let comment = try #require(lines.first { $0.contains("; comment") })
        #expect(comment.hasPrefix("    2 "))
        #expect(!comment.contains("001000"))
    }

    @Test func extraWordsContinueOnNextLine() throws {
        // .WORD 1,2,3,4 — three words on the source line, the fourth below.
        let lines = listing().components(separatedBy: "\n")
        let idx = try #require(lines.firstIndex { $0.contains("TBL:") })
        #expect(lines[idx].contains("000001  000002  000003"))
        #expect(lines[idx + 1].trimmingCharacters(in: .whitespaces) == "000004")
    }

    @Test func byteDataListsAsThreeDigitOctal() throws {
        let lines = listing().components(separatedBy: "\n")
        let msg = try #require(lines.first { $0.contains("MSG:") })
        #expect(msg.contains("110  151  000"))     // 'H' 'i' NUL
    }

    @Test func headerCarriesTitleVersionAndPage() {
        let head = listing().components(separatedBy: "\n")[0]
        #expect(head.hasPrefix("t.mac  m11asm test  "))
        #expect(head.hasSuffix("Page 1"))
    }

    @Test func symbolTableMarksDirectAssignments() {
        let text = listing()
        #expect(text.contains("SYMBOL TABLE"))
        #expect(text.contains("TEN     = 000012"))   // '=' for `sym = expr`
        #expect(text.contains("START     001000"))   // labels have no '='
        #expect(text.contains("ERRORS DETECTED: 0"))
    }
}

@Suite struct SymbolFileOutput {
    @Test func listsNameValueAndType() {
        let src = "TEN\t= ^D10\nSTART:\tHALT\n"
        let (program, _, _) = build(src)
        let text = Listing.symbolFileText(program.symbols, source: "t.mac")
        #expect(text.contains("START 001000 label"))
        #expect(text.contains("TEN 000012 equate"))
    }
}

@Suite struct ListingIncludeOrder {
    @Test func includedLinesAppearAfterTheIncludeLine() {
        let main = "\tHALT\n.INCLUDE /lib.mac/\n"
        let lib  = "SUB:\tRTS\tPC\n"
        let rows = Listing.flatten(mainFile: "m.mac",
                                   sources: ["m.mac": main, "lib.mac": lib])
        #expect(rows.map(\.file) == ["m.mac", "m.mac", "lib.mac"])
        #expect(rows[2].text.contains("SUB:"))
    }

    @Test func missingIncludeIsSkippedNotFatal() {
        let rows = Listing.flatten(mainFile: "m.mac",
                                   sources: ["m.mac": ".INCLUDE /gone.mac/\n"])
        #expect(rows.count == 1)
    }
}
