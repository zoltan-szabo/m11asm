// Parser.swift — Pass 1: build symbol table and statement IR

// MARK: - Directive

public struct Directive: Sendable {
    public let address:  UInt16
    public let location: SourceLocation
    public let kind:     DirectiveKind
}

public enum DirectiveKind: Sendable {
    case word([Expression])
    case byte([Expression])
    case blkw(UInt16)
    case blkb(UInt16)
    case ascii([UInt8], nullTerminated: Bool)
    case even(padded: Bool)
}

extension Directive {
    /// Byte count this directive contributes to the location counter.
    public var byteCount: UInt16 {
        switch kind {
        case .word(let v):            return UInt16(v.count) * 2
        case .byte(let v):            return UInt16(v.count)
        case .blkw(let n):            return n * 2
        case .blkb(let n):            return n
        case .ascii(let b, let nt):   return UInt16(b.count) + (nt ? 1 : 0)
        case .even(let pad):          return pad ? 1 : 0
        }
    }
}

// MARK: - Source item

public enum SourceItem: Sendable {
    case instruction(Statement)
    case directive(Directive)
}

// MARK: - Statement operand payload

public enum StatementOperands: Sendable {
    case none
    case single(OperandMode)
    case double(OperandMode, OperandMode)
    case branch(Expression)
    case regOnly(Int)
    case regOperand(Int, OperandMode)
    case regExpr(Int, Expression)
    case trapN(Expression)
}

extension StatementOperands {
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

public struct Statement: Sendable {
    public let location:   SourceLocation
    public let address:    UInt16
    public let descriptor: InstructionDescriptor
    public let operands:   StatementOperands
}

// MARK: - Parsed program

public struct ParsedProgram: Sendable {
    public let items:   [SourceItem]
    public let symbols: SymbolTable
    public let origin:  UInt16

    /// All instruction statements in order (directives filtered out).
    public var statements: [Statement] {
        items.compactMap {
            guard case .instruction(let s) = $0 else { return nil }
            return s
        }
    }
}

// MARK: - Pass 1 entry point

public func parse(tokens: [Located<Token>],
                  origin: UInt16 = 0,
                  diagnostics: inout DiagnosticEngine) -> ParsedProgram {
    var stream    = TokenStream(tokens)
    var lc        = origin
    var symbols   = SymbolTable()
    var items:    [SourceItem] = []
    var condStack: [Bool] = []    // true = this level is currently assembling

    func assembling() -> Bool { !condStack.contains(false) }

    while stream.peek() != .eof {
        stream.skipNewlines()
        guard stream.peek() != .eof else { break }
        let lineLoc = stream.currentLocation

        // ── Conditional-assembly delimiters (processed regardless of active state) ─────

        if case .symbol(let s) = stream.peek(), s == ".IF" {
            stream.consume()
            if assembling() {
                do {
                    condStack.append(try evalIfCondition(stream: &stream, symbols: symbols, lc: lc))
                } catch let e as ParseError {
                    diagnostics.error(at: e.location, e.message)
                    condStack.append(false)
                } catch {
                    diagnostics.error(at: lineLoc, error.localizedDescription)
                    condStack.append(false)
                }
            } else {
                condStack.append(false)   // nested IF inside false block
                skipToEOL(stream: &stream)
            }
            skipToEOL(stream: &stream)
            continue
        }

        if case .symbol(let s) = stream.peek(), s == ".ENDC" {
            stream.consume()
            if condStack.isEmpty {
                diagnostics.error(at: lineLoc, ".ENDC without matching .IF")
            } else {
                condStack.removeLast()
            }
            skipToEOL(stream: &stream)
            continue
        }

        // ── Skip line if inside a false conditional block ────────────────────────────

        guard assembling() else { skipToEOL(stream: &stream); continue }

        // ── .END — stop assembly ──────────────────────────────────────────────────────

        if case .symbol(let s) = stream.peek(), s == ".END" { break }

        // ── . = expr — set location counter ──────────────────────────────────────────

        if stream.peek() == .dot && stream.peek(1) == .equals {
            stream.consume(); stream.consume()
            do {
                lc = try parseExpression(stream: &stream).evaluate(symbols: symbols, locationCounter: lc)
            } catch {
                diagnostics.error(at: lineLoc, "invalid .= expression: \(error)")
            }
            skipToEOL(stream: &stream); continue
        }

        // ── sym = expr  or  sym == expr — equate ─────────────────────────────────────

        if case .symbol(let name) = stream.peek(),
           stream.peek(1) == .equals || stream.peek(1) == .doubleEquals {
            stream.consume(); stream.consume()
            do {
                let val = try parseExpression(stream: &stream)
                                .evaluate(symbols: symbols, locationCounter: lc)
                symbols.define(name, value: val, kind: .directAssign)
            } catch {
                diagnostics.error(at: lineLoc, "cannot evaluate equate '\(name)': \(error)")
            }
            skipToEOL(stream: &stream); continue
        }

        // ── Optional label: symbol ":" ────────────────────────────────────────────────

        if case .symbol(let name) = stream.peek(), stream.peek(1) == .colon {
            stream.consume(); stream.consume()
            symbols.define(name, value: lc, kind: .label)
        }

        // Label-only line
        if stream.peek() == .newline || stream.peek() == .eof { continue }

        // ── Directive (symbol starting with ".") ─────────────────────────────────────

        if case .symbol(let name) = stream.peek(), name.hasPrefix(".") {
            stream.consume()
            do {
                if let d = try parseDirective(name: name, address: lc, location: lineLoc,
                                              stream: &stream, symbols: &symbols) {
                    lc = lc &+ d.byteCount
                    items.append(.directive(d))
                }
            } catch let e as ParseError {
                diagnostics.error(at: e.location, e.message)
            } catch let e as LexError {
                diagnostics.error(at: e.location, e.message)
            } catch {
                diagnostics.error(at: lineLoc, error.localizedDescription)
            }
            skipToEOL(stream: &stream); continue
        }

        // ── Instruction mnemonic ──────────────────────────────────────────────────────

        guard case .symbol(let mnemonic) = stream.peek() else {
            diagnostics.error(at: lineLoc, "expected instruction or directive, got \(stream.peek())")
            skipToEOL(stream: &stream); continue
        }
        guard let desc = InstructionTable.lookup(mnemonic) else {
            diagnostics.error(at: stream.currentLocation, "unknown mnemonic '\(mnemonic)'")
            skipToEOL(stream: &stream); continue
        }
        stream.consume()

        do {
            let ops = try parseOperands(format: desc.format, stream: &stream)
            items.append(.instruction(Statement(location: lineLoc, address: lc,
                                                descriptor: desc, operands: ops)))
            lc = lc &+ UInt16(ops.wordCount * 2)
        } catch let e as ParseError {
            diagnostics.error(at: e.location, e.message)
            skipToEOL(stream: &stream); continue
        } catch {
            diagnostics.error(at: lineLoc, error.localizedDescription)
            skipToEOL(stream: &stream); continue
        }

        if stream.peek() != .newline && stream.peek() != .eof {
            diagnostics.error(at: stream.currentLocation,
                              "unexpected token '\(stream.peek())' after operands")
            skipToEOL(stream: &stream)
        }
    }

    return ParsedProgram(items: items, symbols: symbols, origin: origin)
}

// MARK: - .IF condition evaluator

private func evalIfCondition(stream: inout TokenStream, symbols: SymbolTable, lc: UInt16) throws -> Bool {
    guard case .symbol(let cond) = stream.peek() else {
        throw ParseError(location: stream.currentLocation,
                         message: "expected condition keyword after .IF")
    }
    stream.consume()
    _ = try stream.expect(.comma)

    switch cond {
    case "DF":
        guard case .symbol(let name) = stream.peek() else {
            throw ParseError(location: stream.currentLocation,
                             message: "expected symbol name for .IF DF")
        }
        stream.consume()
        return symbols.isDefined(name)

    case "NDF":
        guard case .symbol(let name) = stream.peek() else {
            throw ParseError(location: stream.currentLocation,
                             message: "expected symbol name for .IF NDF")
        }
        stream.consume()
        return !symbols.isDefined(name)

    default:
        let val  = try parseExpression(stream: &stream).evaluate(symbols: symbols, locationCounter: lc)
        let signed = Int16(bitPattern: val)
        switch cond {
        case "EQ": return val == 0
        case "NE": return val != 0
        case "GT": return signed > 0
        case "LT": return signed < 0
        case "GE": return signed >= 0
        case "LE": return signed <= 0
        default:
            throw ParseError(location: stream.currentLocation,
                             message: "unknown .IF condition '\(cond)'")
        }
    }
}

// MARK: - Directive parser

private func parseDirective(name: String, address: UInt16, location: SourceLocation,
                             stream: inout TokenStream,
                             symbols: inout SymbolTable) throws -> Directive? {
    switch name {
    case ".WORD":
        let exprs = try parseExprList(stream: &stream)
        return Directive(address: address, location: location, kind: .word(exprs))

    case ".BYTE":
        let exprs = try parseExprList(stream: &stream)
        return Directive(address: address, location: location, kind: .byte(exprs))

    case ".BLKW":
        let n = try evalConstant(stream: &stream, symbols: symbols, lc: address, loc: location)
        return Directive(address: address, location: location, kind: .blkw(n))

    case ".BLKB":
        let n = try evalConstant(stream: &stream, symbols: symbols, lc: address, loc: location)
        return Directive(address: address, location: location, kind: .blkb(n))

    case ".ASCII":
        let bytes = try expectStringLiteral(stream: &stream, loc: location)
        return Directive(address: address, location: location, kind: .ascii(bytes, nullTerminated: false))

    case ".ASCIZ":
        let bytes = try expectStringLiteral(stream: &stream, loc: location)
        return Directive(address: address, location: location, kind: .ascii(bytes, nullTerminated: true))

    case ".EVEN":
        let padded = (address & 1) != 0
        return Directive(address: address, location: location, kind: .even(padded: padded))

    default:
        throw ParseError(location: location, message: "unknown directive '\(name)'")
    }
}

// MARK: - Directive parser helpers

private func parseExprList(stream: inout TokenStream) throws -> [Expression] {
    var list: [Expression] = [try parseExpression(stream: &stream)]
    while stream.match(.comma) {
        list.append(try parseExpression(stream: &stream))
    }
    return list
}

private func evalConstant(stream: inout TokenStream, symbols: SymbolTable,
                           lc: UInt16, loc: SourceLocation) throws -> UInt16 {
    let expr = try parseExpression(stream: &stream)
    do {
        return try expr.evaluate(symbols: symbols, locationCounter: lc)
    } catch ExpressionError.undefinedSymbol(let s) {
        throw ParseError(location: loc, message: "undefined symbol '\(s)' in constant expression")
    } catch ExpressionError.divisionByZero {
        throw ParseError(location: loc, message: "division by zero in constant expression")
    }
}

private func expectStringLiteral(stream: inout TokenStream, loc: SourceLocation) throws -> [UInt8] {
    if case .stringLiteral(let bytes) = stream.peek() {
        stream.consume()
        return bytes
    }
    throw ParseError(location: loc, message: "expected string literal")
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
        return .double(src, try parseOperand(stream: &stream))
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

private func consumeReg(stream: inout TokenStream) throws -> Int {
    let loc = stream.currentLocation
    guard case .symbol(let name) = stream.peek(), let reg = registerNumber(name) else {
        throw ParseError(location: loc,
                         message: "expected register name (R0-R7, SP, PC), got \(stream.peek())")
    }
    stream.consume()
    return reg
}

private func skipToEOL(stream: inout TokenStream) {
    while stream.peek() != .newline && stream.peek() != .eof { stream.consume() }
}
