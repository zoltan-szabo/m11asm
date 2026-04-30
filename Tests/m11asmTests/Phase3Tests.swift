import Testing
@testable import m11asmCore

// MARK: - Helpers

private func lex(_ src: String) throws -> [Located<Token>] {
    var l = Lexer(source: src); return try l.tokenize()
}

private func parseSource(_ src: String, origin: UInt16 = 0) throws -> ParsedProgram {
    let tokens = try lex(src)
    var diag = DiagnosticEngine()
    let prog = parse(tokens: tokens, origin: origin, diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return prog
}

private func assembleBytes(_ src: String, origin: UInt16 = 0) throws -> [UInt8] {
    let prog = try parseSource(src, origin: origin)
    var diag = DiagnosticEngine()
    let bytes = assemble(program: prog, diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return bytes
}

private func assemble(_ src: String, origin: UInt16 = 0) throws -> [UInt16] {
    let bytes = try assembleBytes(src, origin: origin)
    return stride(from: 0, to: bytes.count, by: 2).map { i in
        UInt16(bytes[i]) | (i + 1 < bytes.count ? UInt16(bytes[i + 1]) << 8 : 0)
    }
}

// MARK: - Parser tests

@Suite("Parser") struct ParserTests {

    @Test func noOperandStatement() throws {
        let prog = try parseSource("HALT\n")
        #expect(prog.statements.count == 1)
        #expect(prog.statements[0].descriptor.mnemonic == "HALT")
        #expect(prog.statements[0].address == 0)
        if case .none = prog.statements[0].operands { } else { #expect(Bool(false)) }
    }

    @Test func singleOperandStatement() throws {
        let prog = try parseSource("CLR R0\n")
        #expect(prog.statements.count == 1)
        if case .single(let op) = prog.statements[0].operands {
            #expect(op == .register(0))
        } else { #expect(Bool(false)) }
    }

    @Test func doubleOperandStatement() throws {
        let prog = try parseSource("MOV R0, R1\n")
        #expect(prog.statements.count == 1)
        if case .double(let s, let d) = prog.statements[0].operands {
            #expect(s == .register(0))
            #expect(d == .register(1))
        } else { #expect(Bool(false)) }
    }

    @Test func labelDefinedToLC() throws {
        let prog = try parseSource("START: HALT\n")
        #expect(prog.symbols.lookup("START") == .absolute(0))
    }

    @Test func labelOnOwnLine() throws {
        let prog = try parseSource("START:\nHALT\n")
        #expect(prog.symbols.lookup("START") == .absolute(0))
        #expect(prog.statements[0].address == 0)
    }

    @Test func labelAdvancesWithLC() throws {
        // NOP = 1 word, so NEXT label = address 2
        let prog = try parseSource("NOP\nNEXT: HALT\n")
        #expect(prog.symbols.lookup("NEXT") == .absolute(2))
        #expect(prog.statements[1].address == 2)
    }

    @Test func branchOperand() throws {
        let prog = try parseSource("BR LOOP\n")
        if case .branch(let e) = prog.statements[0].operands {
            #expect(e == .symbol("LOOP"))
        } else { #expect(Bool(false)) }
    }

    @Test func rtsOperand() throws {
        let prog = try parseSource("RTS PC\n")
        if case .regOnly(let r) = prog.statements[0].operands {
            #expect(r == 7) // PC = R7
        } else { #expect(Bool(false)) }
    }

    @Test func jsrOperand() throws {
        let prog = try parseSource("JSR PC, @#177776\n")
        if case .regOperand(let r, let op) = prog.statements[0].operands {
            #expect(r == 7)
            #expect(op == .absolute(.literal(0o177776)))
        } else { #expect(Bool(false)) }
    }

    @Test func sobOperand() throws {
        let prog = try parseSource("SOB R1, LOOP\n")
        if case .regExpr(let r, let e) = prog.statements[0].operands {
            #expect(r == 1)
            #expect(e == .symbol("LOOP"))
        } else { #expect(Bool(false)) }
    }

    @Test func emtOperand() throws {
        let prog = try parseSource("EMT 377\n")
        if case .trapN(let e) = prog.statements[0].operands {
            let st = SymbolTable()
            #expect((try? e.evaluate(symbols: st, locationCounter: 0)) == 0o377)
        } else { #expect(Bool(false)) }
    }

    @Test func wordCountNoExt() throws {
        let prog = try parseSource("MOV R0, R1\n")
        #expect(prog.statements[0].operands.wordCount == 1)
    }

    @Test func wordCountWithImmediate() throws {
        // MOV #1, R0 → 2 words (instruction + immediate extension)
        let prog = try parseSource("MOV #1, R0\n")
        #expect(prog.statements[0].operands.wordCount == 2)
    }

    @Test func wordCountTwoExtensions() throws {
        // MOV #1, #2 would be odd but legal syntax; tests word count = 3
        let prog = try parseSource("MOV #1, LABEL\n")
        #expect(prog.statements[0].operands.wordCount == 3)
    }

    @Test func lcAdvancesByWordCount() throws {
        let prog = try parseSource("MOV #1, R0\nHALT\n")
        // MOV #1, R0 = 2 words = 4 bytes → HALT at address 4
        #expect(prog.statements[1].address == 4)
    }

    @Test func endDirectiveStopsParser() throws {
        let prog = try parseSource("NOP\n.END\nHALT\n")
        #expect(prog.statements.count == 1)
    }

    @Test func multipleStatements() throws {
        let prog = try parseSource("NOP\nNOP\nHALT\n")
        #expect(prog.statements.count == 3)
    }

    @Test func unknownMnemonicRecovery() throws {
        let tokens = try lex("XYZZY\nHALT\n")
        var diag = DiagnosticEngine()
        let prog = parse(tokens: tokens, diagnostics: &diag)
        #expect(diag.hasErrors)
        // Parser recovers and still sees HALT
        #expect(prog.statements.count == 1)
    }

    @Test func originApplied() throws {
        let prog = try parseSource("HALT\n", origin: 0o1000)
        #expect(prog.statements[0].address == 0o1000)
        #expect(prog.origin == 0o1000)
    }

    @Test func caseInsensitiveLabel() throws {
        let prog = try parseSource("start: HALT\n")
        #expect(prog.symbols.lookup("START") == .absolute(0))
        #expect(prog.symbols.lookup("start") == .absolute(0))
    }
}

// MARK: - CodeGen tests

@Suite("CodeGen") struct CodeGenTests {

    @Test func haltEncoding() throws {
        #expect(try assemble("HALT\n") == [0o000000])
    }

    @Test func nopEncoding() throws {
        #expect(try assemble("NOP\n") == [0o000240])
    }

    @Test func clrR0() throws {
        #expect(try assemble("CLR R0\n") == [0o005000])
    }

    @Test func clrParenR1() throws {
        // CLR (R1) → singleOperand, mode 1 (registerDeferred), reg 1 → field = 0o11
        #expect(try assemble("CLR (R1)\n") == [0o005011])
    }

    @Test func movR0R1() throws {
        // MOV R0, R1 → 0o010000 | (0o00 << 6) | 0o01
        #expect(try assemble("MOV R0, R1\n") == [0o010001])
    }

    @Test func movImmediateToReg() throws {
        // MOV #100, R0 → 0o012700, 0o000100
        let words = try assemble("MOV #100, R0\n")
        #expect(words == [0o012700, 0o000100])
    }

    @Test func addR0R1() throws {
        // ADD R0, R1 → 0o060001
        #expect(try assemble("ADD R0, R1\n") == [0o060001])
    }

    @Test func subR2R3() throws {
        // SUB R2, R3 → 0o160203
        #expect(try assemble("SUB R2, R3\n") == [0o160203])
    }

    @Test func movbR0R1() throws {
        // MOVB R0, R1 → 0o110001
        #expect(try assemble("MOVB R0, R1\n") == [0o110001])
    }

    @Test func rtsPC() throws {
        // RTS PC → 0o000207
        #expect(try assemble("RTS PC\n") == [0o000207])
    }

    @Test func jsrPCAbsolute() throws {
        // JSR PC, @#200 → [0o004737, 0o000200]
        let words = try assemble("JSR PC, @#200\n")
        #expect(words == [0o004737, 0o000200])
    }

    @Test func emtZero() throws {
        // EMT 0 → 0o104000
        #expect(try assemble("EMT 0\n") == [0o104000])
    }

    @Test func emtMax() throws {
        // EMT 377 → 0o104377
        #expect(try assemble("EMT 377\n") == [0o104377])
    }

    @Test func splN() throws {
        // SPL 7 → 0o000237
        #expect(try assemble("SPL 7\n") == [0o000237])
    }

    @Test func brForward() throws {
        // NOP then BR to 2 instructions ahead: target = addr+4, pc = addr+2, offset = +1
        let words = try assemble("BR TARGET\nNOP\nTARGET: HALT\n")
        // BR is at addr 0, pc = 2, target = 4, word_offset = +1
        #expect(words[0] == 0o000401)
    }

    @Test func brBackward() throws {
        // LOOP: NOP; BR LOOP → offset = -1 (word), encoded as 0o377 = 255 = -1 in 8-bit signed
        let words = try assemble("LOOP: NOP\nBR LOOP\n")
        // BR at addr 2, pc = 4, target = 0, diff = -4 bytes = -2 words
        // signed 8-bit -2 = 0o376
        #expect(words[1] == 0o000776)
    }

    @Test func bneForwardRef() throws {
        // BNE TARGET where target is forward label
        let words = try assemble("BNE TARGET\nNOP\nTARGET: HALT\n")
        // BNE at 0, pc=2, target=4, offset=+1; BNE base=0o001000 → 0o001001
        #expect(words[0] == 0o001001)
    }

    @Test func sobLoop() throws {
        // LOOP: NOP; NOP; SOB R1, LOOP
        // SOB at addr 4, pc=6, target=0, back=6 bytes = 3 words → bits 5-0 = 3, reg=1 → bits 8-6 = 1
        // SOB base = 0o077000, | (1<<6) | 3 = 0o077000 | 0o100 | 3 = 0o077103
        let words = try assemble("LOOP: NOP\nNOP\nSOB R1, LOOP\n")
        #expect(words[2] == 0o077103)
    }

    @Test func mulEncoding() throws {
        // MUL R2, R3 → eisRegSrc → base 0o070000 | (R2<<6) | R3 = 0o070000 | 0o200 | 3 = 0o070203
        #expect(try assemble("MUL R2, R3\n") == [0o070203])
    }

    @Test func autoIncrementSrc() throws {
        // MOV (R0)+, R1 → src=autoIncrement(0) field=0o20, dst=register(1) field=0o01
        // 0o010000 | (0o20 << 6) | 0o01 = 0o010000 | 0o2000 | 1 = 0o012001
        #expect(try assemble("MOV (R0)+, R1\n") == [0o012001])
    }

    @Test func twoExtensionWords() throws {
        // MOV #1, #2 → illegal as dst but valid encoding test
        // src=immediate(1): field=0o27, ext=1
        // dst=immediate(2): field=0o27, ext=2
        // instr = 0o010000 | (0o27<<6) | 0o27 = 0o010000 | 0o2700 | 0o27 = 0o012727
        let words = try assemble("MOV #1, #2\n")
        #expect(words == [0o012727, 1, 2])
    }

    @Test func relativeAddressing() throws {
        // MOV LABEL, R0 where LABEL: is after MOV
        // MOV at 0, src=relative(.symbol("LABEL")), extension word at addr 2
        // LABEL at 4 (after 2-word MOV instruction)
        // disp = 4 - (2 + 2) = 0
        let words = try assemble("MOV LABEL, R0\nLABEL: HALT\n")
        // MOV relative src: field=0o67, dst=R0: field=0o00
        // instr = 0o010000 | (0o67 << 6) | 0o00 = 0o010000 | 0o6700 | 0 = 0o016700
        #expect(words[0] == 0o016700)
        #expect(words[1] == 0)  // displacement = 0
        #expect(words[2] == 0o000000) // HALT
    }
}

// MARK: - Round-trip integration tests

@Suite("RoundTrip") struct RoundTripTests {

    @Test func simpleSubroutine() throws {
        let src = """
        DOUBLE: ASL R0
                RTS PC
        """
        let words = try assemble(src + "\n")
        #expect(words.count == 2)
        #expect(words[0] == 0o006300) // ASL R0
        #expect(words[1] == 0o000207) // RTS PC
    }

    @Test func forwardBranchOverData() throws {
        // BEQ skips NOP, lands on HALT
        let src = """
        BEQ SKIP
        NOP
        SKIP: HALT
        """
        let words = try assemble(src + "\n")
        #expect(words.count == 3)
        // BEQ at 0, pc=2, SKIP=4, offset=+1 word → 0o001401
        #expect(words[0] == 0o001401)
    }

    @Test func labelForwardReference() throws {
        let src = """
        MOV #TARGET, R0
        TARGET: HALT
        """
        // MOV #TARGET, R0 → immediate(.symbol("TARGET"))
        // TARGET is at address 4 (after 2-word MOV)
        let words = try assemble(src + "\n")
        #expect(words[1] == 4) // immediate value = address of TARGET
    }

    @Test func countsSymbols() throws {
        let src = """
        A: NOP
        B: NOP
        C: HALT
        """
        let prog = try parseSource(src + "\n")
        #expect(prog.symbols.lookup("A") == .absolute(0))
        #expect(prog.symbols.lookup("B") == .absolute(2))
        #expect(prog.symbols.lookup("C") == .absolute(4))
    }

    @Test func originOffset() throws {
        let prog = try parseSource("START: HALT\n", origin: 0o1000)
        #expect(prog.symbols.lookup("START") == .absolute(0o1000))
        let words = try assemble("HALT\n", origin: 0o1000)
        #expect(words == [0])
    }
}
