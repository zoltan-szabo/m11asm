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
  m11asm/         — executable entry point (main.swift, CLI argument parsing)
  m11asmCore/     — library: all assembler logic (importable by J11Terminal)
Tests/
  m11asmTests/    — tests against m11asmCore
```

The split allows the test target and (eventually) J11Terminal to import `m11asmCore`
directly without going through the executable.

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

## CLI interface (planned)

```
USAGE: m11asm [options] <input.mac>

OPTIONS:
  -o <file>        Output file (default: input basename + .oct)
  -f bin|oct       Output format: raw binary or octal load file (default: oct)
  -b <addr>        Base (load) address in octal (default: 001000)
  --list           Print assembly listing to stdout
  --symbols        Print symbol table after assembly
  --strict         Treat warnings as errors
```

Output formats:
- `oct` — octal load file (`address<TAB>value` pairs), compatible with J11Terminal Octal Upload
- `bin` — flat raw binary at the specified base address

Exit codes: 0 = success, 1 = assembly error, 2 = argument error.

---

## GitHub

Repository: (to be created — `github.com/zoltan-szabo/m11asm` or similar)

---

## Claude session history

| Commit | What was done |
|--------|---------------|
| *(initial)* | Project scaffolding: Swift package with `m11asm` executable + `m11asmCore` library, git init, CLAUDE.md |
