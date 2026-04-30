import Testing
@testable import m11asmCore

// MARK: - Helpers

private func lex5(_ src: String) throws -> [Located<Token>] {
    var l = Lexer(source: src); return try l.tokenize()
}

private func expand5(_ src: String) throws -> [Located<Token>] {
    var diag = DiagnosticEngine()
    var exp  = MacroExpander()
    let out  = exp.expand(tokens: try lex5(src), diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return out
}

private func assemble5(_ src: String, origin: UInt16 = 0) throws -> [UInt16] {
    let tokens   = try lex5(src)
    var diag     = DiagnosticEngine()
    var exp      = MacroExpander()
    let expanded = exp.expand(tokens: tokens, diagnostics: &diag)
    let prog     = parse(tokens: expanded, origin: origin, diagnostics: &diag)
    let bytes    = assemble(program: prog, diagnostics: &diag)
    if diag.hasErrors {
        throw ParseError(location: .unknown,
                         message: diag.diagnostics.map(\.description).joined(separator: "; "))
    }
    return stride(from: 0, to: bytes.count, by: 2).map { i in
        UInt16(bytes[i]) | (i + 1 < bytes.count ? UInt16(bytes[i + 1]) << 8 : 0)
    }
}

// MARK: - Macro definition / invocation

@Suite("MacroDefInvoke") struct MacroDefInvokeTests {

    @Test func macroWithNoParamsExpands() throws {
        let src = """
        .MACRO DOIT
        NOP
        .ENDM
        DOIT
        """
        #expect(try assemble5(src + "\n") == [0o000240])
    }

    @Test func macroWithOneParam() throws {
        let src = #"""
        .MACRO PUSH REG
        MOV \REG, -(SP)
        .ENDM
        PUSH R0
        """#
        // MOV R0, -(SP): src=R0 field=0o00, dst=autoDecrement(6) field=0o46
        // 0o010000 | (0o00 << 6) | 0o46 = 0o010046
        #expect(try assemble5(src + "\n") == [0o010046])
    }

    @Test func macroWithTwoParams() throws {
        let src = #"""
        .MACRO XCHG A, B
        MOV \A, R5
        MOV \B, \A
        MOV R5, \B
        .ENDM
        XCHG R0, R1
        """#
        let words = try assemble5(src + "\n")
        #expect(words.count == 3)
        #expect(words[0] == 0o010005) // MOV R0, R5
        #expect(words[1] == 0o010100) // MOV R1, R0
        #expect(words[2] == 0o010501) // MOV R5, R1
    }

    @Test func macroInvokedTwice() throws {
        let src = """
        .MACRO DOIT
        NOP
        .ENDM
        DOIT
        DOIT
        """
        #expect(try assemble5(src + "\n") == [0o000240, 0o000240])
    }

    @Test func macroWithLabel() throws {
        let src = #"""
        .MACRO DOUBLE R
        ASL \R
        .ENDM
        DOUBLE R0
        """#
        // ASL R0 = 0o006300
        #expect(try assemble5(src + "\n") == [0o006300])
    }

    @Test func macroDefinitionDoesNotEmitCode() throws {
        let src = """
        .MACRO DOIT
        NOP
        .ENDM
        HALT
        """
        #expect(try assemble5(src + "\n") == [0o000000])
    }

    @Test func macroWithAngleBracketArg() throws {
        let src = #"""
        .MACRO STORE ADDR
        MOV R0, \ADDR
        .ENDM
        STORE <@#177776>
        """#
        // MOV R0, @#177776: src=R0 field=0o00, dst=absolute field=0o37
        // instr = 0o010000 | 0o37 = 0o010037, ext = 0o177776
        let words = try assemble5(src + "\n")
        #expect(words[0] == 0o010037)
        #expect(words[1] == 0o177776)
    }

    @Test func macroMissingArgTreatedAsEmpty() throws {
        // Param not used in body → empty arg has no effect
        let src = """
        .MACRO DOIT P
        NOP
        .ENDM
        DOIT
        """
        #expect(try assemble5(src + "\n") == [0o000240])
    }
}

// MARK: - Local labels with \@

@Suite("MacroLocalLabels") struct MacroLocalLabelsTests {

    @Test func localLabelUnique() throws {
        let src = #"""
        .MACRO SKIP_NOP
        BR DONE\@
        NOP
        DONE\@: HALT
        .ENDM
        SKIP_NOP
        SKIP_NOP
        """#
        let words = try assemble5(src + "\n")
        // Each expansion = 3 words; two invocations = 6 words
        #expect(words.count == 6)
        // BR at addr 0, DONE = addr 4, pc=2, offset=(4-2)/2=+1 → 0o000401
        #expect(words[0] == 0o000401)
        #expect(words[1] == 0o000240)   // NOP
        #expect(words[2] == 0o000000)   // HALT at DONE__M0001
        // Second expansion at addr 6
        #expect(words[3] == 0o000401)   // BR +1
        #expect(words[4] == 0o000240)   // NOP
        #expect(words[5] == 0o000000)   // HALT at DONE__M0002
    }

    @Test func symbolConcatenationWithAt() throws {
        let src = #"""
        .MACRO COUNTER
        LOOP\@: NOP
        .ENDM
        COUNTER
        COUNTER
        """#
        // Two unique labels → no collision
        #expect(try assemble5(src + "\n") == [0o000240, 0o000240])
    }
}

// MARK: - .REPT

@Suite("REPT") struct ReptTests {

    @Test func reptEmitsBodyNTimes() throws {
        let src = """
        .REPT 3
        NOP
        .ENDR
        """
        #expect(try assemble5(src + "\n") == [0o000240, 0o000240, 0o000240])
    }

    @Test func reptZeroTimesEmpty() throws {
        let src = """
        .REPT 0
        NOP
        .ENDR
        HALT
        """
        #expect(try assemble5(src + "\n") == [0o000000])
    }

    @Test func reptBuildWordTable() throws {
        let src = """
        .REPT 4
        .WORD 1
        .ENDR
        """
        #expect(try assemble5(src + "\n") == [1, 1, 1, 1])
    }

    @Test func nestedRept() throws {
        let src = """
        .REPT 2
        .REPT 2
        NOP
        .ENDR
        .ENDR
        """
        #expect(try assemble5(src + "\n") == [0o000240, 0o000240, 0o000240, 0o000240])
    }
}

// MARK: - .IRP

@Suite("IRP") struct IRPTests {

    @Test func irpExpandsOverList() throws {
        let src = #"""
        .IRP REG, <R0,R1,R2>
        CLR \REG
        .ENDR
        """#
        let words = try assemble5(src + "\n")
        #expect(words == [0o005000, 0o005001, 0o005002])
    }

    @Test func irpSingleElement() throws {
        let src = #"""
        .IRP X, <R0>
        INC \X
        .ENDR
        """#
        #expect(try assemble5(src + "\n") == [0o005200])
    }

    @Test func irpWithWordDirective() throws {
        let src = #"""
        .IRP VAL, <1,2,3>
        .WORD \VAL
        .ENDR
        """#
        #expect(try assemble5(src + "\n") == [1, 2, 3])
    }
}

// MARK: - Macro calling macro

@Suite("MacroNesting") struct MacroNestingTests {

    @Test func macroCallsOtherMacro() throws {
        let src = #"""
        .MACRO PUSH R
        MOV \R, -(SP)
        .ENDM
        .MACRO PUSH2 A, B
        PUSH \A
        PUSH \B
        .ENDM
        PUSH2 R0, R1
        """#
        // MOV R0, -(SP) = 0o010046
        // MOV R1, -(SP): src=R1 field=0o01, dst=0o46 → 0o010000 | (0o01<<6) | 0o46 = 0o010146
        let words = try assemble5(src + "\n")
        #expect(words == [0o010046, 0o010146])
    }

    @Test func macroDefinedInsideRept() throws {
        // .MACRO inside .REPT is registered; last definition wins, but they're identical
        let src = """
        .REPT 2
        .MACRO DOIT
        NOP
        .ENDM
        .ENDR
        DOIT
        """
        #expect(try assemble5(src + "\n") == [0o000240])
    }
}

// MARK: - Token-level expander tests

@Suite("ExpanderOutput") struct ExpanderOutputTests {

    @Test func macroDefinitionRemovedFromStream() throws {
        let toks = try expand5(".MACRO FOO\nNOP\n.ENDM\n")
        let syms = toks.compactMap { if case .symbol(let s) = $0.value { return s } else { return nil } }
        #expect(!syms.contains("NOP"))
        #expect(!syms.contains(".MACRO"))
        #expect(!syms.contains(".ENDM"))
    }

    @Test func macroBodyInsertedAtCallSite() throws {
        let toks = try expand5(".MACRO FOO\nNOP\n.ENDM\nFOO\n")
        let syms = toks.compactMap { if case .symbol(let s) = $0.value { return s } else { return nil } }
        #expect(syms.contains("NOP"))
    }

    @Test func reptRemovedFromStream() throws {
        let toks = try expand5(".REPT 0\nNOP\n.ENDR\n")
        let syms = toks.compactMap { if case .symbol(let s) = $0.value { return s } else { return nil } }
        #expect(!syms.contains(".REPT"))
        #expect(!syms.contains(".ENDR"))
        #expect(!syms.contains("NOP"))
    }
}

// MARK: - Integration

@Suite("Phase5Integration") struct Phase5IntegrationTests {

    @Test func pushPopRoundTrip() throws {
        let src = #"""
        .MACRO PUSH R
        MOV \R, -(SP)
        .ENDM
        .MACRO POP R
        MOV (SP)+, \R
        .ENDM
        PUSH R0
        POP R0
        """#
        // MOV R0, -(SP) = 0o010046
        // MOV (SP)+, R0: src=autoIncrement(6) field=0o26, dst=R0 field=0o00
        // 0o010000 | (0o26 << 6) | 0o00 = 0o010000 | 0o2600 = 0o012600
        let words = try assemble5(src + "\n")
        #expect(words == [0o010046, 0o012600])
    }

    @Test func clrAllRegs() throws {
        let src = #"""
        .IRP R, <R0,R1,R2,R3,R4,R5>
        CLR \R
        .ENDR
        """#
        let words = try assemble5(src + "\n")
        #expect(words == [0o005000, 0o005001, 0o005002, 0o005003, 0o005004, 0o005005])
    }

    @Test func labelAfterMacroExpansion() throws {
        let src = """
        .MACRO NOP2
        NOP
        NOP
        .ENDM
        NOP2
        AFTER: HALT
        """
        let tokens   = try lex5(src + "\n")
        var diag     = DiagnosticEngine()
        var exp      = MacroExpander()
        let expanded = exp.expand(tokens: tokens, diagnostics: &diag)
        let prog     = parse(tokens: expanded, diagnostics: &diag)
        // NOP2 expands to 2 NOPs (4 bytes) → AFTER at address 4
        #expect(prog.symbols.lookup("AFTER") == .absolute(4))
    }

    @Test func conditionalMacroWithIF() throws {
        // Combine .IF with macro expansion
        let src = """
        DEBUG = 0
        .MACRO DBG_NOP
        .IF NE, DEBUG
        NOP
        .ENDC
        .ENDM
        DBG_NOP
        HALT
        """
        // DEBUG=0, so .IF NE, 0 is false → NOP not emitted → only HALT
        let words = try assemble5(src + "\n")
        #expect(words == [0o000000])
    }
}
