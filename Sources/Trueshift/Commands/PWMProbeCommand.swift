// PWMProbeCommand.swift
// Hidden diagnostic: per-display PWM-safe eligibility + brightness round-trip.
// The XCTest-less verification substitute for the backlight pin (like `curve`).

import ArgumentParser
import Foundation
import CoreGraphics
import TrueshiftCore

struct PWMProbeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pwm-probe",
        abstract: "Probe per-display PWM-safe eligibility (debug)",
        shouldDisplay: false
    )

    @Flag(name: .long, help: "Pin then restore each eligible display (round-trip test)")
    var roundTrip = false

    func run() throws {
        let displays = DisplayController.getActiveDisplays()
        guard !displays.isEmpty else {
            print("No active displays")
            return
        }

        for id in displays {
            let builtin = DisplayController.isBuiltIn(id)
            let eligible = DisplayController.isPWMEligible(id)
            let brightness = DisplayController.getBrightness(id)
            let bStr = brightness.map { String(format: "%.2f", $0) } ?? "n/a"
            print("Display \(id): \(builtin ? "built-in" : "external"), eligible=\(eligible), brightness=\(bStr)")

            if roundTrip, eligible, let original = brightness {
                let pinned = DisplayController.pinBacklight(id)
                let after = DisplayController.getBrightness(id).map { String(format: "%.2f", $0) } ?? "n/a"
                DisplayController.restoreBacklight(id, to: original)
                print("  pin→100%: \(pinned ? "ok" : "FAILED") (read back \(after)), restored to \(String(format: "%.2f", original))")
            }
        }
    }
}
