// SymbolTable.swift — symbol storage and forward-reference tracking

public struct SymbolTable: Sendable {

    public enum Value: Sendable, Equatable {
        case absolute(UInt16)   // resolved numeric value
        case undefined          // forward reference not yet resolved
    }

    /// How a symbol entered the table. MACRO-11 listings mark direct
    /// assignments (`sym = expr`) with `=` in the symbol table.
    public enum Kind: Sendable, Equatable {
        case label          // defined by a label
        case directAssign   // defined by `sym = expr` or `sym == expr`
    }

    private var table: [String: Value] = [:]
    private var kinds: [String: Kind] = [:]

    public init() {}

    // MARK: - Mutations

    /// Define or redefine a symbol with a concrete value.
    public mutating func define(_ name: String, value: UInt16, kind: Kind = .label) {
        let key = name.uppercased()
        table[key] = .absolute(value)
        kinds[key] = kind
    }

    /// How the symbol was defined (defaults to `.label` for unknown symbols).
    public func kind(of name: String) -> Kind {
        kinds[name.uppercased()] ?? .label
    }

    /// Mark a symbol as a forward reference (only if not already defined).
    public mutating func markForwardReference(_ name: String) {
        let key = name.uppercased()
        if table[key] == nil { table[key] = .undefined }
    }

    // MARK: - Queries

    public func lookup(_ name: String) -> Value {
        table[name.uppercased()] ?? .undefined
    }

    public func isDefined(_ name: String) -> Bool {
        if case .absolute = table[name.uppercased()] { return true }
        return false
    }

    /// All undefined symbols remaining after pass 1.
    public var undefinedSymbols: [String] {
        table.compactMap { key, val in
            if case .undefined = val { return key } else { return nil }
        }.sorted()
    }

    /// All defined symbols, sorted by name — for listing / --symbols output.
    public var defined: [(name: String, value: UInt16)] {
        table.compactMap { key, val in
            if case .absolute(let v) = val { return (key, v) } else { return nil }
        }.sorted { $0.name < $1.name }
    }

    /// Defined symbols with their kind, sorted by name.
    public var definedWithKind: [(name: String, value: UInt16, kind: Kind)] {
        defined.map { ($0.name, $0.value, kind(of: $0.name)) }
    }

    public var count: Int { table.count }
}
