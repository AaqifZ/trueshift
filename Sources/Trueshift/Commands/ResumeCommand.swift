// ResumeCommand.swift
// Clear the manual override and return to the automatic curve

import ArgumentParser
import Foundation
import TrueshiftCore

struct ResumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Clear the manual override and resume the automatic schedule"
    )

    func run() throws {
        try ConfigManager.clearManualOverride()

        let config = try ConfigManager.createDefaultIfNeeded()
        let state = Schedule.current(config: config)
        DisplayController.apply(kelvin: state.temperature)

        print("✓ Resumed auto — \(state.phase.description)")
        print("  \(state.temperature)K")

        if let next = state.nextTransition, let nextPhase = state.nextPhase {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            print("  Next: \(nextPhase.rawValue) at \(formatter.string(from: next))")
        }
    }
}
