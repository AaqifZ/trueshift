import Foundation
import CoreBrightnessBridge

public struct NightShiftDetector {

    public static func isNightShiftEnabled() -> Bool {
        if CBBridge_initialize() {
            var strength: Float = 0
            if CBBridge_getStrength(&strength) {
                return strength > 0
            }
        }
        return checkViaPlist()
    }

    public static func isTrueToneEnabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "/Library/Preferences/com.apple.WindowServer", "AmbientLightSensorEnabled"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let status = Int(output) {
                return status == 1
            }
        } catch {}

        return false
    }

    public static func getConflictWarning() -> String? {
        var warnings: [String] = []

        if isTrueToneEnabled() {
            warnings.append("True Tone is enabled (may affect color accuracy)")
        }

        if warnings.isEmpty {
            return nil
        }

        return "\u{26a0}\u{fe0f}  " + warnings.joined(separator: ", ") + "\n   Disable in System Settings → Displays for best results"
    }

    private static func checkViaPlist() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.CoreBrightness", "CBBlueReductionStatus"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let status = Int(output) {
                return status == 1
            }
        } catch {}

        return false
    }
}
