import Foundation

/// The direction a device is ranked for. A USB headset is both, and has an entry in each list.
public enum AudioScope: String, Codable, CaseIterable, Sendable, Identifiable {
    case output, input

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .output: "Output"
        case .input: "Input"
        }
    }

    /// The SF Symbol for a device of this scope whose transport says nothing more specific.
    public var symbolName: String {
        switch self {
        case .output: "speaker.wave.2"
        case .input: "mic"
        }
    }
}

/// How a device is attached, for its icon in the menu and the settings.
public enum AudioTransport: String, Codable, Sendable {
    case builtIn, usb, bluetooth, display, airPlay, continuity, virtual, aggregate, other

    public func symbolName(for scope: AudioScope) -> String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .usb: "cable.connector"
        case .bluetooth: "headphones"
        case .display: "display"
        case .airPlay: "airplay.audio"
        case .continuity: "iphone"
        case .virtual: "waveform"
        case .aggregate: "square.stack.3d.up"
        case .other: scope.symbolName
        }
    }
}

/// A connected device as CoreAudio reports it. `uid` is CoreAudio's device UID, which stays the
/// same across reconnects and restarts, unlike the numeric device ID.
public struct AudioDevice: Hashable, Sendable, Identifiable {
    public var uid: String
    public var name: String
    public var transport: AudioTransport

    public var id: String { uid }

    public init(uid: String, name: String, transport: AudioTransport = .other) {
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}
