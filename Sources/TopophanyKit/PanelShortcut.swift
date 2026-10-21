import Foundation

/// A physical key and its modifiers. Modifier bits belong to the settings
/// format, independent of the window system's event flags.
public struct PanelShortcut: Sendable, Hashable, Codable {
    public struct Modifiers: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let control = Self(rawValue: 1 << 0)
        public static let option = Self(rawValue: 1 << 1)
        public static let shift = Self(rawValue: 1 << 2)
        public static let command = Self(rawValue: 1 << 3)
        public static let all: Self = [.control, .option, .shift, .command]
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Require Command, Control or Option so typing and navigation remain
    /// available. Modifier keys themselves cannot be the recorded key.
    public var isValid: Bool {
        keyCode < 128 && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && modifiers.rawValue & ~Modifiers.all.rawValue == 0
            && !modifiers.intersection([.control, .option, .command]).isEmpty
    }
}
