// StatusCommand.swift
// Show current status (JSON output for Raycast integration)

import ArgumentParser
import Foundation
import TrueshiftCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current schedule status"
    )

    @Flag(name: .shortAndLong, help: "Output as JSON for automation")
    var json = false

    func run() throws {
        let config: TrueshiftConfig
        do {
            config = try ConfigManager.load()
        } catch ConfigError.notFound {
            // Create default config
            config = try ConfigManager.createDefaultIfNeeded()
            print("Created default config at ~/.config/trueshift/config.yaml")
            print("")
        }

        let state = Schedule.current(config: config)

        if json {
            printJSON(state: state, config: config)
        } else {
            printHuman(state: state, config: config)
        }
    }

    /// Count of connected displays whose backlight PWM-safe can pin.
    private func eligibleDisplayCount() -> Int {
        DisplayController.getActiveDisplays().filter { DisplayController.isPWMEligible($0) }.count
    }

    private func printJSON(state: ScheduleState, config: TrueshiftConfig) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var output: [String: Any] = [
            "phase": state.phase.rawValue,
            "temperature": state.temperature,
            "displays": DisplayController.displayCount
        ]

        switch state.mode {
        case .auto:
            output["mode"] = "auto"
        case .manual(let until):
            output["mode"] = "manual"
            output["override_until"] = formatter.string(from: until)
        }

        if let sunrise = state.sunrise {
            output["sunrise"] = formatter.string(from: sunrise)
        }
        if let sunset = state.sunset {
            output["sunset"] = formatter.string(from: sunset)
        }
        if let nextTransition = state.nextTransition {
            output["next_transition"] = formatter.string(from: nextTransition)
        }
        if let nextPhase = state.nextPhase {
            output["next_phase"] = nextPhase.rawValue
        }

        output["pwm_safe"] = [
            "enabled": config.pwmEnabled,
            "software_brightness": config.softwareBrightness,
            "eligible_displays": eligibleDisplayCount()
        ]

        // Output JSON
        if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    private func printHuman(state: ScheduleState, config: TrueshiftConfig) {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        print("Trueshift Status")
        print("───────────────────────────────────────")

        // Check for Night Shift / True Tone conflicts
        if let warning = NightShiftDetector.getConflictWarning() {
            print("")
            print(warning)
        }

        // Show actual display state vs scheduled
        if let actualKelvin = DisplayController.getCurrentKelvin() {
            print("")
            print("Display Now: \(actualKelvin)K")

            // The CCT pipeline clamps at 2700-6000K, so compare in clamped
            // space (sub-2700K deep red comes from TrueshiftBar's gamma layer)
            let clampedTarget = max(2700, min(6000, state.temperature))
            if abs(actualKelvin - clampedTarget) > 200 {
                print("  \u{26a0}\u{fe0f}  Out of sync with schedule!")
                print("  Run 'trueshift auto' to apply")
            }
        }

        print("")
        print("Phase:       \(state.phase.description)")
        print("Scheduled:   \(state.temperature)K")
        switch state.mode {
        case .auto:
            print("Mode:        Auto")
        case .manual(let until):
            print("Mode:        Manual until \(timeFormatter.string(from: until)) (\(state.temperature)K)")
            print("             Run 'trueshift resume' to return to auto")
        }
        print("Displays:    \(DisplayController.displayCount)")
        if config.pwmEnabled {
            let pct = Int((config.softwareBrightness * 100).rounded())
            let eligible = eligibleDisplayCount()
            print("PWM-Safe:    On · \(pct)% · \(eligible) display\(eligible == 1 ? "" : "s") pinnable")
            if eligible == 0 {
                print("             \u{26a0}\u{fe0f}  No pinnable display connected — no effect")
            }
        } else {
            print("PWM-Safe:    Off")
        }
        print("")

        if let sunrise = state.sunrise {
            print("Sunrise:     \(timeFormatter.string(from: sunrise))")
        }
        if let sunset = state.sunset {
            print("Sunset:      \(timeFormatter.string(from: sunset))")
        }

        print("")
        if let next = state.nextTransition, let nextPhase = state.nextPhase {
            print("Next:        \(nextPhase.rawValue) at \(timeFormatter.string(from: next))")
        }
    }
}
