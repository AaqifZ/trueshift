// AutoCommand.swift
// Apply automatic schedule-based settings (the launchd agent tick)

import ArgumentParser
import Foundation
import TrueshiftCore

struct AutoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto",
        abstract: "Apply the scheduled color temperature for the current time"
    )

    @Flag(name: .shortAndLong, help: "Show what would be applied without changing display")
    var dryRun = false

    func run() throws {
        // Lazy cleanup — an expired override is already ignored by the
        // schedule; this just tidies the state file.
        ConfigManager.clearOverrideIfExpired()

        let config = try ConfigManager.createDefaultIfNeeded()
        let state = Schedule.current(config: config)

        if dryRun {
            print("Would apply: \(state.temperature)K")
            print("Phase: \(state.phase.description)")
            printMode(state)
            return
        }

        let success = DisplayController.apply(kelvin: state.temperature)

        if success {
            print("✓ \(state.phase.description)")
            print("  \(state.temperature)K")
            printMode(state)

            if let next = state.nextTransition, let nextPhase = state.nextPhase {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                print("  Next: \(nextPhase.rawValue) at \(formatter.string(from: next))")
            }

            // Warn about Night Shift / True Tone conflicts
            if let warning = NightShiftDetector.getConflictWarning() {
                print("")
                print(warning)
            }
        } else {
            throw RuntimeError("Failed to apply display settings")
        }
    }

    private func printMode(_ state: ScheduleState) {
        if case .manual(let until) = state.mode {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            print("  Manual override until \(formatter.string(from: until))")
        }
    }
}
