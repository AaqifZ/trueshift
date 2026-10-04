// PWMCommand.swift
// Toggle PWM-safe mode (sticky). Enforced by TrueshiftBar — inert without it.

import ArgumentParser
import Foundation
import TrueshiftCore

struct PWMCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pwm",
        abstract: "Toggle PWM-safe mode: pin backlight to 100%, dim in software",
        discussion: """
            PWM-safe stops backlight flicker by holding the backlight at 100%
            and dimming the image in software instead. It works on Apple
            displays (built-in, Studio Display, Pro Display XDR) and is applied
            by TrueshiftBar — running the CLI alone sets the preference but does
            not drive the display.
            """
    )

    @Argument(help: "on or off")
    var state: PWMToggle

    func run() throws {
        try ConfigManager.setPWMEnabled(state == .on)
        print("✓ PWM-safe \(state == .on ? "enabled" : "disabled")")
        if state == .on {
            print("  TrueshiftBar pins the backlight and dims in software.")
            print("  Set brightness with 'trueshift dim <20-100>'.")
        }
    }
}

enum PWMToggle: String, ExpressibleByArgument, CaseIterable {
    case on, off
}
