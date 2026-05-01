// Disassembler.swift — PDP-11/DCJ-11 instruction disassembler

// MARK: - Public Output Type

public struct DisassembledInstruction: Sendable {
    public let address:  UInt16
    public let words:    [UInt16]   // 1–3 words consumed
    public let mnemonic: String
    public let operands: String     // empty string for no-operand instructions

    /// One formatted listing line.
    /// Columns: address  w0  w1  w2  mnemonic  operands
    /// Blank word columns are padded with spaces for alignment.
    public var listingLine: String {
        let a  = String(format: "%08o", address)
        let w0 = String(format: "%06o", words[0])
        let w1 = words.count > 1 ? String(format: "%06o", words[1]) : "      "
        let w2 = words.count > 2 ? String(format: "%06o", words[2]) : "      "
        let mn = mnemonic.padding(toLength: 6, withPad: " ", startingAt: 0)
        return operands.isEmpty
            ? "\(a) \(w0)  \(w1)  \(w2)  \(mn)"
            : "\(a) \(w0)  \(w1)  \(w2)  \(mn)  \(operands)"
    }
}

// MARK: - Disassemble

/// Disassemble an array of 16-bit words starting at `baseAddress`.
/// `symbols` maps addresses to label names used in branch/operand display.
public func disassemble(words: [UInt16],
                        baseAddress: UInt16,
                        symbols: [UInt16: String] = [:]) -> [DisassembledInstruction] {
    var result: [DisassembledInstruction] = []
    var i  = 0
    var pc = baseAddress
    while i < words.count {
        let startI  = i
        let instrPC = pc
        let (mn, ops) = decodeWord(words: words, i: &i, pc: &pc, symbols: symbols)
        result.append(DisassembledInstruction(
            address:  instrPC,
            words:    Array(words[startI ..< i]),
            mnemonic: mn,
            operands: ops
        ))
    }
    return result
}

// MARK: - ODT Input Parser

/// Parse ODT-format terminal output or m11asm `.oct` files into a word array.
///
/// Accepted line formats:
/// - `NNNNNN/ VVVVVV` — ODT open-address output (address / value)
/// - `@NNNNNN`        — m11asm `.oct` address directive
/// - `VVVVVV`         — bare 1–6 digit octal word (no address info)
/// - Lines with `;` prefix or unrecognised content are skipped.
///
/// The first address seen becomes `baseAddress`; subsequent words are appended
/// in order regardless of their ODT addresses.
public func parseODTInput(_ text: String) -> (words: [UInt16], baseAddress: UInt16) {
    var words:     [UInt16] = []
    var baseAddr:  UInt16   = 0o001000
    var foundAddr           = false

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix(";") { continue }

        // ODT format: NNNNNN/ VVVVVV  (value is the first octal run after the slash)
        if let slashIdx = line.firstIndex(of: "/") {
            let addrPart = String(line[line.startIndex ..< slashIdx])
                .trimmingCharacters(in: .whitespaces)
            let afterSlash = String(line[line.index(after: slashIdx)...])
                .trimmingCharacters(in: .whitespaces)
            let valStr = String(afterSlash.prefix(while: { "01234567".contains($0) }))
            if !valStr.isEmpty,
               let addr = UInt16(addrPart, radix: 8),
               let val  = UInt16(valStr,   radix: 8) {
                if !foundAddr { baseAddr = addr; foundAddr = true }
                words.append(val)
            }
            continue
        }

        // m11asm .oct address directive
        if line.hasPrefix("@") {
            if let addr = UInt16(String(line.dropFirst()), radix: 8) {
                baseAddr = addr; foundAddr = true
            }
            continue
        }

        // Bare octal word
        let bareStr = String(line.prefix(while: { "01234567".contains($0) }))
        if bareStr.count >= 1, bareStr.count <= 6, let val = UInt16(bareStr, radix: 8) {
            words.append(val)
        }
    }
    return (words, baseAddr)
}

// MARK: - Decode Table

private struct DecodeEntry: Sendable {
    let mask:     UInt16
    let match:    UInt16
    let mnemonic: String
    let format:   InstructionFormat
}

// Built once at startup, sorted most-specific first.
private let decodeTable: [DecodeEntry] = {
    var entries: [DecodeEntry] = []

    func add(_ mask: UInt16, _ match: UInt16,
             _ mnemonic: String, _ fmt: InstructionFormat) {
        guard !entries.contains(where: { $0.mask == mask && $0.match == match })
        else { return }
        entries.append(DecodeEntry(mask: mask, match: match,
                                   mnemonic: mnemonic, format: fmt))
    }
    func d(_ mn: String) -> InstructionDescriptor? { InstructionTable.lookup(mn) }

    // Exact match (mask 177777): no-operand system + condition codes
    for mn in ["HALT","WAIT","RTI","BPT","IOT","RESET","RTT","MFPT",
               "NOP","CLC","CLV","CLZ","CLN","CCC","SEC","SEV","SEZ","SEN","SCC"] {
        if let x = d(mn) { add(0o177777, x.base, mn, .noOperand) }
    }
    // mask 177770: RTS, SPL, FIS
    if let x = d("RTS") { add(0o177770, x.base, "RTS", .rts)  }
    if let x = d("SPL") { add(0o177770, x.base, "SPL", .splN) }
    for mn in ["FADD","FSUB","FMUL","FDIV"] {
        if let x = d(mn) { add(0o177770, x.base, mn, .fisReg) }
    }
    // mask 177700: MARK + single-operand word + single-operand byte
    if let x = d("MARK") { add(0o177700, x.base, "MARK", .markN) }
    for mn in ["JMP","SWAB","CLR","COM","INC","DEC","NEG","ADC","SBC","TST",
               "ROR","ROL","ASR","ASL","MFPI","MTPI","SXT"] {
        if let x = d(mn) { add(0o177700, x.base, mn, .singleOperand) }
    }
    for mn in ["CLRB","COMB","INCB","DECB","NEGB","ADCB","SBCB","TSTB",
               "RORB","ROLB","ASRB","ASLB","MFPD","MTPD"] {
        if let x = d(mn) { add(0o177700, x.base, mn, .singleOperand) }
    }
    // mask 177400: branches + EMT/TRAP
    // BCC/BHIS share base 103000; BCS/BLO share 103400 — dedup keeps first.
    for mn in ["BR","BNE","BEQ","BGE","BLT","BGT","BLE",
               "BPL","BMI","BHI","BLOS","BVC","BVS","BCC","BHIS","BCS","BLO"] {
        if let x = d(mn) { add(0o177400, x.base, mn, .branch) }
    }
    for mn in ["EMT","TRAP"] {
        if let x = d(mn) { add(0o177400, x.base, mn, .trapN) }
    }
    // mask 177000: JSR, SOB, EIS
    if let x = d("JSR") { add(0o177000, x.base, "JSR", .jsr) }
    if let x = d("SOB") { add(0o177000, x.base, "SOB", .sob) }
    for mn in ["MUL","DIV","ASH","ASHC","XOR"] {
        if let x = d(mn) { add(0o177000, x.base, mn, .eisRegSrc) }
    }
    // mask 170000: double-operand
    for mn in ["MOV","CMP","BIT","BIC","BIS","ADD","SUB",
               "MOVB","CMPB","BITB","BICB","BISB"] {
        if let x = d(mn) { add(0o170000, x.base, mn, .doubleOperand) }
    }

    return entries.sorted { $0.mask > $1.mask }
}()

// MARK: - Core Decoder

private func decodeWord(words: [UInt16], i: inout Int,
                         pc: inout UInt16,
                         symbols: [UInt16: String]) -> (String, String) {
    let word = words[i]; i += 1
    pc = pc &+ 2                        // pc now points past the opcode word

    guard let entry = decodeTable.first(where: { (word & $0.mask) == $0.match }) else {
        return (".WORD", String(format: "%06o", word))
    }

    // extPC tracks the address of the next extension word as operands are consumed.
    var extPC = pc
    let mn    = entry.mnemonic

    switch entry.format {

    case .noOperand:
        return (mn, "")

    case .singleOperand:
        let ops = operand(field: word & 0o077, words: words, i: &i,
                          extPC: &extPC, symbols: symbols)
        pc = extPC
        return (mn, ops)

    case .doubleOperand:
        let src = operand(field: (word >> 6) & 0o077, words: words, i: &i,
                          extPC: &extPC, symbols: symbols)
        let dst = operand(field: word & 0o077, words: words, i: &i,
                          extPC: &extPC, symbols: symbols)
        pc = extPC
        return (mn, "\(src), \(dst)")

    case .branch:
        let off    = Int8(bitPattern: UInt8(word & 0xFF))
        let target = pc &+ UInt16(bitPattern: Int16(off) &* 2)
        return (mn, symbols[target] ?? String(format: "%06o", target))

    case .jsr:
        let reg = Int((word >> 6) & 7)
        let dst = operand(field: word & 0o077, words: words, i: &i,
                          extPC: &extPC, symbols: symbols)
        pc = extPC
        return (mn, "\(regName(reg)), \(dst)")

    case .rts:
        return (mn, regName(Int(word & 7)))

    case .sob:
        let r      = Int((word >> 6) & 7)
        let offset = Int(word & 0o077)
        let target = pc &- UInt16(offset * 2)
        return (mn, "\(regName(r)), \(String(format: "%06o", target))")

    case .eisRegSrc:
        let r   = Int((word >> 6) & 7)
        let src = operand(field: word & 0o077, words: words, i: &i,
                          extPC: &extPC, symbols: symbols)
        pc = extPC
        return (mn, "\(regName(r)), \(src)")

    case .fisReg:
        return (mn, regName(Int(word & 7)))

    case .trapN:
        return (mn, String(format: "%o", word & 0xFF))

    case .markN:
        return (mn, String(format: "%o", word & 0o077))

    case .splN:
        return (mn, "\(word & 7)")
    }
}

// MARK: - Operand Decoder

private func operand(field: UInt16, words: [UInt16], i: inout Int,
                     extPC: inout UInt16, symbols: [UInt16: String]) -> String {
    let mode = Int((field >> 3) & 7)
    let r    = Int(field & 7)
    let rn   = regName(r)

    switch mode {
    case 0: return rn
    case 1: return "(\(rn))"
    case 2:
        if r == 7 {
            let ext = nextWord(words, &i, &extPC)
            return "#\(String(format: "%06o", ext))"
        }
        return "(\(rn))+"
    case 3:
        if r == 7 {
            let ext = nextWord(words, &i, &extPC)
            return "@#\(symbols[ext] ?? String(format: "%06o", ext))"
        }
        return "@(\(rn))+"
    case 4: return "-(\(rn))"
    case 5: return "@-(\(rn))"
    case 6:
        let ext = nextWord(words, &i, &extPC)
        if r == 7 {
            // EA = extPC (already advanced past extension word) + signedDisp
            let target = extPC &+ UInt16(bitPattern: Int16(bitPattern: ext))
            return symbols[target] ?? String(format: "%06o", target)
        }
        return "\(String(format: "%06o", ext))(\(rn))"
    case 7:
        let ext = nextWord(words, &i, &extPC)
        if r == 7 {
            let target = extPC &+ UInt16(bitPattern: Int16(bitPattern: ext))
            return "@\(symbols[target] ?? String(format: "%06o", target))"
        }
        return "@\(String(format: "%06o", ext))(\(rn))"
    default:
        return "?"
    }
}

// Consume one extension word, advancing i and extPC.
private func nextWord(_ words: [UInt16], _ i: inout Int, _ extPC: inout UInt16) -> UInt16 {
    guard i < words.count else { return 0 }
    let w = words[i]; i += 1; extPC = extPC &+ 2
    return w
}

private func regName(_ r: Int) -> String {
    switch r {
    case 0: return "R0"; case 1: return "R1"; case 2: return "R2"; case 3: return "R3"
    case 4: return "R4"; case 5: return "R5"; case 6: return "SP"; case 7: return "PC"
    default: return "R\(r)"
    }
}
