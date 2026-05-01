// DisassemblerTests.swift — unit tests for Disassembler.swift

import Testing
@testable import m11asmCore

@Suite("Disassembler")
struct DisassemblerTests {

    // MARK: - No-operand

    @Test func halt() {
        let r = dis([0o000000])
        #expect(r[0].mnemonic == "HALT")
        #expect(r[0].operands == "")
        #expect(r[0].address == 0o1000)
        #expect(r[0].words == [0o000000])
    }

    @Test func nop() {
        let r = dis([0o000240])
        #expect(r[0].mnemonic == "NOP")
        #expect(r[0].operands == "")
    }

    @Test func conditionCodes() {
        #expect(dis([0o000241])[0].mnemonic == "CLC")
        #expect(dis([0o000261])[0].mnemonic == "SEC")
        #expect(dis([0o000257])[0].mnemonic == "CCC")
        #expect(dis([0o000277])[0].mnemonic == "SCC")
    }

    @Test func rts() {
        // RTS PC → 000207
        let r = dis([0o000207])
        #expect(r[0].mnemonic == "RTS")
        #expect(r[0].operands == "PC")
    }

    @Test func rtsR0() {
        // RTS R0 → 000200
        let r = dis([0o000200])
        #expect(r[0].mnemonic == "RTS")
        #expect(r[0].operands == "R0")
    }

    @Test func spl() {
        // SPL 3 → 000233
        let r = dis([0o000233])
        #expect(r[0].mnemonic == "SPL")
        #expect(r[0].operands == "3")
    }

    // MARK: - Single-operand

    @Test func clrR3() {
        let r = dis([0o005003])
        #expect(r[0].mnemonic == "CLR")
        #expect(r[0].operands == "R3")
        #expect(r[0].words.count == 1)
    }

    @Test func clrDeferred() {
        // CLR @(R1) = CLR mode1/R1 → 005011
        let r = dis([0o005011])
        #expect(r[0].mnemonic == "CLR")
        #expect(r[0].operands == "(R1)")
    }

    @Test func clrAutoInc() {
        // CLR (R2)+ → 005022
        let r = dis([0o005022])
        #expect(r[0].mnemonic == "CLR")
        #expect(r[0].operands == "(R2)+")
    }

    @Test func clrAutoDec() {
        // CLR -(R4) → 005044
        let r = dis([0o005044])
        #expect(r[0].mnemonic == "CLR")
        #expect(r[0].operands == "-(R4)")
    }

    @Test func jmpAbsolute() {
        // JMP @#addr → JMP mode3/R7 = 000137 + ext
        let r = dis([0o000137, 0o001000])
        #expect(r[0].mnemonic == "JMP")
        #expect(r[0].operands == "@#001000")
        #expect(r[0].words.count == 2)
    }

    @Test func sxt() {
        let r = dis([0o006703])
        #expect(r[0].mnemonic == "SXT")
        #expect(r[0].operands == "R3")
    }

    @Test func tstbAutoIncrDeferred() {
        // TSTB @(R3)+ → 105733  (TSTB base 105700 | mode3/R3=033)
        let r = dis([0o105733])
        #expect(r[0].mnemonic == "TSTB")
        #expect(r[0].operands == "@(R3)+")
    }

    // MARK: - Double-operand

    @Test func movRegReg() {
        // MOV R0, R1 → 010001
        let r = dis([0o010001])
        #expect(r[0].mnemonic == "MOV")
        #expect(r[0].operands == "R0, R1")
        #expect(r[0].words.count == 1)
    }

    @Test func movImmReg() {
        // MOV #000377, R0 → 012700 000377
        let r = dis([0o012700, 0o000377])
        #expect(r.count == 1)
        #expect(r[0].mnemonic == "MOV")
        #expect(r[0].operands == "#000377, R0")
        #expect(r[0].words.count == 2)
    }

    @Test func movThreeWords() {
        // MOV @#src, @#dst → opcode 013737 + two extension words
        let r = dis([0o013737, 0o001000, 0o002000])
        #expect(r.count == 1)
        #expect(r[0].mnemonic == "MOV")
        #expect(r[0].operands == "@#001000, @#002000")
        #expect(r[0].words.count == 3)
    }

    @Test func movIndexed() {
        // MOV 000010(R1), R2 → two words
        // src: mode6/R1 = 0o61 = 0b110_001, dst: mode0/R2 = 0o02
        // opcode: 0o010000 | (0o61 << 6) | 0o02 = 0o010000 | 0o6100 | 0o02 = 0o016102
        let r = dis([0o016102, 0o000010])
        #expect(r[0].mnemonic == "MOV")
        #expect(r[0].operands == "000010(R1), R2")
        #expect(r[0].words.count == 2)
    }

    @Test func addSP() {
        // ADD R0, SP → 060006
        let r = dis([0o060006])
        #expect(r[0].mnemonic == "ADD")
        #expect(r[0].operands == "R0, SP")
    }

    @Test func sub() {
        // SUB R1, R2 → 160102
        let r = dis([0o160102])
        #expect(r[0].mnemonic == "SUB")
        #expect(r[0].operands == "R1, R2")
    }

    @Test func movbRegReg() {
        // MOVB R0, R1 → 110001
        let r = dis([0o110001])
        #expect(r[0].mnemonic == "MOVB")
        #expect(r[0].operands == "R0, R1")
    }

    // MARK: - Branches

    @Test func brForward() {
        // BR offset=2 (4 bytes forward) at 0o1000 → target 0o1006
        // word: BR base 000400 | offset 002 = 000402
        // after opcode pc = 0o1002; target = 0o1002 + 2*2 = 0o1006
        let r = dis([0o000402])
        #expect(r[0].mnemonic == "BR")
        #expect(r[0].operands == "001006")
    }

    @Test func bneBackward() {
        // BNE with signed offset -2 (=376 octal) → target = pc - 2 bytes
        // BNE base = 001000, offset = 0o376 (Int8 = -2)
        // after opcode pc = 0o1002; target = 0o1002 + 2*(-2) = 0o776
        let word: UInt16 = 0o001000 | 0o376
        let r = dis([word])
        #expect(r[0].mnemonic == "BNE")
        #expect(r[0].operands == "000776")
    }

    @Test func bcc() {
        let r = dis([0o103002])  // BCC offset 2 → target = 0o1002 + 4 = 0o1006
        #expect(r[0].mnemonic == "BCC")
    }

    @Test func branchWithSymbol() {
        let syms: [UInt16: String] = [0o1006: "LOOP"]
        let r = disassemble(words: [0o000402], baseAddress: 0o1000, symbols: syms)
        #expect(r[0].operands == "LOOP")
    }

    // MARK: - JSR / SOB

    @Test func jsrPC() {
        // JSR PC, @(R2)+ → 004237 (base 004000 | PC<<6 | mode3/R2)
        // reg=7(PC) → 7<<6 = 0o700; dst = mode3/R2 = 0o32 → 0o004000|0o700|0o032 = 0o004732
        let r = dis([0o004732])
        #expect(r[0].mnemonic == "JSR")
        #expect(r[0].operands == "PC, @(R2)+")
    }

    @Test func jsrR1Immediate() {
        // JSR R1, #n → reg=1, dst=mode2/R7=0o27
        // 0o004000 | (1<<6) | 0o27 = 0o004000 | 0o100 | 0o027 = 0o004127
        let r = dis([0o004127, 0o001234])
        #expect(r[0].mnemonic == "JSR")
        #expect(r[0].operands == "R1, #001234")
    }

    @Test func sob() {
        // SOB R2, 2 words back; at 0o1006, target=0o1004
        // after opcode pc = 0o1010; target = 0o1010 - 2*2 = 0o1004
        let r = disassemble(words: [0o077202], baseAddress: 0o1006)
        #expect(r[0].mnemonic == "SOB")
        #expect(r[0].operands == "R2, 001004")
    }

    // MARK: - EIS / FIS

    @Test func mul() {
        // MUL R1, R2 → 070102 (MUL base 070000 | R1<<6 | mode0/R2)
        // 0o070000 | (1 << 6) | 2 = 0o070000 | 0o100 | 0o002 = 0o070102
        let r = dis([0o070102])
        #expect(r[0].mnemonic == "MUL")
        #expect(r[0].operands == "R1, R2")
    }

    @Test func xor() {
        // XOR R0, R3 → 074003
        let r = dis([0o074003])
        #expect(r[0].mnemonic == "XOR")
        #expect(r[0].operands == "R0, R3")
    }

    @Test func fadd() {
        // FADD R2 → 075002
        let r = dis([0o075002])
        #expect(r[0].mnemonic == "FADD")
        #expect(r[0].operands == "R2")
    }

    // MARK: - TRAP / EMT / MARK

    @Test func emt() {
        // EMT 12 (octal) → 104014
        let r = dis([0o104014])
        #expect(r[0].mnemonic == "EMT")
        #expect(r[0].operands == "14")
    }

    @Test func trap() {
        // TRAP 0 → 104400
        let r = dis([0o104400])
        #expect(r[0].mnemonic == "TRAP")
        #expect(r[0].operands == "0")
    }

    @Test func mark() {
        // MARK 6 → 006406
        let r = dis([0o006406])
        #expect(r[0].mnemonic == "MARK")
        #expect(r[0].operands == "6")
    }

    // MARK: - PC-relative operands

    @Test func pcRelativeLoad() {
        // MOV LABEL, R0 — mode6/R7 (field 067) src, mode0/R0 (field 0) dst
        // opcode: 0o010000 | (0o67 << 6) | 0 = 0o016700
        // ext word at 0o1002: disp = 0
        // target = extPC_after + 0 = (0o1002 + 2) + 0 = 0o1004
        let r = dis([0o016700, 0o000000])
        #expect(r[0].mnemonic == "MOV")
        #expect(r[0].operands == "001004, R0")
    }

    @Test func pcRelativeLoadWithDisp() {
        // Same instruction, disp = 4 → target = 0o1004 + 4 = 0o1010
        let r = dis([0o016700, 0o000004])
        #expect(r[0].operands == "001010, R0")
    }

    @Test func pcRelativeNegativeDisp() {
        // disp = 0o177774 (= -4 signed) → target = 0o1004 - 4 = 0o1000
        let r = dis([0o016700, 0o177774])
        #expect(r[0].operands == "001000, R0")
    }

    // MARK: - Unknown / .WORD

    @Test func unknownWord() {
        // 0o000017 is in the reserved range (000010–000037)
        let r = dis([0o000017])
        #expect(r[0].mnemonic == ".WORD")
        #expect(r[0].operands == "000017")
    }

    // MARK: - Multi-instruction sequence

    @Test func sequence() {
        // MOV #377, R0 ; HALT
        let r = dis([0o012700, 0o000377, 0o000000])
        #expect(r.count == 2)
        #expect(r[0].mnemonic == "MOV")
        #expect(r[1].mnemonic == "HALT")
        #expect(r[0].address == 0o1000)
        #expect(r[1].address == 0o1004)  // MOV consumed 2 words = 4 bytes
    }

    // MARK: - Listing line format

    @Test func listingLineOneWord() {
        let r = dis([0o010001])
        let line = r[0].listingLine
        #expect(line.hasPrefix("001000"))
        #expect(line.contains("010001"))
        #expect(line.contains("MOV"))
        #expect(line.contains("R0, R1"))
    }

    @Test func listingLineTwoWords() {
        let r = dis([0o012700, 0o000377])
        let line = r[0].listingLine
        #expect(line.contains("012700"))
        #expect(line.contains("000377"))
        #expect(line.contains("MOV"))
        #expect(line.contains("#000377"))
    }

    // MARK: - ODT Parser

    @Test func parseODTFormat() {
        let input = "001000/ 012700\n001002/ 000377\n001004/ 000000\n"
        let (words, base) = parseODTInput(input)
        #expect(base == 0o001000)
        #expect(words == [0o012700, 0o000377, 0o000000])
    }

    @Test func parseODTWithGarbage() {
        let input = "001000/ 012700  <- echoed\nsome garbage\n001002/ 000377\n"
        let (words, base) = parseODTInput(input)
        #expect(base == 0o001000)
        #expect(words == [0o012700, 0o000377])
    }

    @Test func parseOctFileFormat() {
        let input = "@001000\n012700\n000377\n000000\n"
        let (words, base) = parseODTInput(input)
        #expect(base == 0o001000)
        #expect(words == [0o012700, 0o000377, 0o000000])
    }

    @Test func parseBareWords() {
        let input = "012700\n000377\n"
        let (words, base) = parseODTInput(input)
        #expect(base == 0o001000)  // default
        #expect(words == [0o012700, 0o000377])
    }

    @Test func parseEmptyInput() {
        let (words, base) = parseODTInput("")
        #expect(base == 0o001000)
        #expect(words.isEmpty)
    }

    @Test func parseODTWithComments() {
        let input = "; comment line\n001000/ 012700\n; another comment\n001002/ 000377\n"
        let (words, _) = parseODTInput(input)
        #expect(words == [0o012700, 0o000377])
    }
}

// MARK: - Helper

private func dis(_ words: [UInt16]) -> [DisassembledInstruction] {
    disassemble(words: words, baseAddress: 0o1000)
}
