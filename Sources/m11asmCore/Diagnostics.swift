// Diagnostics.swift — error and warning collection

import Foundation

public enum DiagnosticLevel: Sendable, Equatable {
    case warning
    case error
}

public struct Diagnostic: Sendable, CustomStringConvertible {
    public let level:    DiagnosticLevel
    public let location: SourceLocation
    public let message:  String

    /// Embedders (J11Terminal) build diagnostics for errors raised outside the
    /// assembler stages, such as a failed `.INCLUDE`.
    public init(level: DiagnosticLevel, location: SourceLocation, message: String) {
        self.level = level
        self.location = location
        self.message = message
    }

    public var description: String {
        let tag = level == .error ? "error" : "warning"
        return "\(location): \(tag): \(message)"
    }
}

/// Collects diagnostics during assembly. Pass by inout through the assembler stages.
public struct DiagnosticEngine: Sendable {
    private var _diagnostics: [Diagnostic] = []

    public init() {}

    public var diagnostics: [Diagnostic] { _diagnostics }
    public var hasErrors:   Bool { _diagnostics.contains { $0.level == .error } }
    public var errorCount:  Int  { _diagnostics.filter  { $0.level == .error }.count }
    public var warningCount:Int  { _diagnostics.filter  { $0.level == .warning }.count }

    public mutating func error(at location: SourceLocation, _ message: String) {
        _diagnostics.append(Diagnostic(level: .error, location: location, message: message))
    }

    public mutating func warning(at location: SourceLocation, _ message: String) {
        _diagnostics.append(Diagnostic(level: .warning, location: location, message: message))
    }

    /// Print all diagnostics to stderr in compiler-style format.
    public func printAll() {
        for d in _diagnostics {
            FileHandle.standardError.write(Data((d.description + "\n").utf8))
        }
    }
}
