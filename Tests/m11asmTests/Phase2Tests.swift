import Testing
@testable import m11asmCore

// MARK: - Instruction table tests

@Suite("InstructionTable") struct InstructionTableTests {

    @Test func lookupMOV() {
        let d = InstructionTable.lookup("MOV")
        #expect(d?.base == 0o010000)
        #expect(d?.format == .doubleOperand)
    }

    @Test func lookupCLR() {
        let d = InstructionTable.lookup("CLR")
        #expect(d?.base == 0o005000)
        #expect(d?.format == .singleOperand)
    }

    @Test func lookupBR() {
        let d = InstructionTable.lookup("BR")
        #expect(d?.base == 0o000400)
        #expect(d?.format == .branch)
    }

    @Test func lookupBNE() { #expect(InstructionTable.lookup("BNE")?.base == 0o001000) }
    @Test func lookupBEQ() { #expect(InstructionTable.lookup("BEQ")?.base == 0o001400) }
    @Test func lookupBGE() { #expect(InstructionTable.lookup("BGE")?.base == 0o002000) }
    @Test func lookupBLT() { #expect(InstructionTable.lookup("BLT")?.base == 0o002400) }
    @Test func lookupBPL() { #expect(InstructionTable.lookup("BPL")?.base == 0o100000) }
    @Test func lookupBMI() { #expect(InstructionTable.lookup("BMI")?.base == 0o100400) }

    @Test func lookupJSR() {
        let d = InstructionTable.lookup("JSR")
        #expect(d?.base == 0o004000)
        #expect(d?.format == .jsr)
    }

    @Test func lookupRTS() {
        let d = InstructionTable.lookup("RTS")
        #expect(d?.base == 0o000200)
        #expect(d?.format == .rts)
    }

    @Test func lookupSOB() {
        let d = InstructionTable.lookup("SOB")
        #expect(d?.base == 0o077000)
        #expect(d?.format == .sob)
    }

    @Test func lookupMUL() {
        let d = InstructionTable.lookup("MUL")
        #expect(d?.base == 0o070000)
        #expect(d?.format == .eisRegSrc)
    }

    @Test func lookupADD()  { #expect(InstructionTable.lookup("ADD")?.base  == 0o060000) }
    @Test func lookupSUB()  { #expect(InstructionTable.lookup("SUB")?.base  == 0o160000) }
    @Test func lookupMOVB() { #expect(InstructionTable.lookup("MOVB")?.base == 0o110000) }
    @Test func lookupSUBbase() { #expect(InstructionTable.lookup("SUB")?.format == .doubleOperand) }

    @Test func lookupHALT() {
        #expect(InstructionTable.lookup("HALT")?.format == .noOperand)
        #expect(InstructionTable.lookup("HALT")?.base == 0)
    }

    @Test func lookupNOP()  { #expect(InstructionTable.lookup("NOP")?.base  == 0o000240) }
    @Test func lookupCLC()  { #expect(InstructionTable.lookup("CLC")?.base  == 0o000241) }
    @Test func lookupSEC()  { #expect(InstructionTable.lookup("SEC")?.base  == 0o000261) }
    @Test func lookupMFPT() { #expect(InstructionTable.lookup("MFPT")?.base == 0o000007) }

    @Test func lookupEMT()  {
        #expect(InstructionTable.lookup("EMT")?.base == 0o104000)
        #expect(InstructionTable.lookup("EMT")?.format == .trapN)
    }

    @Test func lookupSPL()  {
        #expect(InstructionTable.lookup("SPL")?.base == 0o000230)
        #expect(InstructionTable.lookup("SPL")?.format == .splN)
    }

    @Test func aliasesWork() {
        #expect(InstructionTable.lookup("BCC")?.base == InstructionTable.lookup("BHIS")?.base)
        #expect(InstructionTable.lookup("BCS")?.base == InstructionTable.lookup("BLO")?.base)
    }

    @Test func caseInsensitive() {
        #expect(InstructionTable.lookup("mov") != nil)
        #expect(InstructionTable.lookup("Clr") != nil)
    }

    @Test func unknownMnemonic() {
        #expect(InstructionTable.lookup("XYZZY") == nil)
    }
}

// MARK: - Operand encoding tests

@Suite("OperandEncoding") struct OperandEncodingTests {

    private let pc: UInt16 = 0o001002 // arbitrary extension-word address

    @Test func registerMode() {
        let enc = OperandMode.register(0).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o00)
        #expect(enc.extensionExpr == nil)
    }

    @Test func register5() {
        #expect(OperandMode.register(5).encode(extensionWordAddress: pc).field == 5)
    }

    @Test func registerDeferred() {
        let enc = OperandMode.registerDeferred(2).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o12)   // mode 1 (0o10) + reg 2
        #expect(enc.extensionExpr == nil)
    }

    @Test func autoIncrement() {
        #expect(OperandMode.autoIncrement(3).encode(extensionWordAddress: pc).field == 0o23)
    }

    @Test func autoIncrementDeferred() {
        #expect(OperandMode.autoIncrementDeferred(4).encode(extensionWordAddress: pc).field == 0o34)
    }

    @Test func autoDecrement() {
        #expect(OperandMode.autoDecrement(1).encode(extensionWordAddress: pc).field == 0o41)
    }

    @Test func autoDecrementDeferred() {
        #expect(OperandMode.autoDecrementDeferred(0).encode(extensionWordAddress: pc).field == 0o50)
    }

    @Test func indexMode() {
        let enc = OperandMode.index(.literal(4), 1).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o61)           // mode 6 (0o60) + reg 1
        #expect(enc.extensionExpr == .literal(4))
    }

    @Test func indexDeferredMode() {
        let enc = OperandMode.indexDeferred(.literal(0o200), 5).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o75)
        #expect(enc.extensionExpr == .literal(0o200))
    }

    @Test func immediateMode() {
        let enc = OperandMode.immediate(.literal(0o377)).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o27)           // mode 2, R7
        #expect(enc.extensionExpr == .literal(0o377))
    }

    @Test func absoluteMode() {
        let enc = OperandMode.absolute(.literal(0o177776)).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o37)           // mode 3, R7
        #expect(enc.extensionExpr == .literal(0o177776))
    }

    @Test func relativeMode() {
        // relative stores a displacement expression target-(pc+2), evaluated at pass 2
        let target: Expression = .literal(0o001010)
        let enc = OperandMode.relative(target).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o67)
        // Verify displacement: evaluate with empty symbol table
        let st = SymbolTable()
        let disp = try? enc.extensionExpr!.evaluate(symbols: st, locationCounter: 0)
        // target(001010) - (pc(001002) + 2(2)) = 001010 - 001004 = 4
        #expect(disp == 4)
    }

    @Test func relativeDeferredMode() {
        let enc = OperandMode.relativeDeferred(.literal(0o001010)).encode(extensionWordAddress: pc)
        #expect(enc.field == 0o77)
    }

    @Test func hasExtensionWord() {
        #expect(OperandMode.register(0).hasExtensionWord == false)
        #expect(OperandMode.immediate(.literal(0)).hasExtensionWord == true)
        #expect(OperandMode.index(.literal(0), 0).hasExtensionWord == true)
        #expect(OperandMode.autoIncrement(0).hasExtensionWord == false)
    }
}

// MARK: - Expression parser tests

@Suite("ExpressionParser") struct ExpressionParserTests {

    private func lex(_ src: String) throws -> [Located<Token>] {
        var l = Lexer(source: src); return try l.tokenize()
    }

    private func parse(_ src: String) throws -> Expression {
        var s = TokenStream(try lex(src))
        return try parseExpression(stream: &s)
    }

    @Test func literalExpr() throws {
        #expect(try parse("177") == .literal(0o177))
    }

    @Test func symbolExpr() throws {
        #expect(try parse("FOO") == .symbol("FOO"))
    }

    @Test func locationCounter() throws {
        #expect(try parse(".") == .locationCounter)
    }

    @Test func addExpr() throws {
        let e = try parse("1+2")
        #expect(e == .add(.literal(1), .literal(2)))
    }

    @Test func subtractExpr() throws {
        #expect(try parse("10-3") == .subtract(.literal(0o10), .literal(3)))
    }

    @Test func leftToRightNoPrecedence() throws {
        // 2+3*4 = (2+3)*4 = 20 in MACRO-11 (left-to-right, no precedence)
        let e = try parse("2+3*4")
        let st = SymbolTable()
        let v = try e.evaluate(symbols: st, locationCounter: 0)
        #expect(v == 20)
    }

    @Test func unaryMinus() throws {
        let e = try parse("-1")
        let st = SymbolTable()
        #expect(try e.evaluate(symbols: st, locationCounter: 0) == UInt16(bitPattern: -1))
    }

    @Test func parenGrouping() throws {
        // (2+3) stops the expression after )
        let tokens = try lex("(2+3),R0")
        var s = TokenStream(tokens)
        let e = try parseExpression(stream: &s)
        let st = SymbolTable()
        #expect(try e.evaluate(symbols: st, locationCounter: 0) == 5)
        #expect(s.peek() == .comma) // parser stopped at comma
    }

    @Test func dotPlusOffset() throws {
        let e = try parse(". + 4")
        #expect(e == .add(.locationCounter, .literal(4)))
    }

    @Test func asciiCharExpr() throws {
        let e = try parse("'A")
        let st = SymbolTable()
        #expect(try e.evaluate(symbols: st, locationCounter: 0) == 65)
    }
}

// MARK: - Operand parser tests

@Suite("OperandParser") struct OperandParserTests {

    private func lex(_ src: String) throws -> [Located<Token>] {
        var l = Lexer(source: src); return try l.tokenize()
    }

    private func parseOp(_ src: String) throws -> OperandMode {
        var s = TokenStream(try lex(src))
        return try parseOperand(stream: &s)
    }

    @Test func registerR0() throws { #expect(try parseOp("R0")  == .register(0)) }
    @Test func registerSP() throws { #expect(try parseOp("SP")  == .register(6)) }
    @Test func registerPC() throws { #expect(try parseOp("PC")  == .register(7)) }
    @Test func registerR5() throws { #expect(try parseOp("R5")  == .register(5)) }

    @Test func registerDeferred() throws {
        #expect(try parseOp("(R1)") == .registerDeferred(1))
    }

    @Test func autoIncrement() throws {
        #expect(try parseOp("(R2)+") == .autoIncrement(2))
    }

    @Test func autoIncrementDeferred() throws {
        #expect(try parseOp("@(R3)+") == .autoIncrementDeferred(3))
    }

    @Test func autoDecrement() throws {
        #expect(try parseOp("-(R4)") == .autoDecrement(4))
    }

    @Test func autoDecrementDeferred() throws {
        #expect(try parseOp("@-(R5)") == .autoDecrementDeferred(5))
    }

    @Test func indexMode() throws {
        let op = try parseOp("4(R1)")
        #expect(op == .index(.literal(4), 1))
    }

    @Test func indexDeferredMode() throws {
        let op = try parseOp("@4(R2)")
        #expect(op == .indexDeferred(.literal(4), 2))
    }

    @Test func immediate() throws {
        #expect(try parseOp("#177") == .immediate(.literal(0o177)))
    }

    @Test func immediateDecimal() throws {
        #expect(try parseOp("#^D255") == .immediate(.literal(255)))
    }

    @Test func absolute() throws {
        #expect(try parseOp("@#177776") == .absolute(.literal(0o177776)))
    }

    @Test func relative() throws {
        #expect(try parseOp("LOOP") == .relative(.symbol("LOOP")))
    }

    @Test func relativeDeferred() throws {
        #expect(try parseOp("@LOOP") == .relativeDeferred(.symbol("LOOP")))
    }

    @Test func indexWithExpr() throws {
        // ^D4(R3) — decimal index
        let op = try parseOp("^D4(R3)")
        #expect(op == .index(.literal(4), 3))
    }

    @Test func immediateExpression() throws {
        // #FOO+2
        let op = try parseOp("#FOO+2")
        #expect(op == .immediate(.add(.symbol("FOO"), .literal(2))))
    }

    @Test func twoOperandsSeparatedByComma() throws {
        // Parse "R0, R1" as two operands
        let tokens = try lex("R0, R1")
        var s = TokenStream(tokens)
        let op1 = try parseOperand(stream: &s)
        #expect(op1 == .register(0))
        _ = s.match(.comma)
        let op2 = try parseOperand(stream: &s)
        #expect(op2 == .register(1))
    }
}
