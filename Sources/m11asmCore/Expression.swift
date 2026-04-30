// Expression.swift — AST for assembler arithmetic expressions and evaluator

public indirect enum Expression: Sendable, Equatable {
    case literal(UInt16)
    case symbol(String)
    case locationCounter              // . (current PC / location counter)

    case add     (Expression, Expression)
    case subtract(Expression, Expression)
    case multiply(Expression, Expression)
    case divide  (Expression, Expression)
    case negate  (Expression)
    case bitwiseOr (Expression, Expression)  // !
    case bitwiseAnd(Expression, Expression)  // &
}

// MARK: - Evaluation errors

public enum ExpressionError: Error, Sendable, Equatable {
    case undefinedSymbol(String)
    case divisionByZero
}

// MARK: - Evaluator

extension Expression {
    /// Evaluate the expression to a 16-bit value.
    /// All arithmetic wraps (mod 65536). Undefined symbols throw.
    public func evaluate(symbols: SymbolTable, locationCounter pc: UInt16) throws -> UInt16 {
        switch self {
        case .literal(let v):
            return v

        case .locationCounter:
            return pc

        case .symbol(let name):
            switch symbols.lookup(name) {
            case .absolute(let v): return v
            case .undefined:       throw ExpressionError.undefinedSymbol(name)
            }

        case .add(let l, let r):
            return try l.evaluate(symbols: symbols, locationCounter: pc) &+
                       r.evaluate(symbols: symbols, locationCounter: pc)

        case .subtract(let l, let r):
            return try l.evaluate(symbols: symbols, locationCounter: pc) &-
                       r.evaluate(symbols: symbols, locationCounter: pc)

        case .multiply(let l, let r):
            return try l.evaluate(symbols: symbols, locationCounter: pc) &*
                       r.evaluate(symbols: symbols, locationCounter: pc)

        case .divide(let l, let r):
            let divisor = try r.evaluate(symbols: symbols, locationCounter: pc)
            guard divisor != 0 else { throw ExpressionError.divisionByZero }
            return try l.evaluate(symbols: symbols, locationCounter: pc) / divisor

        case .negate(let e):
            return try 0 &- e.evaluate(symbols: symbols, locationCounter: pc)

        case .bitwiseOr(let l, let r):
            return try l.evaluate(symbols: symbols, locationCounter: pc) |
                       r.evaluate(symbols: symbols, locationCounter: pc)

        case .bitwiseAnd(let l, let r):
            return try l.evaluate(symbols: symbols, locationCounter: pc) &
                       r.evaluate(symbols: symbols, locationCounter: pc)
        }
    }

    /// Returns true if the expression can be fully evaluated without symbol look-up.
    public var isConstant: Bool {
        switch self {
        case .literal:           return true
        case .locationCounter:   return false
        case .symbol:            return false
        case .negate(let e):     return e.isConstant
        case .add(let l, let r),
             .subtract(let l, let r),
             .multiply(let l, let r),
             .divide(let l, let r),
             .bitwiseOr(let l, let r),
             .bitwiseAnd(let l, let r):
            return l.isConstant && r.isConstant
        }
    }
}
