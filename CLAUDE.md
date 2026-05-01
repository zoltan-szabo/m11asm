# CLAUDE.md — m11asm

## What this is

`m11asm` is a MACRO-11 assembler for the DCJ-11 (PDP-11) architecture, written in Swift.
It is a command-line macOS tool designed for bare-metal PDP-11 development and for
integration with the J11Terminal serial terminal app.

Related project: `../J11Terminal` — the terminal app that can call this assembler
and upload the resulting binary via ODT over a serial port.

Reference docs (in J11Terminal repo): `../J11Terminal/docs/`
- `dcj11-instruction-set.md` — full DCJ-11 opcode reference
- `macro11-syntax.md`        — MACRO-11 language reference
- `assembler-plan.md`        — architecture and development plan
- `disassembler-plan.md`     — plan for the disassembler (also lives here eventually)

---

## Project structure

```
Sources/
  m11asm/         — executable entry point (main.swift — CLI, argument parsing)
  m11asmCore/     — library: all assembler logic (importable by J11Terminal)
    Token.swift           — Token enum (symbol, integer, stringLiteral, punctuation, …)
    Lexer.swift           — tokeniser; injects .stringLiteral after .ASCII/.ASCIZ
    SourceLocation.swift  — file/line/column, Located<T> wrapper
    Expression.swift      — Expression AST + evaluate(symbols:locationCounter:)
    ExpressionParser.swift — recursive-descent expression parser (TokenStream)
    SymbolTable.swift     — symbol storage and lookup
    Diagnostics.swift     — DiagnosticEngine (errors / warnings)
    InstructionTable.swift — opcode lookup, InstructionDescriptor, all formats
    OperandMode.swift     — OperandMode enum, 6-bit field + extension-word encoding
    Parser.swift          — Pass 1: symbol table, ParsedProgram, .IF/.ENDC, directives
    CodeGen.swift         — Pass 2: byte emission (little-endian [UInt8] output)
    MacroExpander.swift   — Pre-pass: .MACRO/.ENDM, .REPT, .IRP, \PARAM, \@ local labels
    Output.swift          — writeBinary() and writeOctalLoad() file writers
    m11asmCore.swift      — public re-exports
Tests/
  m11asmTests/
    Phase1Tests.swift     — Lexer, Expression, SymbolTable (66 tests)
    Phase2Tests.swift     — InstructionTable, OperandMode encoder (136 tests)
    Phase3Tests.swift     — Parser + CodeGen, two-pass assembly (183 tests)
    Phase4Tests.swift     — directives, equates, .IF conditional (231 tests)
    Phase5Tests.swift     — macro expansion, .REPT, .IRP (257 tests total)
```

`Package.swift` declares two products: `m11asm` (executable) and `m11asmCore` (library).
The test target imports `m11asmCore` directly. J11Terminal can do the same.

---

## Building

```bash
swift build
swift build -c release
```

Run the assembler:
```bash
swift run m11asm [options] <input.mac>
# or after release build:
.build/release/m11asm [options] <input.mac>
```

Run tests:
```bash
swift test
```

---

## CLI interface

```
USAGE: m11asm [options] <input.mac>

OPTIONS:
  -o <file>        Output file (default: input basename + .oct or .bin)
  -f bin|oct       Output format: raw binary or octal load file (default: oct)
  -b <addr>        Base (load) address in octal (default: 001000)
  --symbols        Print symbol table to stdout after assembly
  -h, --help       Show help
```

Output formats:
- `oct` — octal load file (`@address` header + one word per line in octal), for J11Terminal Octal Upload
- `bin` — flat raw binary at the specified base address

Exit codes: 0 = success, 1 = assembly or I/O error, 2 = argument error.

---

## GitHub

Repository: `github.com/zoltan-szabo/m11asm`

---

## Claude session history

| Commit | What was done |
|--------|---------------|
| `86e1843` | Project scaffolding: Swift package with `m11asm` executable + `m11asmCore` library, git init, CLAUDE.md |
| `8285f87` | Phase 1 — Lexer (octal default, `^D`/`^B`/`^X` prefixes, `.ASCII`/`.ASCIZ` string injection), Expression AST + recursive-descent evaluator, SymbolTable, DiagnosticEngine; 66 tests |
| `be499de` | Phase 2 — InstructionTable (all PDP-11 formats + DCJ-11 extensions), OperandMode 12-case encoder (6-bit field + optional extension word), ExpressionParser (TokenStream), OperandParser; 136 tests |
| `0885617` | Phase 3 — two-pass assembler: Parser (pass 1, symbol table, statement IR), CodeGen (pass 2, byte-level `[UInt8]` output, little-endian); all instruction formats, all addressing modes, branch/SOB range checks; 183 tests |
| `fe00f06` | Phase 4 — directives (`.WORD` `.BYTE` `.BLKW` `.BLKB` `.ASCII` `.ASCIZ` `.EVEN`), equates (`sym = expr`, `sym == expr`), location counter assignment (`. = expr`), `.IF`/`.ENDC` conditional assembly (nested, EQ/NE/GT/LT/DF/NDF); byte-level output; 231 tests |
| `64c26d3` | Phase 5 — pre-pass `MacroExpander`: `.MACRO`/`.ENDM` definition and invocation, `\PARAM` substitution, `\@` local-label suffix (`__M0001`…), `SYM\@` concatenation, `.REPT n`, `.IRP sym, <list>`, depth-limited recursion (64 levels); 257 tests |
| `80c18b1` | Phase 6+7 — `Output.swift` (`writeBinary`, `writeOctalLoad`); `main.swift` CLI (`-f bin\|oct`, `-b addr`, `-o file`, `--symbols`, `-h`); compiler-style error messages; exit codes |
| `aec73e1` | `README.md` — installation, quick start, CLI reference, language support, full instruction set, "not supported" section |
| `7fa31de` | `LICENSE` — MIT |
| `v0.1.0`  | Tagged release; GitHub Release created; universal macOS binary (arm64 + x86_64) attached; Homebrew tap published at `github.com/zoltan-szabo/homebrew-m11asm` |
| `f859c31` | `README.md` hello_world.mac — added two leading CR+LF pairs before the message so output appears on its own line after `@1000G`; 19 words → 21 words |
