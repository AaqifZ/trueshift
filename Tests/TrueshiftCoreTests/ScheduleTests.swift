// ScheduleTests.swift
// Tests for the v2 temp-only curve via the pure autoState function

import XCTest
@testable import TrueshiftCore

final class ScheduleTests: XCTestCase {

    // Synthetic solar day: sunrise 07:00, sunset 19:00
    let calendar = Calendar.current
    var sunrise: Date!
    var sunset: Date!

    override func setUp() {
        super.setUp()
        let base = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        sunrise = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: base)!
        sunset = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: base)!
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sunrise)!
    }

    private func curve(_ now: Date, dayTemp: Int = 5500, nightFloor: Int = 1000)
        -> (temperature: Int, phase: Phase, nextTransition: Date?, nextPhase: Phase?) {
        Schedule.autoState(now: now, sunrise: sunrise, sunset: sunset,
                           dayTemp: dayTemp, nightFloor: nightFloor)
    }

    // MARK: - Phase enum

    func testPhaseRawValues() {
        XCTAssertEqual(Phase.wake.rawValue, "wake")
        XCTAssertEqual(Phase.day.rawValue, "day")
        XCTAssertEqual(Phase.dusk.rawValue, "dusk")
        XCTAssertEqual(Phase.evening.rawValue, "evening")
        XCTAssertEqual(Phase.night.rawValue, "night")
    }

    // MARK: - Anchor boundaries

    func testPreDawnIsNightHold() {
        let state = curve(at(3))
        XCTAssertEqual(state.phase, .night)
        XCTAssertEqual(state.temperature, 1000)
        XCTAssertEqual(state.nextTransition, sunrise)
        XCTAssertEqual(state.nextPhase, .wake)
    }

    func testWakeRampStartsAtSunrise() {
        let state = curve(sunrise)
        XCTAssertEqual(state.phase, .wake)
        XCTAssertEqual(state.temperature, 1000)
    }

    func testWakeRampEndsAtDayTemp() {
        // 07:30 = sunrise + 30m
        let state = curve(at(7, 30))
        XCTAssertEqual(state.phase, .day)
        XCTAssertEqual(state.temperature, 5500)
    }

    func testMiddayHoldsDayTemp() {
        let state = curve(at(12))
        XCTAssertEqual(state.phase, .day)
        XCTAssertEqual(state.temperature, 5500)
        XCTAssertEqual(state.nextTransition, sunset.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(state.nextPhase, .dusk)
    }

    func testDuskStartsAtSunsetMinus3h() {
        // 16:00 = sunset − 3h
        let state = curve(at(16))
        XCTAssertEqual(state.phase, .dusk)
        XCTAssertEqual(state.temperature, 5500)
    }

    func testSunsetHits2700() {
        // Just before sunset the dusk ramp has essentially arrived at 2700
        let state = curve(at(18, 59))
        XCTAssertEqual(state.phase, .dusk)
        XCTAssertLessThanOrEqual(abs(state.temperature - 2700), 30)
    }

    func testEveningRampAtSunsetStartsFrom2700() {
        let state = curve(sunset)
        XCTAssertEqual(state.phase, .evening)
        XCTAssertEqual(state.temperature, 2700)
        XCTAssertEqual(state.nextTransition, sunset.addingTimeInterval(2 * 3600))
        XCTAssertEqual(state.nextPhase, .night)
    }

    func testNightHoldAfterSunsetPlus2h() {
        let state = curve(at(22))
        XCTAssertEqual(state.phase, .night)
        XCTAssertEqual(state.temperature, 1000)
        XCTAssertNil(state.nextTransition) // caller fills in tomorrow's sunrise
        XCTAssertEqual(state.nextPhase, .wake)
    }

    // MARK: - Monotonicity

    func testDuskRampIsMonotonicallyDescending() {
        var previous = Int.max
        var t = sunset.addingTimeInterval(-3 * 3600)
        while t <= sunset {
            let temp = curve(t).temperature
            XCTAssertLessThanOrEqual(temp, previous, "dusk ramp rose at \(t)")
            previous = temp
            t = t.addingTimeInterval(5 * 60)
        }
    }

    func testEveningRampIsMonotonicallyDescending() {
        var previous = Int.max
        var t = sunset!
        while t <= sunset.addingTimeInterval(2 * 3600) {
            let temp = curve(t).temperature
            XCTAssertLessThanOrEqual(temp, previous, "evening ramp rose at \(t)")
            previous = temp
            t = t.addingTimeInterval(5 * 60)
        }
    }

    func testWakeRampIsMonotonicallyAscending() {
        var previous = Int.min
        var t = sunrise!
        while t <= sunrise.addingTimeInterval(30 * 60) {
            let temp = curve(t).temperature
            XCTAssertGreaterThanOrEqual(temp, previous, "wake ramp fell at \(t)")
            previous = temp
            t = t.addingTimeInterval(2 * 60)
        }
    }

    // MARK: - Bounds

    func testTemperatureAlwaysWithinFloorAndDayTemp() {
        var t = at(0)
        for _ in 0..<(24 * 12) { // whole day in 5-min steps
            let temp = curve(t).temperature
            XCTAssertGreaterThanOrEqual(temp, 1000)
            XCTAssertLessThanOrEqual(temp, 5500)
            t = t.addingTimeInterval(5 * 60)
        }
    }

    func testCustomNightFloorRespected() {
        let state = curve(at(23), nightFloor: 1400)
        XCTAssertEqual(state.temperature, 1400)
    }

    func testNightFloorAbove2700DoesNotRiseInEvening() {
        // Pathological config: nightFloor above the dusk end temp
        var previous = Int.max
        var t = sunset!
        while t <= sunset.addingTimeInterval(2 * 3600) {
            let temp = curve(t, nightFloor: 3000).temperature
            XCTAssertLessThanOrEqual(temp, previous)
            previous = temp
            t = t.addingTimeInterval(10 * 60)
        }
        XCTAssertEqual(previous, 3000)
    }

    // MARK: - Override handling (via Schedule.current + activeOverride)

    func testActiveOverrideWins() {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            state: .init(
                overrideUntil: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                overrideTemp: 2200
            )
        )
        let state = Schedule.current(config: config)
        XCTAssertEqual(state.temperature, 2200)
        guard case .manual(let until) = state.mode else {
            return XCTFail("expected manual mode")
        }
        XCTAssertEqual(state.nextTransition, until)
    }

    func testExpiredOverrideIgnored() {
        let config = TrueshiftConfig(
            location: .init(latitude: -33.87, longitude: 151.21),
            state: .init(
                overrideUntil: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)),
                overrideTemp: 2200
            )
        )
        let state = Schedule.current(config: config)
        XCTAssertEqual(state.mode, .auto)
    }

    func testNoOverrideIsAuto() {
        let config = TrueshiftConfig(location: .init(latitude: -33.87, longitude: 151.21))
        let state = Schedule.current(config: config)
        XCTAssertEqual(state.mode, .auto)
        XCTAssertNotNil(state.sunrise)
        XCTAssertNotNil(state.sunset)
        XCTAssertLessThan(state.sunrise!, state.sunset!)
    }

    // MARK: - nextSunrise

    func testNextSunriseBeforeDawnIsToday() {
        // 2am today → today's sunrise
        let now = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!
        let next = Schedule.nextSunrise(after: now, latitude: -33.87, longitude: 151.21)
        XCTAssertNotNil(next)
        XCTAssertTrue(calendar.isDate(next!, inSameDayAs: now))
        XCTAssertGreaterThan(next!, now)
    }

    func testNextSunriseAfterDawnIsTomorrow() {
        let now = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let next = Schedule.nextSunrise(after: now, latitude: -33.87, longitude: 151.21)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, now)
        XCTAssertFalse(calendar.isDate(next!, inSameDayAs: now))
    }
}
