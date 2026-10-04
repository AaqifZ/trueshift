// TrueshiftBarApp.swift
// Menu bar app: status icon + control panel.
//
// NSStatusItem instead of SwiftUI MenuBarExtra because the panel needs
// left-click (popover) AND right-click (Quit / Launch at Login menu) —
// MenuBarExtra has no secondary-click support.

import SwiftUI
import AppKit
import Combine
import ServiceManagement
import TrueshiftCore

@main
struct TrueshiftBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() } // no windows; everything lives in the status item
    }
}

// MARK: - App Delegate (status item + popover + right-click menu)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let engine = DisplayEngine()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auto-enable launch at login on first run
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(engine: engine)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        // Keep the menubar label in sync with the engine
        engine.$temperature
            .combineLatest(engine.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] temperature, phase in
                self?.updateButton(temperature: temperature, phase: phase)
            }
            .store(in: &cancellables)
    }

    private func updateButton(temperature: Int, phase: Phase) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch phase {
        case .wake: symbol = "sunrise.fill"
        case .day: symbol = "sun.max.fill"
        case .dusk: symbol = "sun.haze.fill"
        case .evening: symbol = "sunset.fill"
        case .night: symbol = "moon.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Trueshift")
        button.title = " \(temperature)"
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Trueshift",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        // Assign temporarily so the click opens the menu; menuDidClose removes
        // it again so LEFT click keeps opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean quit: return the backlight to normal. The sticky config stays
        // enabled, so a relaunch re-pins. A hard crash skips this and self-heals.
        engine.teardownForQuit()
    }

    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
}

// MARK: - Design System

struct TrueshiftColors {
    // Dynamic background based on color temperature
    static func ambientGradient(for kelvin: Int) -> LinearGradient {
        let warmth = 1.0 - (Double(kelvin - 1800) / Double(6500 - 1800))
        let clampedWarmth = max(0, min(1, warmth))

        // Neutral dark → warm amber based on temperature
        let baseColor = Color(red: 0.12, green: 0.12, blue: 0.13)
        let warmColor = Color(red: 0.18 + (clampedWarmth * 0.08),
                              green: 0.14 + (clampedWarmth * 0.04),
                              blue: 0.12)

        return LinearGradient(
            colors: [warmColor, baseColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let accent = Color(red: 1.0, green: 0.72, blue: 0.42) // Warm amber
    static let accentSubtle = Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.15)
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let divider = Color.white.opacity(0.08)
}

// MARK: - Log-scale slider mapping

enum KelvinScale {
    static let minK = 1000.0
    static let maxK = 6500.0

    /// Kelvin → slider position [0,1] (log-scaled: the red zone gets room)
    static func position(for kelvin: Int) -> Double {
        let k = min(max(Double(kelvin), minK), maxK)
        return log(k / minK) / log(maxK / minK)
    }

    /// Slider position [0,1] → Kelvin, snapped to 50K
    static func kelvin(at position: Double) -> Int {
        let k = minK * exp(position * log(maxK / minK))
        return Int((k / 50.0).rounded() * 50.0)
    }
}

// MARK: - Panel

struct MenuBarPanel: View {
    @ObservedObject var engine: DisplayEngine
    @State private var sliderPosition: Double = 0.5
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(engine: engine)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle()
                .fill(TrueshiftColors.divider)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Presets
            HStack(spacing: 8) {
                PresetButton(label: "Day", kelvin: 5500, engine: engine)
                PresetButton(label: "Sunset", kelvin: 2700, engine: engine)
                PresetButton(label: "Night", kelvin: 1000, engine: engine)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Slider
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TrueshiftColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { sliderPosition },
                            set: { newValue in
                                sliderPosition = newValue
                                engine.sliderChanged(kelvin: KelvinScale.kelvin(at: newValue))
                            }
                        ),
                        in: 0...1
                    ) { editing in
                        isDragging = editing
                        if !editing {
                            engine.sliderCommitted(kelvin: KelvinScale.kelvin(at: sliderPosition))
                        }
                    }
                    .tint(TrueshiftColors.accent)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TrueshiftColors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(TrueshiftColors.divider)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // PWM-Safe: pin backlight, dim in software
            PWMSafeSection(engine: engine)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Rectangle()
                .fill(TrueshiftColors.divider)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Footer: Resume Auto (manual) / next transition (auto)
            PanelFooter(engine: engine)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 260)
        .background(TrueshiftColors.ambientGradient(for: engine.temperature))
        .onAppear {
            sliderPosition = KelvinScale.position(for: engine.temperature)
        }
        .onReceive(engine.$temperature) { temp in
            // Track the curve/animation unless the user is mid-drag
            if !isDragging {
                sliderPosition = KelvinScale.position(for: temp)
            }
        }
    }
}

// MARK: - Header

struct PanelHeader: View {
    @ObservedObject var engine: DisplayEngine

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: 38, height: 38)

                Image(systemName: isManual ? "hand.raised.fill" : phaseIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(phaseColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(engine.temperature)K")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(TrueshiftColors.textPrimary)

                Text(modeLine)
                    .font(.system(size: 11))
                    .foregroundColor(TrueshiftColors.textSecondary)
            }

            Spacer()
        }
    }

    private var isManual: Bool {
        if case .manual = engine.mode { return true }
        return false
    }

    private var modeLine: String {
        switch engine.mode {
        case .auto:
            return "\(phaseName) · Auto"
        case .manual(let until):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Manual until \(formatter.string(from: until))"
        }
    }

    private var phaseName: String {
        engine.phase.rawValue.capitalized
    }

    private var phaseIcon: String {
        switch engine.phase {
        case .wake: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sun.haze.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.fill"
        }
    }

    private var phaseColor: Color {
        if isManual { return TrueshiftColors.accent }
        switch engine.phase {
        case .wake: return Color(red: 1.0, green: 0.75, blue: 0.45)
        case .day: return Color(red: 1.0, green: 0.85, blue: 0.4)
        case .dusk: return Color(red: 1.0, green: 0.65, blue: 0.35)
        case .evening: return Color(red: 1.0, green: 0.5, blue: 0.3)
        case .night: return Color(red: 0.85, green: 0.35, blue: 0.25)
        }
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let label: String
    let kelvin: Int
    @ObservedObject var engine: DisplayEngine
    @State private var isHovering = false

    var body: some View {
        Button(action: { engine.setPreset(kelvin: kelvin) }) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TrueshiftColors.textPrimary)
                Text("\(kelvin)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TrueshiftColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Footer

struct PanelFooter: View {
    @ObservedObject var engine: DisplayEngine
    @State private var isHoveringResume = false

    var body: some View {
        Group {
            switch engine.mode {
            case .manual:
                Button(action: { engine.resumeAuto() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                        Text("Resume Auto")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(TrueshiftColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isHoveringResume ? TrueshiftColors.accent.opacity(0.25) : TrueshiftColors.accentSubtle)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringResume = $0 }

            case .auto:
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundColor(TrueshiftColors.textTertiary)
                    if let next = engine.nextTransition, let nextPhase = engine.nextPhase {
                        Text("\(nextPhase.rawValue) at \(Self.timeFormatter.string(from: next))")
                            .font(.system(size: 11))
                            .foregroundColor(TrueshiftColors.textSecondary)
                    } else {
                        Text("following the sun")
                            .font(.system(size: 11))
                            .foregroundColor(TrueshiftColors.textSecondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

// MARK: - PWM-Safe Section

struct PWMSafeSection: View {
    @ObservedObject var engine: DisplayEngine
    @State private var brightnessDraft: Double = 1.0
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rays")
                    .font(.system(size: 12))
                    .foregroundColor(engine.pwmEligible ? TrueshiftColors.accent : TrueshiftColors.textTertiary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("PWM-Safe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(engine.pwmEligible ? TrueshiftColors.textPrimary : TrueshiftColors.textTertiary)
                    Text(engine.pwmEligible ? "Backlight 100%, dim in software" : "Unavailable on this display")
                        .font(.system(size: 9))
                        .foregroundColor(TrueshiftColors.textTertiary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { engine.pwmEnabled },
                    set: { engine.setPWM(enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TrueshiftColors.accent)
                .disabled(!engine.pwmEligible)
            }

            if engine.pwmEnabled && engine.pwmEligible {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min")
                        .font(.system(size: 10))
                        .foregroundColor(TrueshiftColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { isDragging ? brightnessDraft : engine.softwareBrightness },
                            set: { newValue in
                                brightnessDraft = newValue
                                engine.previewBrightness(newValue)
                            }
                        ),
                        in: 0.2...1.0
                    ) { editing in
                        isDragging = editing
                        if editing {
                            brightnessDraft = engine.softwareBrightness
                        } else {
                            engine.setSoftwareBrightness(brightnessDraft)
                        }
                    }
                    .tint(TrueshiftColors.accent)

                    Text("\(Int((isDragging ? brightnessDraft : engine.softwareBrightness) * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(TrueshiftColors.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}
