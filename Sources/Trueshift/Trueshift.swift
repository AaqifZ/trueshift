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
            Follows the real sun where you live: daylight white by day, deep
            red (about 1000K, close to firelight) after dark. The schedule
            changes color only, never brightness.

            Set a temperature manually and it holds until the next sunrise.
            'trueshift resume' hands control back to the schedule.
            """,
        version: "0.1.0",
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
