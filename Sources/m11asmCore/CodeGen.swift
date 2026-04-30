// CodeGen.swift — Pass 2: evaluate expressions and emit bytes

// MARK: - Entry point

/// Encode every item in `program` into a flat byte array (little-endian).
/// Bytes are in address order starting at `program.origin`.
public func assemble(program: ParsedProgram,
                     diagnostics: inout DiagnosticEngine) -> [UInt8] {
    var bytes: [UInt8] = []
    for item in program.items {
        do {
            switch item {
            case .instruction(let stmt):
                try emitInstruction(stmt: stmt, symbols: program.symbols, into: &bytes)
            case .directive(let dir):
                try emitDirective(dir: dir, symbols: program.symbols, into: &bytes)
            }
        } catch let e as CodeGenError {
            diagnostics.error(at: e.location, e.message)
        } catch {
            let loc: SourceLocation
            if case .instruction(let s) = item { loc = s.location }
            else if case .directive(let d) = item { loc = d.location }
            else { loc = .unknown }
            diagnostics.error(at: loc, error.localizedDescription)
        }
    }
    return bytes
}

// MARK: - Internal error type

private struct CodeGenError: Error {
    let location: SourceLocation
    let message:  String
}

// MARK: - Instruction emitter

private func emitInstruction(stmt: Statement, symbols: SymbolTable,
                              into bytes: inout [UInt8]) throws {
    let base = stmt.descriptor.base
    let addr = stmt.address

    func evalExpr(_ expr: Expression, lc: UInt16 = addr) throws -> UInt16 {
        try eval(expr, symbols: symbols, lc: lc, at: stmt.location)
    }

    switch stmt.operands {

    case .none:
        emitWord(base, into: &bytes)

    case .single(let op):
        let enc = op.encode(extensionWordAddress: addr &+ 2)
        emitWord(base | enc.field, into: &bytes)
        if let x = enc.extensionExpr { emitWord(try evalExpr(x), into: &bytes) }

    case .double(let src, let dst):
        let srcEnc = src.encode(extensionWordAddress: addr &+ 2)
        let dstOff = UInt16(src.hasExtensionWord ? 2 : 0)
        let dstEnc = dst.encode(extensionWordAddress: addr &+ 2 &+ dstOff)
        emitWord(base | (srcEnc.field << 6) | dstEnc.field, into: &bytes)
        if let x = srcEnc.extensionExpr { emitWord(try evalExpr(x), into: &bytes) }
        if let x = dstEnc.extensionExpr { emitWord(try evalExpr(x), into: &bytes) }

    case .branch(let target):
        let tgt    = try evalExpr(target)
        let pc     = addr &+ 2
        let raw    = Int(tgt) - Int(pc)
        guard raw & 1 == 0 else {
            throw CodeGenError(location: stmt.location, message: "branch target is not word-aligned")
        }
        let off = raw / 2
        guard off >= -128 && off <= 127 else {
            throw CodeGenError(location: stmt.location,
                               message: "branch target out of range (\(off) words from PC)")
        }
        emitWord(base | (UInt16(bitPattern: Int16(off)) & 0xFF), into: &bytes)

    case .regOnly(let reg):
        emitWord(base | UInt16(reg), into: &bytes)

    case .regOperand(let reg, let op):
        let enc = op.encode(extensionWordAddress: addr &+ 2)
        emitWord(base | (UInt16(reg) << 6) | enc.field, into: &bytes)
        if let x = enc.extensionExpr { emitWord(try evalExpr(x), into: &bytes) }

    case .regExpr(let reg, let target):
        let tgt  = try evalExpr(target)
        let pc   = addr &+ 2
        let back = Int(pc) - Int(tgt)
        guard back > 0 && back & 1 == 0 else {
            throw CodeGenError(location: stmt.location,
                               message: "SOB target must be a backward word-aligned address")
        }
        let off6 = back / 2
        guard off6 <= 63 else {
            throw CodeGenError(location: stmt.location,
                               message: "SOB offset \(off6) exceeds 63-word limit")
        }
        emitWord(base | (UInt16(reg) << 6) | UInt16(off6), into: &bytes)

    case .trapN(let expr):
        emitWord(base | (try evalExpr(expr)), into: &bytes)
    }
}

// MARK: - Directive emitter

private func emitDirective(dir: Directive, symbols: SymbolTable,
                            into bytes: inout [UInt8]) throws {
    switch dir.kind {

    case .word(let exprs):
        for expr in exprs {
            emitWord(try eval(expr, symbols: symbols, lc: dir.address, at: dir.location),
                     into: &bytes)
        }

    case .byte(let exprs):
        for expr in exprs {
            let val = try eval(expr, symbols: symbols, lc: dir.address, at: dir.location)
            bytes.append(UInt8(val & 0xFF))
        }

    case .blkw(let count):
        for _ in 0..<count { emitWord(0, into: &bytes) }

    case .blkb(let count):
        for _ in 0..<count { bytes.append(0) }

    case .ascii(let rawBytes, let nul):
        bytes.append(contentsOf: rawBytes)
        if nul { bytes.append(0) }

    case .even(let padded):
        if padded { bytes.append(0) }
    }
}

// MARK: - Helpers

private func emitWord(_ word: UInt16, into bytes: inout [UInt8]) {
    bytes.append(UInt8(word & 0xFF))
    bytes.append(UInt8(word >> 8))
}

private func eval(_ expr: Expression, symbols: SymbolTable,
                  lc: UInt16, at loc: SourceLocation) throws -> UInt16 {
    do {
        return try expr.evaluate(symbols: symbols, locationCounter: lc)
    } catch ExpressionError.undefinedSymbol(let name) {
        throw CodeGenError(location: loc, message: "undefined symbol '\(name)'")
    } catch ExpressionError.divisionByZero {
        throw CodeGenError(location: loc, message: "division by zero in expression")
    } catch {
        throw CodeGenError(location: loc, message: error.localizedDescription)
    }
}
