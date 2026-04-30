// OperandMode.swift — operand representation and 6-bit field encoding

// MARK: - Register helpers (shared across operand parsing and encoding)

/// Returns 0-7 for recognised register names, nil otherwise.
public func registerNumber(_ name: String) -> Int? {
    switch name.uppercased() {
    case "R0": return 0
    case "R1": return 1
    case "R2": return 2
    case "R3": return 3
    case "R4": return 4
    case "R5": return 5
    case "R6", "SP": return 6
    case "R7", "PC": return 7
    default: return nil
    }
}

// MARK: - Operand mode

public enum OperandMode: Sendable, Equatable {
    // Modes 0-7 with explicit register
    case register           (Int)               // mode 0:  Rn
    case registerDeferred   (Int)               // mode 1:  (Rn)
    case autoIncrement      (Int)               // mode 2:  (Rn)+
    case autoIncrementDeferred(Int)             // mode 3:  @(Rn)+
    case autoDecrement      (Int)               // mode 4:  -(Rn)
    case autoDecrementDeferred(Int)             // mode 5:  @-(Rn)
    case index              (Expression, Int)   // mode 6:  X(Rn)
    case indexDeferred      (Expression, Int)   // mode 7:  @X(Rn)

    // PC-relative shorthand forms (R7-based, synthesised by the assembler)
    case immediate          (Expression)        // mode 2, R7:  #expr
    case absolute           (Expression)        // mode 3, R7:  @#expr
    case relative           (Expression)        // mode 6, R7:  label  (PC-relative)
    case relativeDeferred   (Expression)        // mode 7, R7:  @label
}

// MARK: - Encoded operand

/// The assembled representation of one operand field.
/// `field` goes into the instruction word; `extensionExpr` (if set) becomes
/// the next extension word — evaluated during pass 2.
public struct EncodedOperand: Sendable {
    public let field:         UInt16
    public let extensionExpr: Expression?  // nil if no extension word needed

    public init(field: UInt16, extension ext: Expression? = nil) {
        self.field         = field
        self.extensionExpr = ext
    }
}

// MARK: - Encoding

extension OperandMode {
    /// Encode the operand into a 6-bit field and optional extension expression.
    /// `pc` is the address of the extension word (not the instruction word) — used
    /// to compute the PC-relative displacement for `.relative` / `.relativeDeferred`.
    public func encode(extensionWordAddress pc: UInt16) -> EncodedOperand {
        switch self {

        // ── Explicit register modes ─────────────────────────────────────────
        case .register(let r):
            return EncodedOperand(field: UInt16(r))                         // 0nn

        case .registerDeferred(let r):
            return EncodedOperand(field: UInt16(0o10 + r))                  // 1nn

        case .autoIncrement(let r):
            return EncodedOperand(field: UInt16(0o20 + r))                  // 2nn

        case .autoIncrementDeferred(let r):
            return EncodedOperand(field: UInt16(0o30 + r))                  // 3nn

        case .autoDecrement(let r):
            return EncodedOperand(field: UInt16(0o40 + r))                  // 4nn

        case .autoDecrementDeferred(let r):
            return EncodedOperand(field: UInt16(0o50 + r))                  // 5nn

        case .index(let expr, let r):
            return EncodedOperand(field: UInt16(0o60 + r), extension: expr) // 6nn + word

        case .indexDeferred(let expr, let r):
            return EncodedOperand(field: UInt16(0o70 + r), extension: expr) // 7nn + word

        // ── PC-relative (R7) modes ──────────────────────────────────────────
        case .immediate(let expr):
            // #expr → mode 2, R7 — extension word is the literal value
            return EncodedOperand(field: 0o27, extension: expr)

        case .absolute(let expr):
            // @#expr → mode 3, R7 — extension word is the absolute address
            return EncodedOperand(field: 0o37, extension: expr)

        case .relative(let target):
            // label → mode 6, R7 — extension word = target - pc (signed displacement)
            // `pc` here is the address of this extension word; displacement is
            // relative to the address AFTER this word (pc + 2).
            let disp = Expression.subtract(target, .add(.literal(pc), .literal(2)))
            return EncodedOperand(field: 0o67, extension: disp)

        case .relativeDeferred(let target):
            let disp = Expression.subtract(target, .add(.literal(pc), .literal(2)))
            return EncodedOperand(field: 0o77, extension: disp)
        }
    }

    /// True if this mode adds an extension word to the instruction stream.
    public var hasExtensionWord: Bool {
        switch self {
        case .index, .indexDeferred, .immediate, .absolute, .relative, .relativeDeferred:
            return true
        default:
            return false
        }
    }
}
