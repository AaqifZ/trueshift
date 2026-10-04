// Config.swift
// YAML configuration loading and management

import Foundation
import Yams

/// Trueshift configuration
///
/// v2 schema — temperature only. The schedule never touches brightness.
/// Legacy v1 keys (bedtime, finish_line, evening_temp, ...) are ignored on
/// load (Codable skips unknown YAML keys) and dropped on the next save.
public struct TrueshiftConfig: Codable {
    public var location: Location
    public var schedule: ScheduleConfig?
    public var state: StateConfig?
    public var pwmSafe: PWMSafeConfig?

    public struct Location: Codable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct ScheduleConfig: Codable {
        public var dayTemp: Int?
        public var nightFloor: Int?
        public var deepRed: Bool?

        public init(dayTemp: Int? = nil, nightFloor: Int? = nil, deepRed: Bool? = nil) {
            self.dayTemp = dayTemp
            self.nightFloor = nightFloor
            self.deepRed = deepRed
        }

        enum CodingKeys: String, CodingKey {
            case dayTemp = "day_temp"
            case nightFloor = "night_floor"
            case deepRed = "deep_red"
        }
    }

    public struct StateConfig: Codable {
        /// Manual override: sticky until this ISO8601 timestamp (next sunrise)
        public var overrideUntil: String?
        public var overrideTemp: Int?

        public init(overrideUntil: String? = nil, overrideTemp: Int? = nil) {
            self.overrideUntil = overrideUntil
            self.overrideTemp = overrideTemp
        }

        enum CodingKeys: String, CodingKey {
            case overrideUntil = "override_until"
            case overrideTemp = "override_temp"
        }
    }

    public struct PWMSafeConfig: Codable {
        /// PWM-safe mode: pin backlight to 100%, dim in software (sticky).
        public var enabled: Bool?
        /// Software brightness (0.2–1.0). Floored to avoid gamma banding.
        public var softwareBrightness: Double?
        /// Pre-pin brightness of the built-in display, so a clean disable can
        /// restore it even after a crash. Only the built-in gets a persisted
        /// snapshot — external display IDs aren't stable across reboots.
        public var savedBrightness: Double?

        public init(enabled: Bool? = nil, softwareBrightness: Double? = nil, savedBrightness: Double? = nil) {
            self.enabled = enabled
            self.softwareBrightness = softwareBrightness
            self.savedBrightness = savedBrightness
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case softwareBrightness = "software_brightness"
            case savedBrightness = "saved_brightness"
        }
    }

    public init(location: Location, schedule: ScheduleConfig? = nil, state: StateConfig? = nil, pwmSafe: PWMSafeConfig? = nil) {
        self.location = location
        self.schedule = schedule
        self.state = state
        self.pwmSafe = pwmSafe
    }
}

// MARK: - Config Defaults

public extension TrueshiftConfig {
    /// Daytime temperature (Kelvin)
    var dayTemp: Int { schedule?.dayTemp ?? 5500 }
    /// Nighttime floor (Kelvin) — Jack Kruse deep red by default
    var nightFloor: Int { schedule?.nightFloor ?? 1000 }
    /// Sub-2700K deep red via gamma layer (TrueshiftBar only)
    var deepRed: Bool { schedule?.deepRed ?? true }

    /// PWM-safe mode active — pin backlight, dim in software (TrueshiftBar only)
    var pwmEnabled: Bool { pwmSafe?.enabled ?? false }
    /// Software brightness multiplier (0.2–1.0). Floored to guard banding.
    var softwareBrightness: Double { min(1.0, max(0.2, pwmSafe?.softwareBrightness ?? 1.0)) }
}

/// Minimum software brightness — below this, gamma banding gets ugly.
public let pwmBrightnessFloor: Double = 0.2

// MARK: - Config Manager

public struct ConfigManager {
    public static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/trueshift")
    public static let configFile = configDir.appendingPathComponent("config.yaml")

    /// Load configuration from disk
    public static func load() throws -> TrueshiftConfig {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            throw ConfigError.notFound
        }

        let data = try Data(contentsOf: configFile)
        let decoder = YAMLDecoder()
        return try decoder.decode(TrueshiftConfig.self, from: data)
    }

    /// Save configuration to disk (atomic — readers never see a torn file)
    public static func save(_ config: TrueshiftConfig) throws {
        try FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true
        )

        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(to: configFile, atomically: true, encoding: .utf8)
    }

    /// Create default config if none exists
    public static func createDefaultIfNeeded() throws -> TrueshiftConfig {
        if FileManager.default.fileExists(atPath: configFile.path) {
            return try load()
        }

        // Default config (Sydney)
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21)
        )

        try save(config)
        return config
    }

    /// Config file modification date — cheap change detection for the bar's tick
    public static func modificationDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configFile.path)
        return attrs?[.modificationDate] as? Date
    }

    // MARK: - Manual Override

    /// Set a sticky manual override (holds until `until`, normally next sunrise)
    public static func setManualOverride(temp: Int, until: Date) throws {
        var config = try createDefaultIfNeeded()
        if config.state == nil {
            config.state = .init()
        }
        config.state?.overrideTemp = temp
        config.state?.overrideUntil = ISO8601DateFormatter().string(from: until)
        try save(config)
    }

    /// Clear the manual override ("Resume Auto")
    public static func clearManualOverride() throws {
        var config = try load()
        guard config.state?.overrideUntil != nil || config.state?.overrideTemp != nil else { return }
        config.state?.overrideUntil = nil
        config.state?.overrideTemp = nil
        try save(config)
    }

    /// Active override, or nil if none/expired. Pure — no I/O.
    public static func activeOverride(in config: TrueshiftConfig, now: Date = Date()) -> (temp: Int, until: Date)? {
        guard let untilStr = config.state?.overrideUntil,
              let temp = config.state?.overrideTemp,
              let until = ISO8601DateFormatter().date(from: untilStr) else {
            return nil
        }
        guard until > now else { return nil }
        return (temp, until)
    }

    // MARK: - PWM-Safe

    /// Enable/disable PWM-safe mode (sticky).
    public static func setPWMEnabled(_ enabled: Bool) throws {
        var config = try createDefaultIfNeeded()
        if config.pwmSafe == nil { config.pwmSafe = .init() }
        config.pwmSafe?.enabled = enabled
        try save(config)
    }

    /// Set software brightness (0.2–1.0). Values are clamped to the floor.
    public static func setSoftwareBrightness(_ value: Double) throws {
        var config = try createDefaultIfNeeded()
        if config.pwmSafe == nil { config.pwmSafe = .init() }
        config.pwmSafe?.softwareBrightness = min(1.0, max(pwmBrightnessFloor, value))
        try save(config)
    }

    /// Persist the built-in display's pre-pin brightness (crash-safe restore).
    public static func setSavedBrightness(_ value: Double?) throws {
        var config = try createDefaultIfNeeded()
        if config.pwmSafe == nil { config.pwmSafe = .init() }
        config.pwmSafe?.savedBrightness = value
        try save(config)
    }

    /// Lazily clear an expired override. Expired == ignored, so a race between
    /// two clearers is harmless; only writes when there is something to clear.
    public static func clearOverrideIfExpired(now: Date = Date()) {
        guard var config = try? load(),
              let untilStr = config.state?.overrideUntil,
              let until = ISO8601DateFormatter().date(from: untilStr),
              until <= now else {
            return
        }
        config.state?.overrideUntil = nil
        config.state?.overrideTemp = nil
        try? save(config)
    }
}

public enum ConfigError: Error, CustomStringConvertible {
    case notFound

    public var description: String {
        switch self {
        case .notFound:
            return "Config not found. Run 'trueshift status' to create default config."
        }
    }
}
