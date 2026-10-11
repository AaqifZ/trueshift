// DimCommand.swift
// Set PWM-safe software brightness (20-100%). Enforced by TrueshiftBar.

import ArgumentParser
import Foundation
import TrueshiftCore

struct DimCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dim",
        abstract: "Set PWM-safe software brightness (20-100%)"
    )

    @Argument(help: "Brightness percentage (20-100)")
    var percent: Int

    func run() throws {
        guard percent >= 20 && percent <= 100 else {
            throw ValidationError("Brightness must be between 20 and 100")
        }
        try ConfigManager.setSoftwareBrightness(Double(percent) / 100.0)
        print("✓ Software brightness set to \(percent)%")
        print("  Applies when PWM-safe is on (TrueshiftBar). Enable: 'trueshift pwm on'")
    }
}
