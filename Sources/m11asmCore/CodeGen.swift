// CodeGen.swift — Pass 2: evaluate expressions and emit [UInt16]

// MARK: - Entry point

/// Encode every statement in `program` into a flat word array.
/// Words are in instruction-stream order starting at `program.origin`.
/// All symbol references must be resolved; remaining errors go to `diagnostics`.
public func assemble(program: ParsedProgram,
                     diagnostics: inout DiagnosticEngine) -> [UInt16] {
    var words: [UInt16] = []
    for stmt in program.statements {
        do {
            try emit(stmt: stmt, symbols: program.symbols, into: &words)
        } catch let e as CodeGenError {
            diagnostics.error(at: stmt.location, e.message)
        } catch {
            diagnostics.error(at: stmt.location, error.localizedDescription)
        }
    }
    return words
}

// MARK: - Internal error type

private struct CodeGenError: Error {
    let message: String
}

// MARK: - Emit one statement

private func emit(stmt: Statement, symbols: SymbolTable, into words: inout [UInt16]) throws {
    let base = stmt.descriptor.base
    let addr = stmt.address

    switch stmt.operands {

    case .none:
        words.append(base)

    case .single(let op):
        let enc = op.encode(extensionWordAddress: addr &+ 2)
        words.append(base | enc.field)
        if let x = enc.extensionExpr {
            words.append(try eval(x, symbols: symbols, lc: addr, at: stmt.location))
        }

    case .double(let src, let dst):
        let srcEnc = src.encode(extensionWordAddress: addr &+ 2)
        let dstOff = UInt16(src.hasExtensionWord ? 2 : 0)
        let dstEnc = dst.encode(extensionWordAddress: addr &+ 2 &+ dstOff)
        words.append(base | (srcEnc.field << 6) | dstEnc.field)
        if let x = srcEnc.extensionExpr {
            words.append(try eval(x, symbols: symbols, lc: addr, at: stmt.location))
        }
        if let x = dstEnc.extensionExpr {
            words.append(try eval(x, symbols: symbols, lc: addr, at: stmt.location))
        }

    case .branch(let target):
        let tgt = try eval(target, symbols: symbols, lc: addr, at: stmt.location)
        let pc  = addr &+ 2
        // Byte offset = (target - pc) must be even and fit in [-256, 254].
        let raw = Int(tgt) - Int(pc)
        guard raw & 1 == 0 else {
            throw CodeGenError(message: "branch target is not word-aligned")
        }
        let wordOff = raw / 2
        guard wordOff >= -128 && wordOff <= 127 else {
            throw CodeGenError(message: "branch target out of range (\(wordOff) words from PC)")
        }
        words.append(base | (UInt16(bitPattern: Int16(wordOff)) & 0xFF))

    case .regOnly(let reg):
        words.append(base | UInt16(reg))

    case .regOperand(let reg, let op):
        let enc = op.encode(extensionWordAddress: addr &+ 2)
        words.append(base | (UInt16(reg) << 6) | enc.field)
        if let x = enc.extensionExpr {
            words.append(try eval(x, symbols: symbols, lc: addr, at: stmt.location))
        }

    case .regExpr(let reg, let target):
        // SOB: backward-only branch, offset in words (1-63).
        let tgt = try eval(target, symbols: symbols, lc: addr, at: stmt.location)
        let pc  = addr &+ 2
        let back = Int(pc) - Int(tgt)
        guard back > 0 && back & 1 == 0 else {
            throw CodeGenError(message: "SOB target must be a backward word-aligned address")
        }
        let off6 = back / 2
        guard off6 <= 63 else {
            throw CodeGenError(message: "SOB offset \(off6) exceeds 63-word limit")
        }
        words.append(base | (UInt16(reg) << 6) | UInt16(off6))

    case .trapN(let expr):
        words.append(base | (try eval(expr, symbols: symbols, lc: addr, at: stmt.location)))
    }
}

// MARK: - Expression evaluator shim

private func eval(_ expr: Expression,
                  symbols: SymbolTable,
                  lc: UInt16,
                  at loc: SourceLocation) throws -> UInt16 {
    do {
        return try expr.evaluate(symbols: symbols, locationCounter: lc)
    } catch ExpressionError.undefinedSymbol(let name) {
        throw CodeGenError(message: "undefined symbol '\(name)'")
    } catch ExpressionError.divisionByZero {
        throw CodeGenError(message: "division by zero in expression")
    } catch {
        throw CodeGenError(message: error.localizedDescription)
    }
}
