// main.swift — m11asm CLI entry point

import Foundation
import m11asmCore

// MARK: - Stderr

private func err(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}

// MARK: - Help

private let usage = """
USAGE: m11asm [options] <input.mac>

OPTIONS:
  -o <file>     Output file (default: input basename + .oct or .bin)
  -f bin|oct    Output format — raw binary or octal load file (default: oct)
  -b <addr>     Base (load) address in octal (default: 001000)
  --symbols     Print symbol table to stdout after assembly
  -h, --help    Show this help

OUTPUT FORMATS:
  oct  Octal load file (@address / word-per-line), for J11Terminal Octal Upload
  bin  Flat raw binary at the base address

EXIT CODES:
  0  success
  1  assembly or I/O error
  2  argument error
"""

// MARK: - Argument parsing

private struct CLIArgs {
    var inputPath:  String = ""
    var outputPath: String = ""
    var format:     String = "oct"
    var origin:     UInt16 = 0o001000
    var symbols:    Bool   = false
}

private func parseArgs() -> CLIArgs {
    var a = CLIArgs()
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let arg = argv[i]
        switch arg {
        case "-h", "--help":
            print(usage)
            exit(0)
        case "-o":
            i += 1
            guard i < argv.count else { err("m11asm: -o requires a filename"); exit(2) }
            a.outputPath = argv[i]
        case "-f":
            i += 1
            guard i < argv.count else { err("m11asm: -f requires a format (bin or oct)"); exit(2) }
            let fmt = argv[i].lowercased()
            guard fmt == "bin" || fmt == "oct" else {
                err("m11asm: unknown format '\(argv[i])' — expected bin or oct")
                exit(2)
            }
            a.format = fmt
        case "-b":
            i += 1
            guard i < argv.count else { err("m11asm: -b requires an octal address"); exit(2) }
            guard let val = UInt16(argv[i], radix: 8) else {
                err("m11asm: '\(argv[i])' is not a valid octal address")
                exit(2)
            }
            a.origin = val
        case "--symbols":
            a.symbols = true
        default:
            if arg.hasPrefix("-") {
                err("m11asm: unknown option '\(arg)'")
                err("Run 'm11asm --help' for usage.")
                exit(2)
            }
            guard a.inputPath.isEmpty else {
                err("m11asm: multiple input files not supported")
                exit(2)
            }
            a.inputPath = arg
        }
        i += 1
    }
    guard !a.inputPath.isEmpty else {
        err("m11asm: no input file\n")
        err(usage)
        exit(2)
    }
    return a
}

// MARK: - Main

private let args = parseArgs()

// Read source file
let source: String
do {
    source = try String(contentsOfFile: args.inputPath, encoding: .utf8)
} catch {
    err("m11asm: cannot read '\(args.inputPath)': \(error.localizedDescription)")
    exit(1)
}

// Determine output path
let outputPath: String = args.outputPath.isEmpty
    ? URL(fileURLWithPath: args.inputPath).deletingPathExtension().path
      + (args.format == "bin" ? ".bin" : ".oct")
    : args.outputPath

// Pipeline: lex → expand → parse → assemble
var diag = DiagnosticEngine()

let tokens: [Located<Token>]
do {
    var lexer = Lexer(source: source, filename: args.inputPath)
    tokens = try lexer.tokenize()
} catch let e as LexError {
    err(e.description)
    exit(1)
} catch {
    err("m11asm: lex error: \(error)")
    exit(1)
}

var expander = MacroExpander()
let expanded = expander.expand(tokens: tokens, diagnostics: &diag)

let program = parse(tokens: expanded, origin: args.origin, diagnostics: &diag)
let bytes   = assemble(program: program, diagnostics: &diag)

// Report diagnostics
diag.printAll()

if diag.hasErrors {
    let n = diag.errorCount
    err("m11asm: \(n) error\(n == 1 ? "" : "s") — no output written")
    exit(1)
}

// Symbol table
if args.symbols {
    let syms = program.symbols.defined
    if syms.isEmpty {
        print("(no symbols)")
    } else {
        print("Symbol table:")
        for (name, value) in syms {
            let pad = String(repeating: " ", count: max(1, 24 - name.count))
            print("  \(name)\(pad)\(String(format: "%06o", value))")
        }
    }
}

// Write output
do {
    if args.format == "bin" {
        try writeBinary(bytes: bytes, to: outputPath)
    } else {
        try writeOctalLoad(bytes: bytes, origin: args.origin, to: outputPath)
    }
} catch {
    err("m11asm: cannot write '\(outputPath)': \(error.localizedDescription)")
    exit(1)
}

let words = (bytes.count + 1) / 2
print("\(words) word\(words == 1 ? "" : "s") → \(outputPath)")
