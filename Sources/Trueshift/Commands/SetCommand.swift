// SetCommand.swift
// Sticky manual override — holds until the next sunrise

import ArgumentParser
import Foundation
import TrueshiftCore

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set color temperature manually (sticky until next sunrise)"
    )

    @Argument(help: "Color temperature in Kelvin (1000-6500; 6500 = filter off)")
    var temperature: Int

    @Flag(name: .shortAndLong, help: "Show debug output")
    var verbose = false

    func run() throws {
        guard temperature >= 1000 && temperature <= 6500 else {
            throw ValidationError("Temperature must be between 1000 and 6500 Kelvin")
        }

        let config = try ConfigManager.createDefaultIfNeeded()
        let until = Schedule.nextSunrise(
            after: Date(),
            latitude: config.location.latitude,
            longitude: config.location.longitude
        ) ?? Date().addingTimeInterval(12 * 3600)

        try ConfigManager.setManualOverride(temp: temperature, until: until)

        let success = DisplayController.apply(kelvin: temperature, verbose: verbose)

        if success {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            print("✓ Set to \(temperature)K — holds until \(formatter.string(from: until))")
            print("  Run 'trueshift resume' to return to auto")
        } else {
            throw RuntimeError("Failed to apply display settings")
        }
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}
