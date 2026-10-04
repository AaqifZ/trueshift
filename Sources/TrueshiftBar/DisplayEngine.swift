// DisplayEngine.swift
// Single source of truth for display writes in TrueshiftBar.
//
// One timer owns every apply. The slider, presets, schedule, and override
// never write to the display directly — they set inputs, the tick resolves:
//
//     effectiveTarget = animation ?? transientDrag ?? override ?? schedule
//
// so timers can never fight a drag. All applies are idempotent (the CCT
// pipeline and GammaLayer both skip no-ops), so a 300ms tick is cheap.

import Foundation
import AppKit
import Combine
import CoreGraphics
import TrueshiftCore

final class DisplayEngine: ObservableObject {

    // MARK: - Published UI state (main thread)

    @Published var temperature: Int = 5500
    @Published var mode: ScheduleMode = .auto
    @Published var phase: Phase = .day
    @Published var nextTransition: Date? = nil
    @Published var nextPhase: Phase? = nil

    // PWM-safe UI state
    @Published var pwmEnabled: Bool = false
    @Published var softwareBrightness: Double = 1.0
    /// At least one connected display can be pinned (controls availability)
    @Published var pwmEligible: Bool = false

    // MARK: - Engine state (engine queue only)

    private var config: TrueshiftConfig?
    private var lastSeenMtime: Date?

    /// Live slider value while dragging (not yet committed)
    private var transientDragValue: Int?
    private var isDragging = false

    /// Preset / resume ease animation, evaluated in log-Kelvin space
    private struct Animation {
        let from: Int
        let to: Int
        let start: Date
        let duration: TimeInterval
        /// Commit a sticky override at `to` when the animation completes
        let commitOverride: Bool
    }
    private var animation: Animation?

    /// Filter-off guard: reset() must run once, not every tick (re-running
    /// would churn the pipeline; re-arming it replays the Night Shift animation)
    private var didReset = false

    private var lastEffectiveTarget: Int?

    // PWM-safe engine state (engine queue only)
    /// Displays whose backlight we currently hold pinned at 100%
    private var pinnedDisplays: Set<CGDirectDisplayID> = []
    /// Pre-pin brightness snapshot, restored on a clean disable/quit
    private var prePinBrightness: [CGDirectDisplayID: Float] = [:]
    /// True once the enable transition (snapshot) has run for the current on-state
    private var pwmActive = false
    /// Throttles the brightness drift re-assert (every 3rd tick ≈ 0.9s)
    private var tickCounter = 0
    /// Live brightness while dragging the slider (not yet written to config)
    private var transientBrightness: Double?

    private let queue = DispatchQueue(label: "trueshift.engine", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var fastTicks = false

    // MARK: - Lifecycle

    init() {
        startTimer(fast: false)
        registerSystemCallbacks()
    }

    private func startTimer(fast: Bool) {
        fastTicks = fast
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(fast ? 100 : 300))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func registerSystemCallbacks() {
        // Sleep wipes gamma; force a full re-apply on wake
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.forceReapply() }
        }
        // Display plug/unplug — new displays need the layer applied
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.forceReapply() }
        }
    }

    private func forceReapply() {
        lastEffectiveTarget = nil
        didReset = false
        lastSeenMtime = nil
        // Sleep/display-change can reset the backlight — drop pin bookkeeping
        // (but keep snapshots) so the next tick re-pins eligible displays.
        pinnedDisplays.removeAll()
        tick()
    }

    // MARK: - User actions (any thread)

    /// Slider moved (still dragging)
    func sliderChanged(kelvin: Int) {
        queue.async {
            self.transientDragValue = kelvin
            self.animation = nil
            if !self.isDragging {
                self.isDragging = true
                DispatchQueue.main.async { self.startTimer(fast: true) }
            }
        }
    }

    /// Slider released — commit sticky override
    func sliderCommitted(kelvin: Int) {
        queue.async {
            self.isDragging = false
            self.transientDragValue = nil
            self.commitOverride(temp: kelvin)
            DispatchQueue.main.async { self.startTimer(fast: false) }
        }
    }

    /// Preset tapped — ease over ~1s, then commit sticky override
    func setPreset(kelvin: Int) {
        queue.async {
            let from = self.lastEffectiveTarget ?? self.currentScheduleTemp()
            self.transientDragValue = nil
            self.animation = Animation(from: from, to: kelvin, start: Date(),
                                       duration: 1.0, commitOverride: true)
            DispatchQueue.main.async { self.startTimer(fast: true) }
        }
    }

    /// Resume Auto — clear override, ease back to the curve
    func resumeAuto() {
        queue.async {
            try? ConfigManager.clearManualOverride()
            self.reloadConfig()
            let from = self.lastEffectiveTarget ?? self.currentScheduleTemp()
            let to = self.currentScheduleTemp()
            self.transientDragValue = nil
            self.animation = Animation(from: from, to: to, start: Date(),
                                       duration: 1.0, commitOverride: false)
            DispatchQueue.main.async { self.startTimer(fast: true) }
        }
    }

    // MARK: - Tick (engine queue)

    private func tick() {
        // Cheap change detection: reload config only when the file changed
        // (CLI `trueshift set` reaches the bar within one tick)
        let mtime = ConfigManager.modificationDate()
        if config == nil || mtime != lastSeenMtime {
            reloadConfig()
        }
        guard let config else { return }

        let state = Schedule.current(config: config)
        let target = resolveTarget(scheduleTemp: state.temperature)

        // Reconcile the backlight pin and compute per-display software dims.
        let dims = reconcilePWM(config: config)

        applyTarget(target, deepRed: config.deepRed, dims: dims)
        lastEffectiveTarget = target

        publishUIState(state: state, effectiveTemp: target, config: config, dims: dims)
    }

    // MARK: - PWM-safe reconciliation (engine queue)

    /// Bring the hardware pin in line with config and return the per-display
    /// dim map (only pinned displays are dimmed — externals we can't pin keep
    /// their own hardware brightness). Idempotent; safe every tick.
    private func reconcilePWM(config: TrueshiftConfig) -> [CGDirectDisplayID: Float] {
        guard config.pwmEnabled else {
            if pwmActive { disablePWM() }
            return [:]
        }

        // Enable transition: snapshot pre-pin brightness once.
        if !pwmActive {
            snapshotPrePin(config: config)
            pwmActive = true
        }

        tickCounter &+= 1
        let reassert = (tickCounter % 3 == 0)
        let dimValue = Float(transientBrightness ?? config.softwareBrightness)

        for id in DisplayController.getActiveDisplays() where DisplayController.isPWMEligible(id) {
            if !pinnedDisplays.contains(id) {
                // New / post-wake display: snapshot if we have none, then pin.
                if prePinBrightness[id] == nil {
                    prePinBrightness[id] = DisplayController.getBrightness(id) ?? 1.0
                }
                DisplayController.pinBacklight(id)
                pinnedDisplays.insert(id)
            } else if reassert {
                // Auto-brightness / user drifted the pin — snap it back.
                if let b = DisplayController.getBrightness(id), b < 0.99 {
                    DisplayController.pinBacklight(id)
                }
            }
        }

        var dims: [CGDirectDisplayID: Float] = [:]
        for id in pinnedDisplays { dims[id] = dimValue }
        return dims
    }

    /// Capture each eligible display's brightness before pinning. The built-in
    /// prefers the persisted snapshot (survives relaunch/crash); externals get
    /// an in-memory snapshot only — their IDs aren't reboot-stable.
    private func snapshotPrePin(config: TrueshiftConfig) {
        for id in DisplayController.getActiveDisplays() where DisplayController.isPWMEligible(id) {
            if DisplayController.isBuiltIn(id) {
                if let saved = config.pwmSafe?.savedBrightness {
                    prePinBrightness[id] = Float(saved)
                } else {
                    let current = DisplayController.getBrightness(id) ?? 1.0
                    prePinBrightness[id] = current
                    try? ConfigManager.setSavedBrightness(Double(current))
                }
            } else if prePinBrightness[id] == nil {
                prePinBrightness[id] = DisplayController.getBrightness(id) ?? 1.0
            }
        }
    }

    /// Restore every pinned display's brightness and re-enable ambient
    /// compensation, then forget the snapshots. Clears the persisted snapshot
    /// so the next fresh enable re-captures the real value.
    private func disablePWM() {
        for id in pinnedDisplays {
            let restore = prePinBrightness[id] ?? 1.0
            DisplayController.restoreBacklight(id, to: restore)
        }
        pinnedDisplays.removeAll()
        prePinBrightness.removeAll()
        pwmActive = false
        try? ConfigManager.setSavedBrightness(nil)
    }

    /// Clean-quit teardown: restore brightness so the machine returns to normal.
    /// The sticky config stays enabled, so relaunch re-pins. A hard crash skips
    /// this — the pin persists and self-heals on next launch. Runs on main.
    func teardownForQuit() {
        queue.sync {
            for id in pinnedDisplays {
                let restore = prePinBrightness[id] ?? 1.0
                DisplayController.restoreBacklight(id, to: restore)
            }
        }
    }

    // MARK: - PWM user actions

    func setPWM(enabled: Bool) {
        queue.async {
            try? ConfigManager.setPWMEnabled(enabled)
            self.reloadConfig()
            self.tick()
        }
    }

    /// Live preview while dragging — in-memory only, no config write.
    func previewBrightness(_ value: Double) {
        queue.async {
            self.transientBrightness = min(1.0, max(pwmBrightnessFloor, value))
            self.tick()
        }
    }

    /// Commit on release — persist to config and clear the transient.
    func setSoftwareBrightness(_ value: Double) {
        queue.async {
            self.transientBrightness = nil
            try? ConfigManager.setSoftwareBrightness(value)
            self.reloadConfig()
            self.tick()
        }
    }

    private func reloadConfig() {
        config = try? ConfigManager.createDefaultIfNeeded()
        lastSeenMtime = ConfigManager.modificationDate()
    }

    private func currentScheduleTemp() -> Int {
        guard let config else { return 5500 }
        return Schedule.current(config: config).temperature
    }

    private func resolveTarget(scheduleTemp: Int) -> Int {
        if let anim = animation {
            let progress = min(1.0, Date().timeIntervalSince(anim.start) / anim.duration)
            if progress >= 1.0 {
                animation = nil
                if anim.commitOverride {
                    commitOverride(temp: anim.to)
                }
                if !isDragging {
                    DispatchQueue.main.async { self.startTimer(fast: false) }
                }
                return anim.to
            }
            // Ease-in-out in log-Kelvin space (perceptually even)
            let eased = 0.5 - 0.5 * cos(progress * .pi)
            let logK = log(Double(anim.from)) + (log(Double(anim.to)) - log(Double(anim.from))) * eased
            return Int(exp(logK))
        }

        if let drag = transientDragValue {
            return drag
        }

        return scheduleTemp
    }

    private func applyTarget(_ target: Int, deepRed: Bool, dims: [CGDirectDisplayID: Float]) {
        let dimActive = !dims.isEmpty

        if target >= 6500 {
            if dimActive {
                // Filter off but PWM dimming active: identity color, dim only.
                // Must NOT reset() — that tears down the pipeline; the pin stays.
                didReset = false
                GammaLayer.sync(targetKelvin: 6500, dims: dims)
                return
            }
            // Fully off — reset once; calling apply() here would re-arm the
            // pipeline and replay the Night Shift animation. Pass
            // restoreBrightness:false so we never clobber a PWM-restored value.
            if !didReset {
                DisplayController.reset(restoreBrightness: false)
                GammaLayer.clear()
                didReset = true
            }
            return
        }

        didReset = false
        DisplayController.apply(kelvin: target)
        if deepRed || dimActive {
            GammaLayer.sync(targetKelvin: target, dims: dims)
        } else {
            GammaLayer.clear()
        }
    }

    private func commitOverride(temp: Int) {
        guard let config else { return }
        let until = Schedule.nextSunrise(
            after: Date(),
            latitude: config.location.latitude,
            longitude: config.location.longitude
        ) ?? Date().addingTimeInterval(12 * 3600)
        try? ConfigManager.setManualOverride(temp: temp, until: until)
        reloadConfig()
    }

    private func publishUIState(state: ScheduleState, effectiveTemp: Int,
                                config: TrueshiftConfig, dims: [CGDirectDisplayID: Float]) {
        let pwmOn = config.pwmEnabled
        let brightness = config.softwareBrightness
        let eligible = DisplayController.getActiveDisplays().contains {
            DisplayController.isPWMEligible($0)
        }
        DispatchQueue.main.async {
            if self.temperature != effectiveTemp { self.temperature = effectiveTemp }
            if self.mode != state.mode { self.mode = state.mode }
            if self.phase != state.phase { self.phase = state.phase }
            if self.nextTransition != state.nextTransition { self.nextTransition = state.nextTransition }
            if self.nextPhase != state.nextPhase { self.nextPhase = state.nextPhase }
            if self.pwmEnabled != pwmOn { self.pwmEnabled = pwmOn }
            if self.softwareBrightness != brightness { self.softwareBrightness = brightness }
            if self.pwmEligible != eligible { self.pwmEligible = eligible }
        }
    }
}
