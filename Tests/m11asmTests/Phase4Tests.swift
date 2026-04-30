import Testing
@testable import m11asmCore

// MARK: - Helpers

private func lex4(_ src: String) throws -> [Located<Token>] {
    var l = Lexer(source: src); return try l.tokenize()
}

private func parseSource4(_ src: String, origin: UInt16 = 0) throws -> ParsedProgram {
    let tokens = try lex4(src)
    var diag = DiagnosticEngine()
    let prog = parse(tokens: tokens, origin: origin, diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return prog
}

private func bytes(_ src: String, origin: UInt16 = 0) throws -> [UInt8] {
    let prog = try parseSource4(src, origin: origin)
    var diag = DiagnosticEngine()
    let out = assemble(program: prog, diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return out
}

private func words(_ src: String, origin: UInt16 = 0) throws -> [UInt16] {
    let b = try bytes(src, origin: origin)
    return stride(from: 0, to: b.count, by: 2).map { i in
        UInt16(b[i]) | (i + 1 < b.count ? UInt16(b[i + 1]) << 8 : 0)
    }
}

// MARK: - .WORD

@Suite(".WORD directive") struct WordTests {

    @Test func singleWord() throws {
        #expect(try words(".WORD 1\n") == [1])
    }

    @Test func multipleWords() throws {
        #expect(try words(".WORD 1, 2, 3\n") == [1, 2, 3])
    }

    @Test func octalLiteral() throws {
        // 0o177777 = 65535
        #expect(try words(".WORD 177777\n") == [0o177777])
    }

    @Test func wordExpression() throws {
        #expect(try words(".WORD 1+2\n") == [3])
    }

    @Test func wordForwardRef() throws {
        // .WORD LABEL where LABEL is defined later
        let b = try words(".WORD LABEL\nLABEL: HALT\n")
        // LABEL is at address 4 (2 bytes for .WORD + 2 bytes for HALT = LABEL at byte 2)
        // Actually: .WORD takes 2 bytes, so LABEL = 2
        #expect(b[0] == 2) // LABEL address = 2 (low byte, LE)
        #expect(b[1] == 0) // high byte
    }

    @Test func wordMixedWithInstruction() throws {
        let b = try words("NOP\n.WORD 42\n")
        // words() returns [UInt16]; NOP + .WORD 42(octal=34dec) = 2 words
        #expect(b.count == 2)
        #expect(b[0] == 0o000240)  // NOP
        #expect(b[1] == 0o42)      // 34 decimal
    }

    @Test func wordLabelAtWord() throws {
        let prog = try parseSource4("TABLE: .WORD 1, 2, 3\n")
        #expect(prog.symbols.lookup("TABLE") == .absolute(0))
    }
}

// MARK: - .BYTE

@Suite(".BYTE directive") struct ByteTests {

    @Test func singleByte() throws {
        // ^D65 = decimal 65 = ASCII 'A'
        let b = try bytes(".BYTE ^D65\n")
        #expect(b == [65])
    }

    @Test func multipleBytes() throws {
        let b = try bytes(".BYTE 1, 2, 3\n")
        #expect(b == [1, 2, 3])
    }

    @Test func byteTruncatedToEightBits() throws {
        // 0o401 = 257 → truncated to 1
        let b = try bytes(".BYTE 401\n")
        #expect(b == [1])
    }

    @Test func byteFollowedByEven() throws {
        // .BYTE 1 leaves LC at odd address; .EVEN adds one pad byte
        let b = try bytes(".BYTE 1\n.EVEN\nHALT\n")
        // byte[0] = 1, byte[1] = 0 (pad from .EVEN), bytes[2..3] = HALT
        #expect(b.count == 4)
        #expect(b[0] == 1)
        #expect(b[1] == 0)
        // HALT = 0o000000 → LE [0x00, 0x00]
        #expect(b[2] == 0 && b[3] == 0)
    }

    @Test func byteLCAdvance() throws {
        let prog = try parseSource4(".BYTE 1, 2, 3\nAFTER: HALT\n")
        // .BYTE 3 bytes → AFTER at address 3
        #expect(prog.symbols.lookup("AFTER") == .absolute(3))
    }
}

// MARK: - .BLKW / .BLKB

@Suite(".BLK directives") struct BlkTests {

    @Test func blkwEmitsZeroWords() throws {
        let b = try words(".BLKW 3\n")
        #expect(b == [0, 0, 0])
    }

    @Test func blkbEmitsZeroBytes() throws {
        let b = try bytes(".BLKB 5\n")
        #expect(b == [0, 0, 0, 0, 0])
    }

    @Test func blkwAdvancesLC() throws {
        let prog = try parseSource4(".BLKW 4\nAFTER: HALT\n")
        #expect(prog.symbols.lookup("AFTER") == .absolute(8))
    }

    @Test func blkbAdvancesLC() throws {
        let prog = try parseSource4(".BLKB 3\nAFTER: HALT\n")
        #expect(prog.symbols.lookup("AFTER") == .absolute(3))
    }
}

// MARK: - .ASCII / .ASCIZ

@Suite(".ASCII directive") struct AsciiTests {

    @Test func asciiSlashDelim() throws {
        let b = try bytes(".ASCII /ABC/\n")
        #expect(b == [65, 66, 67])
    }

    @Test func asciiPipeDelim() throws {
        let b = try bytes(".ASCII |Hi|\n")
        #expect(b == [72, 105])
    }

    @Test func ascizAddsNull() throws {
        let b = try bytes(".ASCIZ /OK/\n")
        #expect(b == [79, 75, 0])
    }

    @Test func asciiByteCount() throws {
        let prog = try parseSource4(".ASCII /HELLO/\nAFTER: HALT\n")
        #expect(prog.symbols.lookup("AFTER") == .absolute(5))
    }

    @Test func ascizByteCount() throws {
        let prog = try parseSource4(".ASCIZ /HI/\nAFTER: HALT\n")
        #expect(prog.symbols.lookup("AFTER") == .absolute(3)) // 2 chars + null
    }

    @Test func emptyString() throws {
        let b = try bytes(".ASCII //\n")
        #expect(b.isEmpty)
    }
}

// MARK: - .EVEN

@Suite(".EVEN directive") struct EvenTests {

    @Test func evenAtEvenAddressIsNoop() throws {
        // Start at even address → .EVEN emits nothing
        let b = try bytes(".EVEN\nHALT\n")
        #expect(b.count == 2) // just HALT
    }

    @Test func evenAtOddAddressPads() throws {
        let b = try bytes(".BYTE 1\n.EVEN\nHALT\n")
        #expect(b.count == 4) // 1 byte + 1 pad + 2 (HALT)
    }

    @Test func evenAlignsSoInstructionIsAtEvenAddress() throws {
        let prog = try parseSource4(".BYTE 1\n.EVEN\nLABEL: HALT\n")
        // .BYTE 1 → LC=1; .EVEN pads → LC=2; LABEL = 2
        #expect(prog.symbols.lookup("LABEL") == .absolute(2))
    }
}

// MARK: - Equate (sym = expr)

@Suite("Equates") struct EquateTests {

    @Test func simpleEquate() throws {
        let prog = try parseSource4("SIZE = 100\n")
        #expect(prog.symbols.lookup("SIZE") == .absolute(0o100))
    }

    @Test func equateUsedInInstruction() throws {
        let b = try words("N = 42\nEMT N\n")
        // N = 42 (octal) = 34 decimal; EMT 34 = 0o104000 | 34 = 0o104042
        #expect(b == [0o104042])
    }

    @Test func doubleEquate() throws {
        // sym == expr is also valid (global equate)
        let prog = try parseSource4("X == 7\n")
        #expect(prog.symbols.lookup("X") == .absolute(7))
    }

    @Test func equateExpression() throws {
        let prog = try parseSource4("BASE = 1000\nOFFSET = BASE + 10\n")
        #expect(prog.symbols.lookup("OFFSET") == .absolute(0o1010))
    }

    @Test func equateDoesNotEmitBytes() throws {
        let prog = try parseSource4("N = 5\nHALT\n")
        #expect(prog.items.count == 1) // only HALT, no equate item
    }
}

// MARK: - .= (set location counter)

@Suite("Location counter assignment") struct SetLCTests {

    @Test func setOrigin() throws {
        let prog = try parseSource4(". = 1000\nHALT\n")
        #expect(prog.statements[0].address == 0o1000)
    }

    @Test func labelAfterSetLC() throws {
        let prog = try parseSource4(". = 1000\nSTART: HALT\n")
        #expect(prog.symbols.lookup("START") == .absolute(0o1000))
    }
}

// MARK: - .IF conditional assembly

@Suite(".IF conditional") struct ConditionalTests {

    @Test func ifEqTrue() throws {
        let prog = try parseSource4(".IF EQ, 0\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func ifEqFalse() throws {
        let prog = try parseSource4(".IF EQ, 1\nNOP\n.ENDC\n")
        #expect(prog.statements.isEmpty)
    }

    @Test func ifNeFalse() throws {
        let prog = try parseSource4(".IF NE, 0\nNOP\n.ENDC\n")
        #expect(prog.statements.isEmpty)
    }

    @Test func ifNeTrue() throws {
        let prog = try parseSource4(".IF NE, 1\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func ifGtTrue() throws {
        let prog = try parseSource4(".IF GT, 1\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func ifLtTrue() throws {
        // -1 in 16-bit = 177777 octal; signed < 0
        let prog = try parseSource4(".IF LT, 177777\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func ifDfDefinedSymbol() throws {
        let prog = try parseSource4("X = 1\n.IF DF, X\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func ifDfUndefinedSymbol() throws {
        let prog = try parseSource4(".IF DF, X\nNOP\n.ENDC\n")
        #expect(prog.statements.isEmpty)
    }

    @Test func ifNdfUndefined() throws {
        let prog = try parseSource4(".IF NDF, X\nNOP\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func nestedIfBothTrue() throws {
        let prog = try parseSource4(".IF NE, 1\n.IF NE, 2\nNOP\n.ENDC\n.ENDC\n")
        #expect(prog.statements.count == 1)
    }

    @Test func nestedIfOuterFalse() throws {
        let prog = try parseSource4(".IF EQ, 1\n.IF NE, 1\nNOP\n.ENDC\n.ENDC\n")
        #expect(prog.statements.isEmpty)
    }

    @Test func codeOutsideConditional() throws {
        let prog = try parseSource4("NOP\n.IF EQ, 1\nHALT\n.ENDC\nNOP\n")
        // Only the two NOPs; HALT is inside false block
        #expect(prog.statements.count == 2)
    }

    @Test func conditionalDoesNotAffectLC() throws {
        // Excluded block must not advance LC
        let prog = try parseSource4(".IF EQ, 1\nNOP\n.ENDC\nLABEL: HALT\n")
        #expect(prog.symbols.lookup("LABEL") == .absolute(0))
    }
}

// MARK: - Round-trip with directives

@Suite("RoundTripDirectives") struct RoundTripDirectiveTests {

    @Test func stringFollowedByInstruction() throws {
        // .ASCIZ /OK/ + .EVEN + HALT
        let b = try bytes(".ASCIZ /OK/\n.EVEN\nHALT\n")
        // "OK\0" = 3 bytes, .EVEN pads to 4, HALT = 2 → 6 bytes total
        #expect(b.count == 6)
        #expect(b[0] == 79)  // 'O'
        #expect(b[1] == 75)  // 'K'
        #expect(b[2] == 0)   // null
        #expect(b[3] == 0)   // .EVEN pad
        // HALT = 0o000000 → [0x00, 0x00]
        #expect(b[4] == 0 && b[5] == 0)
    }

    @Test func jumpTable() throws {
        let src = """
        TABLE: .WORD A, B, C
        A: NOP
        B: NOP
        C: HALT
        """
        let prog = try parseSource4(src + "\n")
        // TABLE at 0; A=6, B=8, C=10 (3 words for table = 6 bytes)
        #expect(prog.symbols.lookup("A") == .absolute(6))
        #expect(prog.symbols.lookup("B") == .absolute(8))
        #expect(prog.symbols.lookup("C") == .absolute(10))
        let w = try words(src + "\n")
        #expect(w[0] == 6)   // TABLE[0] = A
        #expect(w[1] == 8)   // TABLE[1] = B
        #expect(w[2] == 10)  // TABLE[2] = C
    }

    @Test func conditionalEquate() throws {
        let src = """
        DEBUG = 0
        .IF NE, DEBUG
        NOP
        .ENDC
        HALT
        """
        let b = try words(src + "\n")
        #expect(b == [0]) // only HALT
    }
}
