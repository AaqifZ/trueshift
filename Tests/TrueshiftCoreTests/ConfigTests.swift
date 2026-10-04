import XCTest
@testable import TrueshiftCore
import Yams
import Foundation

final class ConfigTests: XCTestCase {

    // MARK: - YAML Parsing

    func testParseMinimalConfig() throws {
        let yaml = """
        location:
          latitude: -33.87
          longitude: 151.21
        """

        let config = try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml)
        XCTAssertEqual(config.location.latitude, -33.87)
        XCTAssertEqual(config.location.longitude, 151.21)
        XCTAssertNil(config.schedule)
        XCTAssertNil(config.state)
    }

    func testParseFullConfig() throws {
        let yaml = """
        location:
          latitude: -33.87
          longitude: 151.21
        schedule:
          day_temp: 6000
          night_floor: 1400
          deep_red: false
        state:
          override_until: "2026-07-24T20:00:00Z"
          override_temp: 2200
        """

        let config = try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml)
        XCTAssertEqual(config.schedule?.dayTemp, 6000)
        XCTAssertEqual(config.schedule?.nightFloor, 1400)
        XCTAssertEqual(config.schedule?.deepRed, false)
        XCTAssertEqual(config.state?.overrideUntil, "2026-07-24T20:00:00Z")
        XCTAssertEqual(config.state?.overrideTemp, 2200)
    }

    /// A v1-era config on disk (bedtime, finish_line, old schedule keys) must
    /// still load — Codable ignores unknown YAML keys.
    func testLegacyV1ConfigStillLoads() throws {
        let yaml = """
        location:
          latitude: -33.87
          longitude: 151.21
        bedtime: "21:30"
        finish_line: "20:30"
        schedule:
          day_temp: 5500
          evening_temp: 1200
          night_temp: 1000
          aggressive_temp: 100
          aggressive_brightness: 5
        state:
          tonight_bedtime: "22:00"
          presentation_until: "2026-07-24T20:00:00Z"
        """

        let config = try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml)
        XCTAssertEqual(config.location.latitude, -33.87)
        XCTAssertEqual(config.dayTemp, 5500)
        // Legacy state keys are dropped; no override is derived from them
        XCTAssertNil(config.state?.overrideUntil)
        XCTAssertNil(config.state?.overrideTemp)
    }

    func testMissingLocationThrows() {
        let yaml = """
        schedule:
          day_temp: 5500
        """
        XCTAssertThrowsError(try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml))
    }

    func testMalformedYAMLThrows() {
        let yaml = "location: [not: valid"
        XCTAssertThrowsError(try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml))
    }

    // MARK: - Defaults

    func testDefaults() {
        let config = TrueshiftConfig(location: .init(latitude: -33.87, longitude: 151.21))
        XCTAssertEqual(config.dayTemp, 5500)
        XCTAssertEqual(config.nightFloor, 1000)
        XCTAssertTrue(config.deepRed)
    }

    func testScheduleOverridesDefaults() {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            schedule: .init(dayTemp: 6000, nightFloor: 1800, deepRed: false)
        )
        XCTAssertEqual(config.dayTemp, 6000)
        XCTAssertEqual(config.nightFloor, 1800)
        XCTAssertFalse(config.deepRed)
    }

    // MARK: - Encode/decode round trip

    func testRoundTrip() throws {
        let original = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            schedule: .init(dayTemp: 6000, nightFloor: 1400, deepRed: true),
            state: .init(overrideUntil: "2026-07-24T20:00:00Z", overrideTemp: 2200)
        )

        let yaml = try YAMLEncoder().encode(original)
        let decoded = try YAMLDecoder().decode(TrueshiftConfig.self, from: yaml)

        XCTAssertEqual(decoded.location.latitude, original.location.latitude)
        XCTAssertEqual(decoded.schedule?.dayTemp, original.schedule?.dayTemp)
        XCTAssertEqual(decoded.schedule?.nightFloor, original.schedule?.nightFloor)
        XCTAssertEqual(decoded.state?.overrideUntil, original.state?.overrideUntil)
        XCTAssertEqual(decoded.state?.overrideTemp, original.state?.overrideTemp)
    }

    func testSnakeCaseCodingKeys() throws {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            schedule: .init(dayTemp: 6000, nightFloor: 1400, deepRed: false),
            state: .init(overrideUntil: "2026-07-24T20:00:00Z", overrideTemp: 2200)
        )
        let yaml = try YAMLEncoder().encode(config)

        XCTAssertTrue(yaml.contains("day_temp"))
        XCTAssertTrue(yaml.contains("night_floor"))
        XCTAssertTrue(yaml.contains("deep_red"))
        XCTAssertTrue(yaml.contains("override_until"))
        XCTAssertTrue(yaml.contains("override_temp"))
    }

    // MARK: - Override state (pure API)

    func testActiveOverrideWhenInFuture() {
        let until = Date().addingTimeInterval(3600)
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            state: .init(
                overrideUntil: ISO8601DateFormatter().string(from: until),
                overrideTemp: 1400
            )
        )
        let override = ConfigManager.activeOverride(in: config)
        XCTAssertNotNil(override)
        XCTAssertEqual(override?.temp, 1400)
    }

    func testExpiredOverrideIsNil() {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            state: .init(
                overrideUntil: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)),
                overrideTemp: 1400
            )
        )
        XCTAssertNil(ConfigManager.activeOverride(in: config))
    }

    func testNoStateIsNilOverride() {
        let config = TrueshiftConfig(location: .init(latitude: -33.87, longitude: 151.21))
        XCTAssertNil(ConfigManager.activeOverride(in: config))
    }

    func testMalformedOverrideDateIsNil() {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            state: .init(overrideUntil: "not-a-date", overrideTemp: 1400)
        )
        XCTAssertNil(ConfigManager.activeOverride(in: config))
    }
}
