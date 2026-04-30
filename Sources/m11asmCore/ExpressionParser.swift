// ExpressionParser.swift — token stream, expression parser, operand parser

// MARK: - Parse error

public struct ParseError: Error, Sendable, CustomStringConvertible {
    public let location: SourceLocation
    public let message:  String
    public var description: String { "\(location): error: \(message)" }
}

// MARK: - Token stream

/// A cursor into a flat token array with single-token lookahead.
/// Consumed by value (pass inout to parsers).
public struct TokenStream: Sendable {
    private let tokens: [Located<Token>]
    private var pos: Int = 0

    public init(_ tokens: [Located<Token>]) { self.tokens = tokens }

    private static let sentinelEOF = Located(Token.eof, at: .unknown)

    public var currentLocation: SourceLocation { tokens[safe: pos]?.location ?? .unknown }

    public func peek(_ offset: Int = 0) -> Token {
        tokens[safe: pos + offset]?.value ?? .eof
    }

    public func peekLocated(_ offset: Int = 0) -> Located<Token> {
        tokens[safe: pos + offset] ?? Self.sentinelEOF
    }

    @discardableResult
    public mutating func consume() -> Located<Token> {
        let t = peekLocated()
        if pos < tokens.count { pos += 1 }
        return t
    }

    public mutating func skipNewlines() {
        while peek() == .newline { consume() }
    }

    public mutating func match(_ token: Token) -> Bool {
        guard peek() == token else { return false }
        consume(); return true
    }

    public mutating func expect(_ token: Token) throws -> Located<Token> {
        if peek() == token { return consume() }
        throw ParseError(location: currentLocation,
                         message: "expected \(token), got \(peek())")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Expression parser

/// Parse a MACRO-11 expression.
/// Operators are left-to-right with equal precedence (MACRO-11 specification).
/// Stops when the next token is not an operator or is a delimiter (, ) \n EOF).
public func parseExpression(stream: inout TokenStream) throws -> Expression {
    // Unary minus
    if stream.match(.minus) {
        let loc = stream.currentLocation
        let prim = try parsePrimary(stream: &stream, loc: loc)
        return try applyBinaryOps(lhs: .negate(prim), stream: &stream)
    }
    let loc = stream.currentLocation
    let prim = try parsePrimary(stream: &stream, loc: loc)
    return try applyBinaryOps(lhs: prim, stream: &stream)
}

private func parsePrimary(stream: inout TokenStream, loc: SourceLocation) throws -> Expression {
    switch stream.peek() {
    case .integer(let v):
        stream.consume()
        return .literal(v)

    case .asciiChar(let c):
        stream.consume()
        return .literal(UInt16(c))

    case .dot:
        stream.consume()
        return .locationCounter

    case .symbol(let name):
        stream.consume()
        return .symbol(name)

    case .lparen:
        stream.consume()
        let inner = try parseExpression(stream: &stream)
        _ = try stream.expect(.rparen)
        return inner

    default:
        throw ParseError(location: loc, message: "expected expression, got \(stream.peek())")
    }
}

private func applyBinaryOps(lhs: Expression, stream: inout TokenStream) throws -> Expression {
    var result = lhs
    while true {
        let op = stream.peek()
        switch op {
        case .plus:      stream.consume(); result = .add      (result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        case .minus:     stream.consume(); result = .subtract  (result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        case .star:      stream.consume(); result = .multiply  (result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        case .slash:     stream.consume(); result = .divide    (result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        case .bang:      stream.consume(); result = .bitwiseOr (result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        case .ampersand: stream.consume(); result = .bitwiseAnd(result, try parsePrimary(stream: &stream, loc: stream.currentLocation))
        default: return result
        }
    }
}

// MARK: - Operand parser

/// Parse one PDP-11 addressing-mode operand from the token stream.
/// Consumes only the tokens that belong to this operand.
public func parseOperand(stream: inout TokenStream) throws -> OperandMode {
    let loc = stream.currentLocation

    // #expr → immediate
    if stream.match(.hash) {
        return .immediate(try parseExpression(stream: &stream))
    }

    // @... → indirect / deferred forms
    if stream.match(.at) {
        return try parseAfterAt(stream: &stream, loc: loc)
    }

    // -(Rn) → autoDecrement
    if stream.match(.minus) {
        _ = try stream.expect(.lparen)
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        return .autoDecrement(reg)
    }

    // (Rn) or (Rn)+ → registerDeferred / autoIncrement
    if stream.match(.lparen) {
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        if stream.match(.plus) { return .autoIncrement(reg) }
        return .registerDeferred(reg)
    }

    // Rn alone → register (mode 0)
    if case .symbol(let name) = stream.peek(), let reg = registerNumber(name) {
        stream.consume()
        return .register(reg)
    }

    // expr  or  expr(Rn)
    let expr = try parseExpression(stream: &stream)

    // expr(Rn) → index
    if stream.match(.lparen) {
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        return .index(expr, reg)
    }

    // label / expr alone → relative (PC-relative)
    return .relative(expr)
}

// Called after consuming '@'.
private func parseAfterAt(stream: inout TokenStream, loc: SourceLocation) throws -> OperandMode {

    // @#expr → absolute
    if stream.match(.hash) {
        return .absolute(try parseExpression(stream: &stream))
    }

    // @-(Rn) → autoDecrementDeferred
    if stream.match(.minus) {
        _ = try stream.expect(.lparen)
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        return .autoDecrementDeferred(reg)
    }

    // @(Rn)+ → autoIncrementDeferred
    if stream.match(.lparen) {
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        guard stream.match(.plus) else {
            throw ParseError(location: stream.currentLocation,
                             message: "expected '+' after @(Rn) for autoincrement deferred")
        }
        return .autoIncrementDeferred(reg)
    }

    // @expr or @expr(Rn)
    let expr = try parseExpression(stream: &stream)

    // @expr(Rn) → indexDeferred
    if stream.match(.lparen) {
        let reg = try parseRegisterOperand(stream: &stream, loc: stream.currentLocation)
        _ = try stream.expect(.rparen)
        return .indexDeferred(expr, reg)
    }

    // @label → relativeDeferred
    return .relativeDeferred(expr)
}

/// Consume a register-name token and return its number (0-7).
private func parseRegisterOperand(stream: inout TokenStream, loc: SourceLocation) throws -> Int {
    guard case .symbol(let name) = stream.peek(), let reg = registerNumber(name) else {
        throw ParseError(location: loc, message: "expected register name (R0-R7, SP, PC)")
    }
    stream.consume()
    return reg
}
