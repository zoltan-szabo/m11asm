// SymbolTable.swift — symbol storage and forward-reference tracking

public struct SymbolTable: Sendable {

    public enum Value: Sendable, Equatable {
        case absolute(UInt16)   // resolved numeric value
        case undefined          // forward reference not yet resolved
    }

    private var table: [String: Value] = [:]

    public init() {}

    // MARK: - Mutations

    /// Define or redefine a symbol with a concrete value.
    public mutating func define(_ name: String, value: UInt16) {
        table[name.uppercased()] = .absolute(value)
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

    public var count: Int { table.count }
}
