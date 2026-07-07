# Contributing to m11asm

Thanks for your interest! m11asm is a hobby project, but bug reports and
pull requests are welcome.

## Building and testing

Requires Xcode 16 or the Swift 6 toolchain.

```bash
swift build              # debug build
swift test               # run the full test suite
swift run m11asm -b 1000 Examples/hello_world/hello_world.mac
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/m11asmCore/` | Assembler library — lexer, parser, macro expander, codegen, disassembler |
| `Sources/m11asm/` | Command-line front end |
| `Tests/m11asmTests/` | Swift Testing suites |
| `Examples/` | Small MACRO-11 programs, one directory each (`.mac` committed, generated `.oct` ignored) |

## Reporting bugs

The single most useful thing is a **minimal `.mac` file that reproduces the
problem**, together with the command line you used and the octal output you
expected vs. what you got. Wrong-code bugs are best shown as the offending
octal words with the instruction they should have encoded.

## Pull requests

- Add a test for what you fix or add — instruction encodings, directives, and
  expression evaluation all have existing suites in `Tests/m11asmTests/` to
  extend.
- `swift test` must pass.
- New instructions/directives should match real MACRO-11 / DEC behaviour;
  cite the MACRO-11 Language Reference Manual where behaviour is subtle.
- Keep examples self-contained and runnable on real hardware (they target the
  DCJ-11 SBC by Peter Schranz — https://www.5volts.ch/pages/dcj11sbc/).
