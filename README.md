# m11asm — MACRO-11 Assembler for DCJ-11 / PDP-11

A command-line MACRO-11 assembler for the DCJ-11 (PDP-11) architecture, written in Swift.
Produces raw binary or octal load files suitable for loading into a PDP-11 system via ODT
or an absolute loader. Designed for bare-metal DCJ-11 development and for integration with
[J11Terminal](https://github.com/zoltan-szabo/j11-terminal).

Originally built for the [DCJ11 Single Board Computer v1.3.2](https://www.5volts.ch/pages/dcj11sbc/) by Peter Schranz.

---

## Installation

### Homebrew (recommended)

```bash
brew tap zoltan-szabo/m11asm
brew install m11asm
```

### From source

Requires Xcode 16 or the Swift 6 toolchain.

```bash
git clone https://github.com/zoltan-szabo/m11asm.git
cd m11asm
swift build -c release
cp .build/release/m11asm /usr/local/bin/
```

---

## Quick start

```bash
m11asm program.mac               # → program.oct  (octal load file)
m11asm -f bin program.mac        # → program.bin  (raw binary)
m11asm -b 1000 --symbols prog.mac  # origin 1000₈, print symbol table
```

### Example — blink loop

```asm
; blink.mac — toggle LED at I/O address 177564 in a counted loop
        .= 001000           ; load at 1000 octal

LEDREG  = 177564            ; octal I/O address
COUNT   = ^D1000            ; decimal 1000 iterations

START:  MOV #COUNT, R5
LOOP:   COM @#LEDREG        ; complement LED register
        SOB R5, LOOP
        HALT

        .END START
```

```bash
m11asm -b 1000 Examples/blink/blink.mac && cat Examples/blink/blink.oct
```

```
@001000
012705
001750
005137
177564
077503
000000
```

### Example — Hello World! via the DCJ-11 console UART

The DCJ-11's console UART uses two memory-mapped registers:

| Register | Address | Purpose |
|----------|---------|---------|
| `XCSR` | `177564` | Transmitter status — bit 7 set when ready to accept a byte |
| `XBUF` | `177566` | Transmitter data buffer — write a byte here to send it |

This is the same UART that ODT itself uses. Output appears in J11Terminal's Terminal window.

```asm
; hello_world.mac — "Hello World!" via the DCJ-11 console UART
;
; Assemble:  m11asm -b 1000 hello_world.mac
; Load:      paste hello_world.oct into J11Terminal Octal Upload
; Run:       from ODT prompt:  1000G

        .= 001000

XCSR    = 177564        ; console transmitter status — bit 7: ready
XBUF    = 177566        ; console transmitter data buffer

START:  MOV  #MSG, R0   ; R0 → message string
LOOP:   MOVB (R0)+, R1  ; next byte → R1; advance pointer
        BEQ  DONE       ; NUL terminator — stop
WAIT:   TSTB @#XCSR     ; poll transmitter ready (bit 7)
        BPL  WAIT
        MOVB R1, @#XBUF ; write character to UART
        BR   LOOP
DONE:   HALT

MSG:    .BYTE  15, 12, 15, 12  ; two CR+LF (blank line before output)
        .ASCII /Hello World!/
        .BYTE  15, 12, 0       ; CR, LF, NUL
        .EVEN
```

```bash
m11asm -b 1000 --symbols Examples/hello_world/hello_world.mac && cat Examples/hello_world/hello_world.oct
```

```
Symbol table:
  DONE                    001024
  LOOP                    001004
  MSG                     001026
  START                   001000
  WAIT                    001010
  XBUF                    177566
  XCSR                    177564
21 words → Examples/hello_world/hello_world.oct
@001000
012700
001026
112001
001406
105737
177564
100375
110137
177566
000770
000000
005015
005015
062510
066154
020157
067527
066162
020544
005015
000000
```

After loading and typing `1000G` at the ODT prompt, a blank line followed by `Hello World!`
appears in the Terminal window and the processor halts. ODT resumes control.

---

## CLI reference

```
USAGE: m11asm [options] <input.mac>

OPTIONS:
  -o <file>     Output file (default: input basename + .oct or .bin)
  -f bin|oct    Output format (default: oct)
  -b <addr>     Base (load) address in octal (default: 001000)
  --symbols     Print symbol table to stdout after assembly
  -h, --help    Show help

EXIT CODES:
  0  success
  1  assembly or I/O error
  2  bad arguments
```

### Output formats

**`oct` — Octal load file** (default)

Human-readable and compatible with J11Terminal's Octal Upload window:

```
@001000       ← load origin in octal
012705        ← words in octal, one per line
001750
...
```

**`bin` — Raw binary**

Flat binary image at the base address. The caller must know the load address.

---

## Language support

### Number literals

The default radix is **octal** — a bare integer like `177` is octal, not decimal.

| Syntax | Radix | Example |
|--------|-------|---------|
| bare digits | octal | `177` → 127₁₀ |
| `^D` | decimal | `^D255` |
| `^O` | octal (explicit) | `^O177` |
| `^B` | binary | `^B10110001` |
| `^X` | hex | `^X7F` |
| `^A/c/` | ASCII char | `^A/A/` → 65₁₀ |
| `'c` | ASCII char | `'A` → 65₁₀ |

### Addressing modes

| Syntax | Mode | Description |
|--------|------|-------------|
| `Rn` | 0 | Register direct |
| `(Rn)` | 1 | Register deferred |
| `(Rn)+` | 2 | Autoincrement |
| `@(Rn)+` | 3 | Autoincrement deferred |
| `-(Rn)` | 4 | Autodecrement |
| `@-(Rn)` | 5 | Autodecrement deferred |
| `X(Rn)` | 6 | Index |
| `@X(Rn)` | 7 | Index deferred |
| `#expr` | imm | Immediate (PC autoincrement) |
| `@#addr` | abs | Absolute |
| `label` | rel | PC-relative |
| `@label` | rel-def | PC-relative deferred |
| `SP`, `PC` | — | Aliases for R6, R7 |

### Expressions

Left-to-right evaluation; parentheses override:

| Operator | Meaning |
|----------|---------|
| `+` `-` | add, subtract |
| `*` `/` | multiply, integer divide |
| `!` | bitwise OR |
| `&` | bitwise AND |
| unary `-` | negate |

`.` is the location counter (current address).

### Directives

| Directive | Action |
|-----------|--------|
| `.WORD expr [, ...]` | emit 16-bit words |
| `.BYTE expr [, ...]` | emit bytes |
| `.BLKW n` | reserve n words (zeroed) |
| `.BLKB n` | reserve n bytes (zeroed) |
| `.ASCII /str/` | emit string bytes (any delimiter) |
| `.ASCIZ /str/` | emit string bytes + NUL |
| `.EVEN` | pad to even (word) address |
| `. = expr` | set location counter |
| `sym = expr` | equate (reassignable) |
| `sym == expr` | equate (permanent) |
| `.END [addr]` | end of source |

### Conditional assembly

```asm
.IF  EQ, expr       ; equal to zero
.IF  NE, expr       ; not equal to zero
.IF  GT, expr       ; signed > 0
.IF  LT, expr       ; signed < 0
.IF  GE, expr       ; signed ≥ 0
.IF  LE, expr       ; signed ≤ 0
.IF  DF, SYM        ; symbol is defined
.IF  NDF, SYM       ; symbol is not defined
.ENDC
```

Blocks may be nested.

### Macros

```asm
.MACRO  PUSH  REG
        MOV \REG, -(SP)
.ENDM

        PUSH R0             ; expands to: MOV R0, -(SP)
        PUSH #177           ; expands to: MOV #177, -(SP)
```

- `\PARAM` — substitute argument
- `\@` — unique per-call suffix (for local labels)
- `SYM\@` — concatenate symbol with unique suffix

```asm
.MACRO  SKIP_IF_ZERO  REG
        TST \REG
        BNE DONE\@
        NOP
DONE\@: NOP
.ENDM
```

### Repeat blocks

```asm
.REPT 4
        .WORD 0
.ENDR                       ; emits four zero words

.IRP  R, <R0,R1,R2,R3>
        CLR \R
.ENDR                       ; CLR R0 / CLR R1 / CLR R2 / CLR R3
```

### Local labels

Numeric labels `n$` (n = 0–9) are ordinary symbols and can be reused freely:

```asm
        MOV #10, R2
1$:     DEC R2
        BNE 1$
```

---

## Instruction set

All standard PDP-11 instructions are supported, plus the DCJ-11 (J-11) extensions:

**Double-operand:** `MOV` `MOVB` `CMP` `CMPB` `BIT` `BITB` `BIC` `BICB` `BIS` `BISB` `ADD` `SUB`

**Single-operand:** `CLR` `CLRB` `COM` `COMB` `INC` `INCB` `DEC` `DECB` `NEG` `NEGB`
`ADC` `ADCB` `SBC` `SBCB` `TST` `TSTB` `ROR` `RORB` `ROL` `ROLB` `ASR` `ASRB` `ASL` `ASLB`
`SWAB` `SXT`

**Branch:** `BR` `BNE` `BEQ` `BGE` `BLT` `BGT` `BLE` `BPL` `BMI` `BVC` `BVS` `BCC`/`BHIS`
`BCS`/`BLO` `BHI` `BLOS`

**Jump/call:** `JMP` `JSR` `RTS` `SOB`

**Condition codes:** `NOP` `CLC` `CLV` `CLZ` `CLN` `CCC` `SEC` `SEV` `SEZ` `SEN` `SCC`

**Trap/misc:** `HALT` `WAIT` `RTI` `BPT` `IOT` `RESET` `RTT` `MFPT`
`EMT n` `TRAP n` `SPL n` `MARK n`

**EIS:** `MUL` `DIV` `ASH` `ASHC` `XOR`

**FIS:** `FADD` `FSUB` `FMUL` `FDIV`

**J-11 / DCJ-11:** `MFPD` `MTPD` `MFPS` `MTPS` `MFPI` `MTPI`

---

## Not supported (out of scope for v0.1)

- `.IFF` / `.IFTF` (else/always branches in conditionals)
- `.IRPC` (character-by-character iteration)
- `.INCLUDE` (file inclusion)
- `.PSECT` / `.CSECT` (program sections)
- `.GLOBL` / `.EXTERNAL` (external linking)
- `.NARG` / `.NCHR` (macro argument utilities)
- `.RAD50` (Radix-50 encoding)
- `.DECIMAL` / `.OCTAL` (runtime radix switching)
- Relocatable object files and linker
- FPP (floating-point coprocessor) instructions
- Listing output

---

## Error messages

Errors are reported to stderr in compiler style:

```
prog.mac:12:8: error: undefined symbol 'LOOP'
prog.mac:34:1: error: branch target out of range (72 words from PC)
```

Assembly continues after most errors to collect as many diagnostics as possible.
When any error is present no output file is written.

---

## Integration with J11Terminal

[J11Terminal](https://github.com/zoltan-szabo/J11Terminal) is a macOS serial terminal
for DCJ-11 / PDP-11 systems. The octal load format produced by m11asm is designed to be
pasted directly into J11Terminal's Octal Upload window. Phase 8 of the project will add
an in-app assemble-and-upload workflow.

---

## License

MIT — see [LICENSE](LICENSE).
