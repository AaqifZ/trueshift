// CurveCommand.swift
// Hidden debug command: print the day's temperature curve.
// This is the runnable substitute for unit tests on machines without XCTest.

import ArgumentParser
import Foundation
import TrueshiftCore

struct CurveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "curve",
        abstract: "Print today's temperature curve (debug)",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Step size in minutes")
    var step: Int = 15

    func run() throws {
        let config = try ConfigManager.createDefaultIfNeeded()
        let calendar = Calendar.current
        let now = Date()

        let state = Schedule.current(config: config, now: now)
        guard let sunrise = state.sunrise, let sunset = state.sunset else {
            throw RuntimeError("No solar times available")
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        print("Anchors  (day_temp \(config.dayTemp)K, night_floor \(config.nightFloor)K)")
        print("─────────────────────────────────────────")
        let anchors: [(String, Date, String)] = [
            ("sunrise", sunrise, "wake ramp starts (\(config.nightFloor)K → \(config.dayTemp)K)"),
            ("sunrise+30m", sunrise.addingTimeInterval(30 * 60), "day hold (\(config.dayTemp)K)"),
            ("sunset−3h", sunset.addingTimeInterval(-3 * 3600), "dusk ramp starts (→ 2700K)"),
            ("sunset", sunset, "evening ramp starts (→ \(config.nightFloor)K)"),
            ("sunset+2h", sunset.addingTimeInterval(2 * 3600), "night hold (\(config.nightFloor)K)"),
        ]
        for (name, date, note) in anchors {
            print("  \(timeFormatter.string(from: date))  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(note)")
        }

        print("")
        print("Curve (\(step)-min steps)")
        print("─────────────────────────────────────────")

        var t = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: t)!
        var lastPhase: Phase?
        while t < end {
            let s = Schedule.autoState(
                now: t, sunrise: sunrise, sunset: sunset,
                dayTemp: config.dayTemp, nightFloor: config.nightFloor
            )
            let phaseMark = s.phase != lastPhase ? " ← \(s.phase.rawValue)" : ""
            lastPhase = s.phase
            print("  \(timeFormatter.string(from: t))  \(String(s.temperature).padding(toLength: 5, withPad: " ", startingAt: 0))K\(phaseMark)")
            t = t.addingTimeInterval(Double(step) * 60)
        }
    }
}
