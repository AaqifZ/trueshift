// Trueshift: Circadian Display Control CLI for macOS
// Philosophy: Your screen shouldn't lie to your brain about what time it is.

import ArgumentParser
import Foundation
import TrueshiftCore

@main
struct Trueshift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trueshift",
        abstract: "Circadian display control for macOS",
        discussion: """
            Automatically adjusts screen color temperature based on sun
            position: full daylight by day, deep red after dark. Brightness
            is never touched — deep red at full brightness is the point.

            Set a temperature manually and it sticks until the next sunrise;
            'trueshift resume' hands control back to the curve.

            Based on circadian biology (Jack Kruse).
            """,
        version: "2.0.0",
        subcommands: [
            SetCommand.self,
            ResumeCommand.self,
            AutoCommand.self,
            OffCommand.self,
            PWMCommand.self,
            DimCommand.self,
            StatusCommand.self,
            CurveCommand.self,
            PWMProbeCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}
