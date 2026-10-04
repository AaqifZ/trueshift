import Foundation
import CoreGraphics
import CoreBrightnessBridge

/// Color-temperature control via the CoreBrightness (Night Shift) pipeline.
///
/// v2: this is CCT-only. Brightness is NEVER written by the schedule — the
/// user controls it. Sub-2700K deep red is layered on top by `GammaLayer`,
/// which only persistent processes (TrueshiftBar) may drive: gamma tables are
/// process-lifetime, so a short-lived CLI writing gamma produces a ~1s flash
/// and nothing else (the six-month "red flash" bug).
public struct DisplayController {

    private static var cctMin: Float = 2700
    private static var cctMax: Float = 6000
    private static var cctRangeQueried = false

    /// CCT drift below this is considered "already applied" — skip setCCT
    private static let cctSkipThreshold: Float = 25

    private static func queryCCTRange() {
        guard !cctRangeQueried else { return }
        var min: Float = 0, max: Float = 0, def: Float = 0
        if CBBridge_getCCTRange(&min, &max, &def), min > 0, max > min {
            cctMin = min
            cctMax = max
        }
        cctRangeQueried = true
    }

    // MARK: - Public API

    /// Apply a color temperature via the CoreBrightness pipeline.
    /// The pipeline clamps to its hardware range (2700–6000K on M-series);
    /// sub-2700K targets land at 2700K here and go deeper via `GammaLayer`.
    @discardableResult
    public static func apply(kelvin: Int, verbose: Bool = false) -> Bool {
        guard !getActiveDisplays().isEmpty else {
            if verbose { print("Error: No displays found") }
            return false
        }

        guard CBBridge_initialize() else {
            if verbose { print("Error: CoreBrightness unavailable") }
            return false
        }

        queryCCTRange()

        let clampedCCT = max(cctMin, min(cctMax, Float(kelvin)))

        // Read current pipeline state. Re-arming (setEnabled + setMode) makes
        // CoreBrightness replay its transition animation — so only re-arm when
        // the pipeline is actually down or has lost our setting (after
        // `trueshift off`, reboot, or a manual Night Shift toggle).
        var pipelineEnabled = false
        var pipelineMode: Int32 = -1
        let statusKnown = CBBridge_getStatus(&pipelineEnabled, &pipelineMode)

        var currentCCT: Float = 0
        let cctKnown = CBBridge_getCCT(&currentCCT) && currentCCT > 0
        let cctDelta = cctKnown ? abs(currentCCT - clampedCCT) : Float.infinity

        let needsRearm: Bool
        if statusKnown {
            needsRearm = !pipelineEnabled || pipelineMode != 2
        } else {
            // Status unreadable (private API shifted?) — fall back to CCT drift:
            // a large delta means something reset the display out from under us.
            needsRearm = cctDelta > 500
        }

        if needsRearm {
            CBBridge_setEnabled(true)
            CBBridge_setMode(2)
        }

        // Small schedule drift (~80K per 5-min tick during transitions) is
        // nudged silently via setCCT; no-op ticks are skipped entirely.
        var cctOk = true
        if needsRearm || cctDelta > cctSkipThreshold {
            cctOk = CBBridge_setCCT(clampedCCT, true)
        }

        if verbose {
            print("CoreBrightness: CCT=\(clampedCCT) (from \(kelvin)K)")
            print("  pipeline: \(statusKnown ? (pipelineEnabled ? "enabled, mode \(pipelineMode)" : "disabled") : "unknown"), rearm: \(needsRearm ? "YES" : "no"), cctDelta: \(cctKnown ? String(format: "%.0f", cctDelta) : "?")")
            print("  setCCT: \(cctOk ? "OK" : "FAILED")")
        }

        return cctOk
    }

    /// Filter fully off: pipeline disabled, gamma restored.
    ///
    /// `restoreBrightness` (default true) also slams the built-in back to 100%
    /// — one-time cleanup of the v1 schedule's dimming, kept for CLI `off`/
    /// `uninstall`. TrueshiftBar passes `false`: in v2 brightness is owned by
    /// PWM-safe (or the user), never by this reset, so it must not clobber a
    /// value the engine just restored on a PWM-off transition.
    @discardableResult
    public static func reset(restoreBrightness: Bool = true) -> Bool {
        let displays = getActiveDisplays()
        guard !displays.isEmpty else { return false }

        if CBBridge_initialize() {
            CBBridge_setCCT(6000, true)
            CBBridge_setEnabled(false)

            if restoreBrightness {
                for displayID in displays where isBuiltIn(displayID) {
                    DisplayServicesBridge.setBrightness(displayID, brightness: 1.0)
                }
            }
        }

        CGDisplayRestoreColorSyncSettings()
        return true
    }

    // MARK: - PWM-Safe (backlight pin)

    /// Whether a display's backlight can be pinned (Apple-controlled panels only).
    /// Falls back to `CGDisplayIsBuiltin` if the CanChange symbol is missing.
    public static func isPWMEligible(_ displayID: CGDirectDisplayID) -> Bool {
        if DisplayServicesBridge._canChange != nil {
            return DisplayServicesBridge.canChangeBrightness(displayID)
        }
        return isBuiltIn(displayID)
    }

    /// Current hardware brightness (0.0–1.0), or nil if unreadable.
    public static func getBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        DisplayServicesBridge.getBrightness(displayID)
    }

    /// Pin the backlight to 100% and disable ambient compensation so the
    /// sensor stops fighting the pin. Returns false if the display can't be driven.
    @discardableResult
    public static func pinBacklight(_ displayID: CGDirectDisplayID) -> Bool {
        guard isPWMEligible(displayID) else { return false }
        DisplayServicesBridge.setAmbientCompensation(displayID, enabled: false)
        return DisplayServicesBridge.setBrightness(displayID, brightness: 1.0)
    }

    /// Restore a display's brightness to a saved value and re-enable ambient
    /// compensation. Used when PWM-safe is turned off (NOT via `reset()`).
    @discardableResult
    public static func restoreBacklight(_ displayID: CGDirectDisplayID, to brightness: Float) -> Bool {
        let ok = DisplayServicesBridge.setBrightness(displayID, brightness: brightness)
        DisplayServicesBridge.setAmbientCompensation(displayID, enabled: true)
        return ok
    }

    /// Current pipeline CCT (nil when CoreBrightness is unavailable)
    public static func getCurrentKelvin() -> Int? {
        guard CBBridge_initialize() else { return nil }
        var cct: Float = 0
        guard CBBridge_getCCT(&cct), cct > 0 else { return nil }
        return Int(cct)
    }

    public static var displayCount: Int {
        getActiveDisplays().count
    }

    // MARK: - Display Enumeration (shared with GammaLayer)

    public static func isBuiltIn(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }

    public static func getActiveDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == .success, displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard result == .success else { return [] }

        return displays
    }
}

// MARK: - DisplayServices Bridge

enum DisplayServicesBridge {
    static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let h = handle, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }

    typealias SetBrightnessFunc = @convention(c) (UInt32, Float) -> Int32
    typealias GetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias CanChangeFunc = @convention(c) (UInt32) -> Bool
    typealias EnableAmbientFunc = @convention(c) (UInt32, Bool) -> Int32

    static let _setBrightness: SetBrightnessFunc? = sym("DisplayServicesSetBrightness", as: SetBrightnessFunc.self)
    static let _getBrightness: GetBrightnessFunc? = sym("DisplayServicesGetBrightness", as: GetBrightnessFunc.self)
    static let _canChange: CanChangeFunc? = sym("DisplayServicesCanChangeBrightness", as: CanChangeFunc.self)
    // May be absent on some macOS builds — always dlsym-guarded at the call site.
    static let _enableAmbient: EnableAmbientFunc? = sym("DisplayServicesEnableAmbientLightCompensation", as: EnableAmbientFunc.self)

    @discardableResult
    static func setBrightness(_ displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        guard let fn = _setBrightness else { return false }
        return fn(displayID, brightness) == 0
    }

    /// Current hardware brightness (0.0–1.0), or nil if unreadable.
    static func getBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        guard let fn = _getBrightness else { return nil }
        var value: Float = 0
        return fn(displayID, &value) == 0 ? value : nil
    }

    /// Whether DisplayServices can drive this display's brightness
    /// (true for Apple-controlled panels: built-in, Studio Display, Pro Display XDR).
    static func canChangeBrightness(_ displayID: CGDirectDisplayID) -> Bool {
        _canChange?(displayID) ?? false
    }

    /// Toggle ambient light compensation (auto-brightness). No-op if the
    /// symbol is unavailable — the caller falls back to drift re-assertion.
    @discardableResult
    static func setAmbientCompensation(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard let fn = _enableAmbient else { return false }
        return fn(displayID, enabled) == 0
    }
}
