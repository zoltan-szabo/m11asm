// InstructionTable.swift — opcode lookup and instruction format descriptors

// MARK: - Format

public enum InstructionFormat: Sendable, Equatable {
    case doubleOperand   // base | (src<<6) | dst        — MOV, ADD, CMP …
    case singleOperand   // base | dst                   — CLR, TST, JMP …
    case branch          // base | signedOffset8          — BR, BNE …
    case jsr             // base | (reg<<6) | dst        — JSR reg, dst
    case rts             // base | reg                   — RTS reg
    case sob             // base | (reg<<6) | offset6    — SOB reg, label
    case eisRegSrc       // base | (reg<<6) | src        — MUL, DIV, ASH, ASHC, XOR
    case fisReg          // base | reg                   — FADD, FSUB, FMUL, FDIV
    case noOperand       // base exactly                 — HALT, NOP, CLC …
    case trapN           // base | n  (n 0-255)          — EMT, TRAP
    case markN           // base | n  (n 0-63)           — MARK
    case splN            // base | n  (n 0-7)            — SPL
}

// MARK: - Descriptor

public struct InstructionDescriptor: Sendable {
    public let mnemonic:   String
    public let base:       UInt16
    public let format:     InstructionFormat

    public init(_ mnemonic: String, _ base: UInt16, _ format: InstructionFormat) {
        self.mnemonic = mnemonic
        self.base     = base
        self.format   = format
    }
}

// MARK: - Table

public enum InstructionTable {

    // All opcodes are in octal as documented in the PDP-11 / DCJ-11 manuals.
    private static let table: [String: InstructionDescriptor] = {
        var t: [String: InstructionDescriptor] = [:]
        func add(_ d: InstructionDescriptor) { t[d.mnemonic] = d }

        // Double-operand word
        add(.init("MOV",  0o010000, .doubleOperand))
        add(.init("CMP",  0o020000, .doubleOperand))
        add(.init("BIT",  0o030000, .doubleOperand))
        add(.init("BIC",  0o040000, .doubleOperand))
        add(.init("BIS",  0o050000, .doubleOperand))
        add(.init("ADD",  0o060000, .doubleOperand))
        add(.init("SUB",  0o160000, .doubleOperand))

        // Double-operand byte
        add(.init("MOVB", 0o110000, .doubleOperand))
        add(.init("CMPB", 0o120000, .doubleOperand))
        add(.init("BITB", 0o130000, .doubleOperand))
        add(.init("BICB", 0o140000, .doubleOperand))
        add(.init("BISB", 0o150000, .doubleOperand))

        // Single-operand word
        add(.init("JMP",  0o000100, .singleOperand))
        add(.init("SWAB", 0o000300, .singleOperand))
        add(.init("CLR",  0o005000, .singleOperand))
        add(.init("COM",  0o005100, .singleOperand))
        add(.init("INC",  0o005200, .singleOperand))
        add(.init("DEC",  0o005300, .singleOperand))
        add(.init("NEG",  0o005400, .singleOperand))
        add(.init("ADC",  0o005500, .singleOperand))
        add(.init("SBC",  0o005600, .singleOperand))
        add(.init("TST",  0o005700, .singleOperand))
        add(.init("ROR",  0o006000, .singleOperand))
        add(.init("ROL",  0o006100, .singleOperand))
        add(.init("ASR",  0o006200, .singleOperand))
        add(.init("ASL",  0o006300, .singleOperand))
        add(.init("MFPI", 0o006500, .singleOperand))
        add(.init("MTPI", 0o006600, .singleOperand))
        add(.init("SXT",  0o006700, .singleOperand))

        // Single-operand byte
        add(.init("CLRB", 0o105000, .singleOperand))
        add(.init("COMB", 0o105100, .singleOperand))
        add(.init("INCB", 0o105200, .singleOperand))
        add(.init("DECB", 0o105300, .singleOperand))
        add(.init("NEGB", 0o105400, .singleOperand))
        add(.init("ADCB", 0o105500, .singleOperand))
        add(.init("SBCB", 0o105600, .singleOperand))
        add(.init("TSTB", 0o105700, .singleOperand))
        add(.init("RORB", 0o106000, .singleOperand))
        add(.init("ROLB", 0o106100, .singleOperand))
        add(.init("ASRB", 0o106200, .singleOperand))
        add(.init("ASLB", 0o106300, .singleOperand))
        add(.init("MFPD", 0o106500, .singleOperand))
        add(.init("MTPD", 0o106600, .singleOperand))

        // Branches
        add(.init("BR",   0o000400, .branch))
        add(.init("BNE",  0o001000, .branch))
        add(.init("BEQ",  0o001400, .branch))
        add(.init("BGE",  0o002000, .branch))
        add(.init("BLT",  0o002400, .branch))
        add(.init("BGT",  0o003000, .branch))
        add(.init("BLE",  0o003400, .branch))
        add(.init("BPL",  0o100000, .branch))
        add(.init("BMI",  0o100400, .branch))
        add(.init("BHI",  0o101000, .branch))
        add(.init("BLOS", 0o101400, .branch))
        add(.init("BVC",  0o102000, .branch))
        add(.init("BVS",  0o102400, .branch))
        add(.init("BCC",  0o103000, .branch))
        add(.init("BHIS", 0o103000, .branch)) // alias for BCC
        add(.init("BCS",  0o103400, .branch))
        add(.init("BLO",  0o103400, .branch)) // alias for BCS

        // JSR / RTS / SOB / MARK
        add(.init("JSR",  0o004000, .jsr))
        add(.init("RTS",  0o000200, .rts))
        add(.init("SOB",  0o077000, .sob))
        add(.init("MARK", 0o006400, .markN))

        // EIS (built into DCJ-11)
        add(.init("MUL",  0o070000, .eisRegSrc))
        add(.init("DIV",  0o071000, .eisRegSrc))
        add(.init("ASH",  0o072000, .eisRegSrc))
        add(.init("ASHC", 0o073000, .eisRegSrc))
        add(.init("XOR",  0o074000, .eisRegSrc))

        // FIS (optional floating-point)
        add(.init("FADD", 0o075000, .fisReg))
        add(.init("FSUB", 0o075010, .fisReg))
        add(.init("FMUL", 0o075020, .fisReg))
        add(.init("FDIV", 0o075030, .fisReg))

        // Traps
        add(.init("EMT",  0o104000, .trapN))
        add(.init("TRAP", 0o104400, .trapN))

        // SPL
        add(.init("SPL",  0o000230, .splN))

        // No-operand: system
        add(.init("HALT",  0o000000, .noOperand))
        add(.init("WAIT",  0o000001, .noOperand))
        add(.init("RTI",   0o000002, .noOperand))
        add(.init("BPT",   0o000003, .noOperand))
        add(.init("IOT",   0o000004, .noOperand))
        add(.init("RESET", 0o000005, .noOperand))
        add(.init("RTT",   0o000006, .noOperand))
        add(.init("MFPT",  0o000007, .noOperand))

        // No-operand: condition codes
        add(.init("NOP",  0o000240, .noOperand))
        add(.init("CLC",  0o000241, .noOperand))
        add(.init("CLV",  0o000242, .noOperand))
        add(.init("CLZ",  0o000244, .noOperand))
        add(.init("CLN",  0o000250, .noOperand))
        add(.init("CCC",  0o000257, .noOperand))
        add(.init("SEC",  0o000261, .noOperand))
        add(.init("SEV",  0o000262, .noOperand))
        add(.init("SEZ",  0o000264, .noOperand))
        add(.init("SEN",  0o000270, .noOperand))
        add(.init("SCC",  0o000277, .noOperand))

        return t
    }()

    public static func lookup(_ mnemonic: String) -> InstructionDescriptor? {
        table[mnemonic.uppercased()]
    }

    public static var allMnemonics: [String] { table.keys.sorted() }
}
