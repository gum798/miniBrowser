import Foundation

/// App-wide user settings. Fields decode leniently (missing -> default) so files
/// written by older versions keep working as settings are added over time.
public struct Settings: Codable, Equatable {
    public var inverted: Bool          // global color inversion (dark-mode-ish)
    public var adBlockEnabled: Bool
    public var bossModeEnabled: Bool   // shrink the window when idle (자리비움 자동 숨김)
    public var windowOpacity: Double   // whole-window alpha, minWindowOpacity...1

    /// Floor for `windowOpacity`: a near-invisible window can't be found or clicked.
    public static let minWindowOpacity = 0.3

    public init(inverted: Bool = false, adBlockEnabled: Bool = true, bossModeEnabled: Bool = true,
                windowOpacity: Double = 1.0) {
        self.inverted = inverted
        self.adBlockEnabled = adBlockEnabled
        self.bossModeEnabled = bossModeEnabled
        self.windowOpacity = windowOpacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
        adBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .adBlockEnabled) ?? true
        bossModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .bossModeEnabled) ?? true
        let opacity = try c.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? 1.0
        windowOpacity = min(max(opacity, Self.minWindowOpacity), 1.0)
    }
}

/// Loads/saves `Settings` as JSON (`settings.json`), like the other app stores.
public final class SettingsStore {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("settings.json")
    }

    /// Whether a settings file exists yet (used for one-time migrations).
    public var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Missing or corrupt file -> defaults; the app must always be able to start.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
