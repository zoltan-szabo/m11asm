# History

Release notes. Commit messages stay short; the detail lives here.

## v0.3.0 (2026-07-10)

- **`.INCLUDE /file/`** — assemble another source file in place. Names
  resolve relative to the including file, nest up to 16 levels, and are
  delimited like `.ASCII` (use another delimiter for paths containing
  `/`). File reading goes through a caller-supplied closure so sandboxed
  hosts such as J11Terminal can grant folder access before the read.
- **`-v` / `--version`** — the tool reports its own version; the version
  string lives in `m11asmCore.m11asmVersion` and is also shown in
  `--help`.
- **22-bit physical addressing** in the disassembler and ODT parser.
  `DisassembledInstruction.address`, `disassemble(baseAddress:)`, the
  `symbols` dictionary keys and `parseODTInput` now use `UInt32` masked
  to 22 bits. Previously an ODT fetch above `177777` failed to parse at
  all. Targets inside the 16-bit range still print as 6 octal digits.
- **New example**: `Examples/knight_rider` — a table-driven LED scanner
  for the W65C22S VIA on the DCJ11 Multi IO card. Examples now follow
  the DEC tab grid (label 0, opcode 8, operands 16, comment 32).
- Contributing guide and a structured bug-report issue template.

Known issue: symbol redefinition (a label over an equate) is silently
accepted; real MACRO-11 reports a multiple-definition error. See
[#4](https://github.com/zoltan-szabo/m11asm/issues/4).

## v0.2.0

Tagged but never released. Phase 9 — disassembler engine and ODT
parser (`Disassembler.swift`, `parseODTInput`), 46 tests; `m11asmCore`
exported as a library product for J11Terminal.

## v0.1.0 (2026-04-30)

First release: two-pass MACRO-11 assembler (lexer, expression parser,
symbol table, instruction table with all PDP-11 formats and DCJ-11
extensions, all addressing modes), directives, conditional assembly,
macros with `.REPT`/`.IRP` and local labels, octal-load and raw-binary
output, CLI. Universal macOS binary and Homebrew tap.
