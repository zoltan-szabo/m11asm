import Testing
@testable import m11asmCore

// MARK: - Lexer tests

@Suite("Lexer") struct LexerTests {

    private func lex(_ src: String) throws -> [Token] {
        var lexer = Lexer(source: src)
        return try lexer.tokenize().map(\.value)
    }

    @Test func emptyInput() throws {
        #expect(try lex("") == [.eof])
    }

    @Test func whitespaceOnly() throws {
        #expect(try lex("   \t  ") == [.eof])
    }

    // MARK: Numbers — default radix is octal

    @Test func octalDefault() throws {
        #expect(try lex("177") == [.integer(0o177), .eof])
    }

    @Test func octalZero() throws {
        #expect(try lex("0") == [.integer(0), .eof])
    }

    @Test func decimalPrefix() throws {
        #expect(try lex("^D255") == [.integer(255), .eof])
    }

    @Test func octalExplicit() throws {
        #expect(try lex("^O377") == [.integer(0o377), .eof])
    }

    @Test func binaryPrefix() throws {
        #expect(try lex("^B1010") == [.integer(0b1010), .eof])
    }

    @Test func hexPrefix() throws {
        #expect(try lex("^XFF") == [.integer(0xFF), .eof])
    }

    @Test func hexPrefixLowercase() throws {
        #expect(try lex("^Xff") == [.integer(0xFF), .eof])
    }

    @Test func maxUInt16() throws {
        #expect(try lex("^XFFFF") == [.integer(0xFFFF), .eof])
    }

    // MARK: Character literals

    @Test func singleQuoteChar() throws {
        #expect(try lex("'A") == [.asciiChar(65), .eof])
    }

    @Test func singleQuoteSpace() throws {
        // 'digit after tick
        #expect(try lex("'0") == [.asciiChar(48), .eof])
    }

    @Test func caretAscii() throws {
        #expect(try lex("^A/A/") == [.asciiChar(65), .eof])
    }

    @Test func caretAsciiPipeDelim() throws {
        #expect(try lex("^A|Z|") == [.asciiChar(90), .eof])
    }

    // MARK: Symbols and directives

    @Test func simpleSymbol() throws {
        #expect(try lex("MOV") == [.symbol("MOV"), .eof])
    }

    @Test func symbolCaseNormalized() throws {
        #expect(try lex("mov") == [.symbol("MOV"), .eof])
    }

    @Test func directive() throws {
        #expect(try lex(".WORD") == [.symbol(".WORD"), .eof])
    }

    @Test func directiveLowercase() throws {
        #expect(try lex(".word") == [.symbol(".WORD"), .eof])
    }

    @Test func register() throws {
        #expect(try lex("R0") == [.symbol("R0"), .eof])
    }

    @Test func symbolWithDollar() throws {
        #expect(try lex("LOOP$") == [.symbol("LOOP$"), .eof])
    }

    // MARK: Local labels

    @Test func localLabelDef() throws {
        // "1$:" → symbol("1$") + colon
        #expect(try lex("1$:") == [.symbol("1$"), .colon, .eof])
    }

    @Test func localLabelRef() throws {
        #expect(try lex("1$") == [.symbol("1$"), .eof])
    }

    @Test func localLabelTwoDigit() throws {
        #expect(try lex("10$") == [.symbol("10$"), .eof])
    }

    // MARK: Standalone dot (location counter)

    @Test func dotAlone() throws {
        #expect(try lex(".") == [.dot, .eof])
    }

    @Test func dotInExpression() throws {
        // . + 2
        #expect(try lex(". + 2") == [.dot, .plus, .integer(2), .eof])
    }

    // MARK: Comments

    @Test func comment() throws {
        #expect(try lex("; full line comment") == [.eof])
    }

    @Test func commentAfterInstruction() throws {
        #expect(try lex("CLR R0 ; clear it") == [.symbol("CLR"), .symbol("R0"), .eof])
    }

    // MARK: Newlines

    @Test func newline() throws {
        #expect(try lex("\n") == [.newline, .eof])
    }

    @Test func crlfNewline() throws {
        #expect(try lex("\r\n") == [.newline, .eof])
    }

    @Test func multipleLines() throws {
        #expect(try lex("MOV\nCLR") == [.symbol("MOV"), .newline, .symbol("CLR"), .eof])
    }

    // MARK: Punctuation

    @Test func colonComma() throws {
        #expect(try lex(":,") == [.colon, .comma, .eof])
    }

    @Test func hashAt() throws {
        #expect(try lex("#@") == [.hash, .at, .eof])
    }

    @Test func equals() throws {
        #expect(try lex("=") == [.equals, .eof])
    }

    @Test func doubleEquals() throws {
        #expect(try lex("==") == [.doubleEquals, .eof])
    }

    @Test func parens() throws {
        #expect(try lex("()") == [.lparen, .rparen, .eof])
    }

    @Test func angles() throws {
        #expect(try lex("<>") == [.langle, .rangle, .eof])
    }

    // MARK: Full instruction lines

    @Test func movImmediate() throws {
        let tokens = try lex("MOV #177, R0")
        #expect(tokens == [.symbol("MOV"), .hash, .integer(0o177), .comma, .symbol("R0"), .eof])
    }

    @Test func labeledInstruction() throws {
        let tokens = try lex("LOOP: SOB R2, LOOP")
        #expect(tokens == [
            .symbol("LOOP"), .colon,
            .symbol("SOB"),
            .symbol("R2"), .comma, .symbol("LOOP"),
            .eof
        ])
    }

    @Test func indexedOperand() throws {
        let tokens = try lex("MOV 4(R1), R0")
        #expect(tokens == [
            .symbol("MOV"),
            .integer(4), .lparen, .symbol("R1"), .rparen, .comma,
            .symbol("R0"),
            .eof
        ])
    }

    @Test func dotWordDirective() throws {
        let tokens = try lex(".WORD ^D1000, ^D2000")
        #expect(tokens == [
            .symbol(".WORD"), .integer(1000), .comma, .integer(2000),
            .eof
        ])
    }

    @Test func equate() throws {
        let tokens = try lex("SIZE = ^D512")
        #expect(tokens == [.symbol("SIZE"), .equals, .integer(512), .eof])
    }
}

// MARK: - Expression evaluator tests

@Suite("Expression") struct ExpressionTests {

    private var symbols: SymbolTable = {
        var s = SymbolTable()
        s.define("FOO", value: 0o1000)
        s.define("BAR", value: 0o0010)
        return s
    }()

    @Test func literalEval() throws {
        let expr = Expression.literal(42)
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 42)
    }

    @Test func symbolEval() throws {
        let expr = Expression.symbol("FOO")
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0o1000)
    }

    @Test func locationCounter() throws {
        let expr = Expression.locationCounter
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0o1234) == 0o1234)
    }

    @Test func addEval() throws {
        let expr = Expression.add(.literal(10), .literal(5))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 15)
    }

    @Test func subtractEval() throws {
        let expr = Expression.subtract(.literal(10), .literal(3))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 7)
    }

    @Test func multiplyEval() throws {
        let expr = Expression.multiply(.literal(6), .literal(7))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 42)
    }

    @Test func divideEval() throws {
        let expr = Expression.divide(.literal(20), .literal(4))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 5)
    }

    @Test func divideByZero() throws {
        let expr = Expression.divide(.literal(1), .literal(0))
        #expect(throws: ExpressionError.divisionByZero) {
            try expr.evaluate(symbols: symbols, locationCounter: 0)
        }
    }

    @Test func negateEval() throws {
        let expr = Expression.negate(.literal(1))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0xFFFF)
    }

    @Test func bitwiseOrEval() throws {
        let expr = Expression.bitwiseOr(.literal(0o170), .literal(0o007))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0o177)
    }

    @Test func bitwiseAndEval() throws {
        let expr = Expression.bitwiseAnd(.literal(0o177), .literal(0o070))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0o070)
    }

    @Test func undefinedSymbol() throws {
        let expr = Expression.symbol("UNKNOWN")
        #expect(throws: ExpressionError.undefinedSymbol("UNKNOWN")) {
            try expr.evaluate(symbols: symbols, locationCounter: 0)
        }
    }

    @Test func wrapsAt16Bits() throws {
        let expr = Expression.add(.literal(0xFFFF), .literal(1))
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0)
    }

    @Test func compoundExpr() throws {
        // FOO + BAR * 2  (no precedence here — callers build AST with correct order)
        let expr = Expression.add(.symbol("FOO"), .multiply(.symbol("BAR"), .literal(2)))
        // 0o1000 + 0o0010 * 2 = 0o1000 + 0o0020 = 0o1020
        #expect(try expr.evaluate(symbols: symbols, locationCounter: 0) == 0o1020)
    }

    @Test func isConstantLiteral() {
        #expect(Expression.literal(5).isConstant == true)
    }

    @Test func isConstantSymbol() {
        #expect(Expression.symbol("X").isConstant == false)
    }

    @Test func isConstantCompound() {
        let e = Expression.add(.literal(1), .literal(2))
        #expect(e.isConstant == true)
    }
}

// MARK: - SymbolTable tests

@Suite("SymbolTable") struct SymbolTableTests {

    @Test func defineAndLookup() {
        var st = SymbolTable()
        st.define("FOO", value: 42)
        #expect(st.lookup("FOO") == .absolute(42))
    }

    @Test func caseInsensitive() {
        var st = SymbolTable()
        st.define("foo", value: 1)
        #expect(st.lookup("FOO") == .absolute(1))
        #expect(st.lookup("Foo") == .absolute(1))
    }

    @Test func undefinedByDefault() {
        let st = SymbolTable()
        #expect(st.lookup("X") == .undefined)
    }

    @Test func forwardReference() {
        var st = SymbolTable()
        st.markForwardReference("LOOP")
        #expect(st.lookup("LOOP") == .undefined)
        st.define("LOOP", value: 0o1000)
        #expect(st.lookup("LOOP") == .absolute(0o1000))
    }

    @Test func redefine() {
        var st = SymbolTable()
        st.define("X", value: 1)
        st.define("X", value: 2)
        #expect(st.lookup("X") == .absolute(2))
    }

    @Test func isDefined() {
        var st = SymbolTable()
        #expect(st.isDefined("X") == false)
        st.define("X", value: 0)
        #expect(st.isDefined("X") == true)
    }

    @Test func undefinedSymbolsList() {
        var st = SymbolTable()
        st.markForwardReference("BETA")
        st.markForwardReference("ALPHA")
        st.define("ALPHA", value: 1) // resolve one
        #expect(st.undefinedSymbols == ["BETA"])
    }

    @Test func definedList() {
        var st = SymbolTable()
        st.define("Z", value: 3)
        st.define("A", value: 1)
        let names = st.defined.map(\.name)
        #expect(names == ["A", "Z"]) // sorted
    }
}
