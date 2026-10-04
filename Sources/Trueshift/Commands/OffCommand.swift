// OffCommand.swift
// Filter off (sticky until next sunrise)

import ArgumentParser
import Foundation
import TrueshiftCore

struct OffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "off",
        abstract: "Turn the filter off (sticky until next sunrise)"
    )

    func run() throws {
        let config = try ConfigManager.createDefaultIfNeeded()
        let until = Schedule.nextSunrise(
            after: Date(),
            latitude: config.location.latitude,
            longitude: config.location.longitude
        ) ?? Date().addingTimeInterval(12 * 3600)

        try ConfigManager.setManualOverride(temp: 6500, until: until)

        let success = DisplayController.reset()

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if success {
            print("✓ Filter off — holds until \(formatter.string(from: until))")
        } else {
            DisplayController.apply(kelvin: 6500)
            print("✓ Display set to daylight (6500K) — holds until \(formatter.string(from: until))")
        }
        print("  Run 'trueshift resume' to return to auto")
    }
}
