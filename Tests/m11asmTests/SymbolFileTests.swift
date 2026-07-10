import Testing
@testable import m11asmCore

@Suite struct SymbolFileParsing {
    @Test func parsesNameValueKind() {
        let text = """
        ; m11asm symbol file — hello.mac
        ; name value(octal) type
        START 001000 label
        ON 000001 equate
        """
        let entries = SymbolFile.parseEntries(text)
        #expect(entries.count == 2)
        #expect(entries[0] == SymbolFile.Entry(name: "START", value: 0o1000, kind: .label))
        #expect(entries[1].kind == .directAssign)
    }

    @Test func valuesAreOctal() {
        #expect(SymbolFile.parseEntries("X 000010 label")[0].value == 8)
    }

    @Test func missingTypeDefaultsToLabel() {
        #expect(SymbolFile.parseEntries("X 000010")[0].kind == .label)
    }

    @Test func skipsCommentsAndGarbage() {
        let text = "; c\n\nBAD\nWORSE nine label\nGOOD 000004 label\n"
        let entries = SymbolFile.parseEntries(text)
        #expect(entries.map(\.name) == ["GOOD"])
    }

    @Test func labelWinsOverEquateAtSameAddress() {
        let map = SymbolFile.parse("VIAORA 174002 equate\nPORTA 174002 label\n")
        #expect(map[0o174002] == "PORTA")
    }

    @Test func tiesBreakAlphabetically() {
        let map = SymbolFile.parse("ZED 001000 label\nABLE 001000 label\n")
        #expect(map[0o1000] == "ABLE")
    }

    /// The whole point of the file: names in place of octal addresses.
    @Test func parsedSymbolsAnnotateDisassembly() {
        let sym = "VIAORA 174002 equate\nLOOP 000776 label\n"
        let symbols = SymbolFile.parse(sym)

        // MOV R0, @#174002   (010037 + extension word)
        let mov = disassemble(words: [0o010037, 0o174002], baseAddress: 0o1000, symbols: symbols)
        #expect(mov[0].operands == "R0, @#VIAORA")

        // BR .-2 from 001000 targets 000776
        let br = disassemble(words: [0o000776], baseAddress: 0o1000, symbols: symbols)
        #expect(br[0].operands == "LOOP")

        // ...and without the symbol table, plain octal
        #expect(disassemble(words: [0o000776], baseAddress: 0o1000)[0].operands == "000776")
    }

    /// The in-memory path (an assembled program) and the file path must
    /// produce the same map, including the label-beats-equate rule.
    @Test func mapFromSymbolTableMatchesParsedFile() {
        var symbols = SymbolTable()
        symbols.define("VIAORA", value: 0o174002, kind: .directAssign)
        symbols.define("PORTA",  value: 0o174002, kind: .label)
        symbols.define("START",  value: 0o1000,   kind: .label)

        let fromTable = SymbolFile.map(symbols)
        let fromFile  = SymbolFile.parse(Listing.symbolFileText(symbols, source: "t.mac"))
        #expect(fromTable == fromFile)
        #expect(fromTable[0o174002] == "PORTA")
        #expect(fromTable[0o1000] == "START")
    }

    @Test func roundTripsWithSymbolFileText() {
        var symbols = SymbolTable()
        symbols.define("START", value: 0o1000, kind: .label)
        symbols.define("ON", value: 1, kind: .directAssign)
        let text = Listing.symbolFileText(symbols, source: "t.mac")
        let entries = SymbolFile.parseEntries(text)
        #expect(entries.contains(SymbolFile.Entry(name: "START", value: 0o1000, kind: .label)))
        #expect(entries.contains(SymbolFile.Entry(name: "ON", value: 1, kind: .directAssign)))
    }
}
