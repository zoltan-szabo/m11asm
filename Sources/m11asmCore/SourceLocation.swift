// SourceLocation.swift — source position tracking for diagnostics

public struct SourceLocation: Sendable, Equatable, CustomStringConvertible {
    public let file:   String
    public let line:   Int   // 1-based
    public let column: Int   // 1-based

    public var description: String { "\(file):\(line):\(column)" }

    public static let unknown = SourceLocation(file: "<unknown>", line: 0, column: 0)
}

// Generic wrapper pairing a value with the location it came from.
public struct Located<T: Sendable>: Sendable {
    public let value:    T
    public let location: SourceLocation

    public init(_ value: T, at location: SourceLocation) {
        self.value    = value
        self.location = location
    }
}

extension Located: Equatable where T: Equatable {
    public static func == (lhs: Located<T>, rhs: Located<T>) -> Bool { lhs.value == rhs.value }
}
