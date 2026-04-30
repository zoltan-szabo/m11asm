// Parser.swift — Pass 1: build symbol table and statement IR

// MARK: - Statement operand payload

/// Typed operand payload for each instruction format.
/// Separates the high-level encoding decision (what kind of operands) from the
/// concrete bit encoding done in pass 2.
public enum StatementOperands: Sendable {
    case none                              // HALT, NOP, RTI …
    case single(OperandMode)               // CLR, JMP, TST …
    case double(OperandMode, OperandMode)  // MOV src, dst; ADD src, dst …
    case branch(Expression)               // BR/BNE/… target — 8-bit offset in instr word
    case regOnly(Int)                      // RTS reg; FADD reg
    case regOperand(Int, OperandMode)      // JSR reg, dst; MUL reg, src
    case regExpr(Int, Expression)          // SOB reg, label — 6-bit backward offset
    case trapN(Expression)                 // EMT/TRAP/MARK/SPL n
}

extension StatementOperands {
    /// Number of 16-bit words emitted for this instruction (instruction word + extension words).
    public var wordCount: Int {
        switch self {
        case .none, .branch, .regOnly, .regExpr, .trapN:
            return 1
        case .single(let op):
            return 1 + (op.hasExtensionWord ? 1 : 0)
        case .double(let src, let dst):
            return 1 + (src.hasExtensionWord ? 1 : 0) + (dst.hasExtensionWord ? 1 : 0)
        case .regOperand(_, let op):
            return 1 + (op.hasExtensionWord ? 1 : 0)
        }
    }
}

// MARK: - Statement

/// One assembled instruction: its origin address, opcode descriptor, and operands.
public struct Statement: Sendable {
    public let location:   SourceLocation
    public let address:    UInt16
    public let descriptor: InstructionDescriptor
    public let operands:   StatementOperands
}

// MARK: - Parsed program

public struct ParsedProgram: Sendable {
    public let statements: [Statement]
    public let symbols:    SymbolTable
    public let origin:     UInt16
}

// MARK: - Pass 1 entry point

/// Parse a flat token stream into a `ParsedProgram`.
/// Errors are appended to `diagnostics`; parsing continues after each error.
/// Returns whatever statements could be successfully parsed.
public func parse(tokens: [Located<Token>],
                  origin: UInt16 = 0,
                  diagnostics: inout DiagnosticEngine) -> ParsedProgram {
    var stream  = TokenStream(tokens)
    var lc      = origin
    var symbols = SymbolTable()
    var stmts:  [Statement] = []

    while stream.peek() != .eof {
        stream.skipNewlines()
        guard stream.peek() != .eof else { break }

        let lineLoc = stream.currentLocation

        // .END — stop assembly
        if case .symbol(let s) = stream.peek(), s == ".END" { break }

        // Optional label:  symbol ":"
        var label: String? = nil
        if case .symbol(let name) = stream.peek(), stream.peek(1) == .colon {
            label = name
            stream.consume()  // symbol
            stream.consume()  // colon
            // Define label at current LC immediately — correct even for label-only lines
            // because LC won't change until an instruction is emitted below.
            symbols.define(label!, value: lc)
        }

        // Label-only line
        if stream.peek() == .newline || stream.peek() == .eof { continue }

        // Mnemonic
        guard case .symbol(let mnemonic) = stream.peek() else {
            diagnostics.error(at: lineLoc, "expected instruction mnemonic, got \(stream.peek())")
            skipToEOL(stream: &stream); continue
        }
        guard let desc = InstructionTable.lookup(mnemonic) else {
            diagnostics.error(at: stream.currentLocation, "unknown mnemonic '\(mnemonic)'")
            skipToEOL(stream: &stream); continue
        }
        stream.consume()

        // Parse operands, record statement, advance LC
        do {
            let ops  = try parseOperands(format: desc.format, stream: &stream)
            stmts.append(Statement(location: lineLoc, address: lc,
                                   descriptor: desc, operands: ops))
            lc = lc &+ UInt16(ops.wordCount * 2)
        } catch let e as ParseError {
            diagnostics.error(at: e.location, e.message)
            skipToEOL(stream: &stream); continue
        } catch {
            diagnostics.error(at: lineLoc, error.localizedDescription)
            skipToEOL(stream: &stream); continue
        }

        // Expect end-of-line
        if stream.peek() != .newline && stream.peek() != .eof {
            diagnostics.error(at: stream.currentLocation,
                              "unexpected token '\(stream.peek())' after operands")
            skipToEOL(stream: &stream)
        }
    }

    return ParsedProgram(statements: stmts, symbols: symbols, origin: origin)
}

// MARK: - Per-format operand parsing

private func parseOperands(format: InstructionFormat,
                           stream: inout TokenStream) throws -> StatementOperands {
    switch format {
    case .noOperand:
        return .none

    case .singleOperand:
        return .single(try parseOperand(stream: &stream))

    case .doubleOperand:
        let src = try parseOperand(stream: &stream)
        _ = try stream.expect(.comma)
        let dst = try parseOperand(stream: &stream)
        return .double(src, dst)

    case .branch:
        return .branch(try parseExpression(stream: &stream))

    case .rts, .fisReg:
        return .regOnly(try consumeReg(stream: &stream))

    case .jsr:
        let reg = try consumeReg(stream: &stream)
        _ = try stream.expect(.comma)
        return .regOperand(reg, try parseOperand(stream: &stream))

    case .eisRegSrc:
        let reg = try consumeReg(stream: &stream)
        _ = try stream.expect(.comma)
        return .regOperand(reg, try parseOperand(stream: &stream))

    case .sob:
        let reg = try consumeReg(stream: &stream)
        _ = try stream.expect(.comma)
        return .regExpr(reg, try parseExpression(stream: &stream))

    case .trapN, .markN, .splN:
        return .trapN(try parseExpression(stream: &stream))
    }
}

/// Consume the next token expecting a register name; return 0-7.
private func consumeReg(stream: inout TokenStream) throws -> Int {
    let loc = stream.currentLocation
    guard case .symbol(let name) = stream.peek(), let reg = registerNumber(name) else {
        throw ParseError(location: loc,
                         message: "expected register name (R0-R7, SP, PC), got \(stream.peek())")
    }
    stream.consume()
    return reg
}

/// Advance the stream to the next newline or EOF without recording an error.
private func skipToEOL(stream: inout TokenStream) {
    while stream.peek() != .newline && stream.peek() != .eof { stream.consume() }
}
