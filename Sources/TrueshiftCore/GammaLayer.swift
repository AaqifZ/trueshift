// GammaLayer.swift
//
// Sub-2700K deep red at FULL brightness, on ALL displays (internal included).
//
// ⚠️  PERSISTENT PROCESSES ONLY — never call from the CLI.
// Gamma tables are process-lifetime: WindowServer restores them the moment
// the writing process exits. A short-lived CLI writing gamma produces a ~1s
// red flash and nothing else (the six-month "red flash" bug). TrueshiftBar,
// which stays alive, is the only legitimate caller.
//
// Verified 2026-07-23 on M4/macOS 26: a persistent process CAN hold deep-red
// gamma on the built-in display. (The old "internal displays ignore gamma"
// lore was a misdiagnosis confounded by process-lifetime reverts.)
//
// Math: the CoreBrightness pipeline is already warming the display to 2700K
// (its hardware floor). We layer the REMAINING warmth on top, channel-wise:
//     residual(k) = fromKelvin(k) / fromKelvin(2700)
// For k ≥ 2700 every ratio clamps to 1.0 → identity table, so one formula
// covers both "layer active" and "layer off". Composite ≈ fromKelvin(k) at
// an unchanged backlight.

import Foundation
import CoreGraphics

public enum GammaLayer {

    /// Gamma channel drift below this is considered "already applied"
    static let skipThreshold: Float = 0.005

    /// The residual gamma to layer on top of a 2700K pipeline so the
    /// composite reaches `kelvin`. Identity for kelvin ≥ 2700.
    public static func residual(forTarget kelvin: Int) -> GammaRGB {
        let clamped = max(1000, min(6500, kelvin))
        let target = GammaRGB.fromKelvin(clamped)
        let base = GammaRGB.fromKelvin(2700)
        return GammaRGB(
            red: min(1.0, target.red / max(base.red, 0.001)),
            green: min(1.0, target.green / max(base.green, 0.001)),
            blue: min(1.0, target.blue / max(base.blue, 0.001))
        )
    }

    /// Idempotently sync the gamma layer on all active displays.
    ///
    /// The color residual is uniform; `dims` supplies a per-display brightness
    /// multiplier (PWM-safe software dimming), folded into the same table via
    /// `withBrightness`. Displays absent from `dims` render at full brightness.
    /// No-op when a display's table already matches its dimmed residual.
    @discardableResult
    public static func sync(targetKelvin: Int, dims: [CGDirectDisplayID: Float] = [:]) -> Bool {
        let base = residual(forTarget: targetKelvin)
        var success = true
        for displayID in DisplayController.getActiveDisplays() {
            let dim = dims[displayID] ?? 1.0
            let gamma = base.withBrightness(dim)
            if let current = readTable(from: displayID),
               abs(current.red - gamma.red) < skipThreshold,
               abs(current.green - gamma.green) < skipThreshold,
               abs(current.blue - gamma.blue) < skipThreshold {
                continue
            }
            if !writeTable(gamma, to: displayID) {
                success = false
            }
        }
        return success
    }

    /// Restore identity gamma on all displays (layer fully off — no color, no dim).
    /// Only for genuine teardown; the dim-aware paths call `sync` directly.
    public static func clear() {
        sync(targetKelvin: 6500)
    }

    // MARK: - Gamma Tables

    private static func writeTable(_ gamma: GammaRGB, to displayID: CGDirectDisplayID) -> Bool {
        let tableSize = 256
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)

        for i in 0..<tableSize {
            let x = CGGammaValue(i) / CGGammaValue(tableSize - 1)
            redTable[i] = x * CGGammaValue(gamma.red)
            greenTable[i] = x * CGGammaValue(gamma.green)
            blueTable[i] = x * CGGammaValue(gamma.blue)
        }

        return CGSetDisplayTransferByTable(
            displayID,
            UInt32(tableSize),
            redTable,
            greenTable,
            blueTable
        ) == .success
    }

    private static func readTable(from displayID: CGDirectDisplayID) -> GammaRGB? {
        let tableSize = 256
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)
        var sampleCount: UInt32 = 0

        let result = CGGetDisplayTransferByTable(
            displayID,
            UInt32(tableSize),
            &redTable,
            &greenTable,
            &blueTable,
            &sampleCount
        )

        guard result == .success, sampleCount > 0 else { return nil }

        return GammaRGB(
            red: redTable[Int(sampleCount) - 1],
            green: greenTable[Int(sampleCount) - 1],
            blue: blueTable[Int(sampleCount) - 1]
        )
    }
}
