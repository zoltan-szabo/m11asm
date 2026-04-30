// MacroExpander.swift — Phase 5: macro definition (.MACRO/.ENDM), .REPT, .IRP

// MARK: - Internal definition record

private struct MacroDef: Sendable {
    let params: [String]          // uppercased parameter names
    let body:   [Located<Token>]  // tokens between .MACRO header and .ENDM
}

// MARK: - Expander

/// Pre-processing pass: expands macros in the token stream before the parser sees it.
///
/// Pipeline:  Lexer.tokenize() → MacroExpander.expand() → parse() → assemble()
public struct MacroExpander: Sendable {
    private var defs:    [String: MacroDef] = [:]
    private var callNum: Int = 0

    public init() {}

    /// Expand all macro definitions and invocations in `tokens`.
    /// Mutates internal state (macro registry, call counter).
    public mutating func expand(tokens: [Located<Token>],
                                diagnostics: inout DiagnosticEngine) -> [Located<Token>] {
        expandTokens(tokens, depth: 0, diagnostics: &diagnostics)
    }

    // MARK: - Core expansion loop

    private mutating func expandTokens(_ tokens: [Located<Token>],
                                        depth: Int,
                                        diagnostics: inout DiagnosticEngine) -> [Located<Token>] {
        if depth > 64 {
            diagnostics.error(at: .unknown, "macro expansion depth limit exceeded (recursive macro?)")
            return []
        }

        var out: [Located<Token>] = []
        var idx = 0
        var mnemonicPos = true   // true when the next symbol could be a mnemonic/macro name

        while idx < tokens.count {
            let tok = tokens[idx]

            // ── Newline ───────────────────────────────────────────────────────────────
            if tok.value == .newline {
                out.append(tok); idx += 1; mnemonicPos = true; continue
            }

            // ── Non-symbol pass-through ───────────────────────────────────────────────
            guard case .symbol(let name) = tok.value else {
                out.append(tok); idx += 1
                if tok.value != .colon { mnemonicPos = false }
                continue
            }

            // ── Label: symbol immediately followed by ":" ─────────────────────────────
            if idx + 1 < tokens.count && tokens[idx + 1].value == .colon {
                out.append(tok); out.append(tokens[idx + 1])
                idx += 2; mnemonicPos = true; continue
            }

            // ── .MACRO definition ─────────────────────────────────────────────────────
            if mnemonicPos && name == ".MACRO" {
                idx += 1
                idx = parseMacroDef(tokens: tokens, startIdx: idx, diagnostics: &diagnostics)
                mnemonicPos = true; continue
            }

            // ── .REPT repeat block ────────────────────────────────────────────────────
            if mnemonicPos && name == ".REPT" {
                let loc = tok.location
                idx += 1
                let (countToks, afterLine) = tokensToEOL(tokens, from: idx)
                idx = skipNewline(tokens, from: afterLine)
                let count = evalInt(countToks, at: loc, diagnostics: &diagnostics)
                let (body, afterENDR) = collectBody(tokens, from: idx,
                                                     openers: [".REPT", ".IRP", ".IRPC"],
                                                     closer: ".ENDR")
                idx = skipNewline(tokens, from: afterENDR)
                for _ in 0 ..< max(0, count) {
                    out += expandTokens(body, depth: depth + 1, diagnostics: &diagnostics)
                }
                mnemonicPos = true; continue
            }

            // ── .IRP iterate-over-list block ──────────────────────────────────────────
            if mnemonicPos && name == ".IRP" {
                let loc = tok.location
                idx += 1
                guard idx < tokens.count, case .symbol(let symName) = tokens[idx].value else {
                    diagnostics.error(at: loc, ".IRP: expected parameter name")
                    idx = skipToENDR(tokens, from: idx); continue
                }
                idx += 1
                if idx < tokens.count && tokens[idx].value == .comma { idx += 1 }
                guard idx < tokens.count && tokens[idx].value == .langle else {
                    diagnostics.error(at: loc, ".IRP: expected <argument list>")
                    idx = skipToENDR(tokens, from: idx); continue
                }
                idx += 1  // consume <
                let (listToks, afterAngle) = tokensToRangle(tokens, from: idx)
                idx = skipNewline(tokens, from: afterAngle)
                let (body, afterENDR) = collectBody(tokens, from: idx,
                                                     openers: [".REPT", ".IRP", ".IRPC"],
                                                     closer: ".ENDR")
                idx = skipNewline(tokens, from: afterENDR)
                for argToks in splitOnComma(listToks) {
                    let sub = subParams(body, params: [symName.uppercased()],
                                        args: [argToks], suffix: "")
                    out += expandTokens(sub, depth: depth + 1, diagnostics: &diagnostics)
                }
                mnemonicPos = true; continue
            }

            // ── Known macro invocation ────────────────────────────────────────────────
            if mnemonicPos, let def = defs[name.uppercased()] {
                idx += 1
                callNum += 1
                let suffix = String(format: "__M%04d", callNum)
                var argToks: [[Located<Token>]] = []
                for _ in def.params {
                    guard idx < tokens.count,
                          tokens[idx].value != .newline,
                          tokens[idx].value != .eof else { break }
                    argToks.append(parseOneArg(tokens, idx: &idx))
                    if idx < tokens.count && tokens[idx].value == .comma { idx += 1 }
                }
                // Pad missing arguments with empty
                while argToks.count < def.params.count { argToks.append([]) }
                let sub = subParams(def.body, params: def.params, args: argToks, suffix: suffix)
                out += expandTokens(sub, depth: depth + 1, diagnostics: &diagnostics)
                // Consume rest of invocation line
                while idx < tokens.count && tokens[idx].value != .newline { idx += 1 }
                if idx < tokens.count { idx += 1 }
                mnemonicPos = true; continue
            }

            // ── Pass through ──────────────────────────────────────────────────────────
            out.append(tok); idx += 1; mnemonicPos = false
        }
        return out
    }

    // MARK: - Macro definition parser

    /// Consume a `.MACRO NAME PARAMS \n BODY .ENDM [NAME]` block starting at `startIdx`
    /// (the token immediately after the `.MACRO` token).
    /// Returns the index of the first token on the line after `.ENDM`.
    private mutating func parseMacroDef(tokens: [Located<Token>], startIdx: Int,
                                         diagnostics: inout DiagnosticEngine) -> Int {
        var i = startIdx
        guard i < tokens.count, case .symbol(let macroName) = tokens[i].value else {
            let loc = i < tokens.count ? tokens[i].location : SourceLocation.unknown
            diagnostics.error(at: loc, ".MACRO: expected name")
            let (_, after) = collectBody(tokens, from: i, openers: [".MACRO"], closer: ".ENDM")
            return skipNewline(tokens, from: after)
        }
        i += 1
        // Collect param names from rest of header line (commas are separators, not included)
        var params: [String] = []
        while i < tokens.count && tokens[i].value != .newline && tokens[i].value != .eof {
            if case .symbol(let p) = tokens[i].value { params.append(p.uppercased()) }
            i += 1
        }
        i = skipNewline(tokens, from: i)
        // Collect body tokens until matching .ENDM
        let (body, afterEND) = collectBody(tokens, from: i, openers: [".MACRO"], closer: ".ENDM")
        defs[macroName.uppercased()] = MacroDef(params: params, body: body)
        // Skip optional name after .ENDM and consume the newline
        return skipNewline(tokens, from: afterEND)
    }

    // MARK: - Parameter substitution

    /// Replace `\PARAM`, `\@`, `SYM\@`, `SYM\PARAM` patterns in body with actual arguments.
    private func subParams(_ body: [Located<Token>],
                            params: [String],
                            args:   [[Located<Token>]],
                            suffix: String) -> [Located<Token>] {
        var lookup: [String: [Located<Token>]] = [:]
        for (i, p) in params.enumerated() {
            lookup[p] = i < args.count ? args[i] : []
        }

        var result: [Located<Token>] = []
        var i = 0
        while i < body.count {
            let tok = body[i]

            // SYM\@ → concatenate symbol + suffix
            if case .symbol(let sym) = tok.value,
               i + 2 < body.count,
               body[i + 1].value == .backslash,
               body[i + 2].value == .at {
                result.append(Located(.symbol(sym + suffix), at: tok.location))
                i += 3; continue
            }

            // \@ → unique suffix
            if tok.value == .backslash,
               i + 1 < body.count, body[i + 1].value == .at {
                result.append(Located(.symbol(suffix.isEmpty ? "__M0000" : suffix), at: tok.location))
                i += 2; continue
            }

            // \PARAM → substitute argument tokens
            if tok.value == .backslash,
               i + 1 < body.count,
               case .symbol(let pname) = body[i + 1].value,
               let argToks = lookup[pname] {
                result.append(contentsOf: argToks)
                i += 2; continue
            }

            result.append(tok)
            i += 1
        }
        return result
    }

    // MARK: - Body collector

    /// Collect tokens from `startIdx` until the matching `closer`, counting nested `openers`.
    /// Returns the body (exclusive of the closing keyword) and the index AFTER the closer.
    private func collectBody(_ tokens: [Located<Token>], from startIdx: Int,
                              openers: Set<String>, closer: String) -> ([Located<Token>], Int) {
        var body: [Located<Token>] = []
        var i = startIdx
        var depth = 0
        while i < tokens.count {
            if case .symbol(let s) = tokens[i].value {
                if openers.contains(s) { depth += 1 }
                else if s == closer {
                    if depth == 0 { i += 1; break }
                    depth -= 1
                }
            }
            body.append(tokens[i])
            i += 1
        }
        return (body, i)
    }

    // MARK: - Argument parser

    /// Parse one macro invocation argument starting at `idx` (mutates idx).
    /// Angle-bracket args `<...>` strip the brackets. Otherwise reads until comma/newline.
    private func parseOneArg(_ tokens: [Located<Token>], idx: inout Int) -> [Located<Token>] {
        guard idx < tokens.count else { return [] }
        if tokens[idx].value == .langle {
            idx += 1
            let (toks, after) = tokensToRangle(tokens, from: idx)
            idx = after
            return toks
        }
        var toks: [Located<Token>] = []
        while idx < tokens.count,
              tokens[idx].value != .comma,
              tokens[idx].value != .newline,
              tokens[idx].value != .eof {
            toks.append(tokens[idx]); idx += 1
        }
        return toks
    }

    // MARK: - Token stream utilities

    /// Tokens from `from` to (not including) next newline/eof.
    private func tokensToEOL(_ tokens: [Located<Token>], from idx: Int) -> ([Located<Token>], Int) {
        var r: [Located<Token>] = []; var i = idx
        while i < tokens.count && tokens[i].value != .newline && tokens[i].value != .eof {
            r.append(tokens[i]); i += 1
        }
        return (r, i)
    }

    /// Tokens from `from` to (not including) the matching closing `>`.
    private func tokensToRangle(_ tokens: [Located<Token>], from idx: Int) -> ([Located<Token>], Int) {
        var r: [Located<Token>] = []; var i = idx; var depth = 0
        while i < tokens.count {
            if tokens[i].value == .rangle && depth == 0 { i += 1; break }
            if tokens[i].value == .langle { depth += 1 }
            if tokens[i].value == .rangle { depth -= 1 }
            r.append(tokens[i]); i += 1
        }
        return (r, i)
    }

    /// Skip tokens on the current line (including the newline itself) and return the
    /// index of the first token on the next line.
    private func skipNewline(_ tokens: [Located<Token>], from idx: Int) -> Int {
        var i = idx
        while i < tokens.count && tokens[i].value != .newline { i += 1 }
        if i < tokens.count { i += 1 }
        return i
    }

    /// Skip to and past the matching .ENDR.
    private func skipToENDR(_ tokens: [Located<Token>], from idx: Int) -> Int {
        let (_, after) = collectBody(tokens, from: idx,
                                      openers: [".REPT", ".IRP", ".IRPC"], closer: ".ENDR")
        return skipNewline(tokens, from: after)
    }

    /// Split a flat token list on top-level commas (angle-bracket content is opaque).
    private func splitOnComma(_ tokens: [Located<Token>]) -> [[Located<Token>]] {
        var result: [[Located<Token>]] = []
        var cur: [Located<Token>] = []
        var depth = 0
        for tok in tokens {
            if tok.value == .langle { depth += 1 }
            else if tok.value == .rangle, depth > 0 { depth -= 1 }
            else if tok.value == .comma, depth == 0 { result.append(cur); cur = []; continue }
            cur.append(tok)
        }
        if !cur.isEmpty { result.append(cur) }
        return result
    }

    /// Evaluate a flat token list as a constant integer expression (no symbol table).
    private func evalInt(_ toks: [Located<Token>], at loc: SourceLocation,
                          diagnostics: inout DiagnosticEngine) -> Int {
        var stream = TokenStream(toks)
        do {
            let expr = try parseExpression(stream: &stream)
            let st   = SymbolTable()
            return Int(try expr.evaluate(symbols: st, locationCounter: 0))
        } catch {
            diagnostics.error(at: loc, "invalid count expression: \(error)")
            return 0
        }
    }
}
