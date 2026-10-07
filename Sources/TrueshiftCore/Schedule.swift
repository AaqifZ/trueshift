// Schedule.swift
// Temp-only circadian curve, sun-anchored. Brightness is never scheduled.
//
//   wake     sunrise → sunrise+30m       nightFloor → dayTemp
//   day      sunrise+30m → sunset−3h     hold dayTemp
//   dusk     sunset−3h → sunset          dayTemp → 2700
//   evening  sunset → sunset+2h          2700 → nightFloor
//   night    sunset+2h → next sunrise    hold nightFloor

import Foundation
import Solar
import CoreLocation

/// Phases of the day for display adjustment
public enum Phase: String, Codable {
    case wake       // Sunrise → Sunrise+30m: warming up to daylight
    case day        // Sunrise+30m → Sunset−3h: full daylight
    case dusk       // Sunset−3h → Sunset: gradual warmth
    case evening    // Sunset → Sunset+2h: descending to deep red
    case night      // Sunset+2h → next sunrise: deep red hold

    public var description: String {
        switch self {
        case .wake: return "Wake (warming to daylight)"
        case .day: return "Day (no filtering)"
        case .dusk: return "Dusk (gradual warmth)"
        case .evening: return "Evening (descending to red)"
        case .night: return "Night (deep red)"
        }
    }
}

/// Whether the display is following the curve or a sticky manual override
public enum ScheduleMode: Equatable {
    case auto
    case manual(until: Date)
}

/// Current schedule state
public struct ScheduleState {
    public let phase: Phase
    /// Effective target temperature (override-aware)
    public let temperature: Int
    public let mode: ScheduleMode
    /// Next curve anchor (auto) or override end (manual)
    public let nextTransition: Date?
    public let nextPhase: Phase?
    public let sunrise: Date?
    public let sunset: Date?

    public init(phase: Phase, temperature: Int, mode: ScheduleMode,
                nextTransition: Date?, nextPhase: Phase?,
                sunrise: Date?, sunset: Date?) {
        self.phase = phase
        self.temperature = temperature
        self.mode = mode
        self.nextTransition = nextTransition
        self.nextPhase = nextPhase
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Schedule calculator
public struct Schedule {

    /// Anchor between dusk-start and sunset (dusk always ends at 2700K)
    static let duskEndTemp = 2700

    /// Calculate current schedule state (override-aware)
    public static func current(config: TrueshiftConfig, now: Date = Date()) -> ScheduleState {
        let (sunrise, sunset) = solarTimes(
            for: now,
            latitude: config.location.latitude,
            longitude: config.location.longitude
        )

        let auto = autoState(
            now: now,
            sunrise: sunrise,
            sunset: sunset,
            dayTemp: config.dayTemp,
            nightFloor: config.nightFloor
        )

        // Night phase after sunset+2h: next transition is tomorrow's sunrise
        var nextTransition = auto.nextTransition
        if nextTransition == nil, auto.phase == .night {
            nextTransition = nextSunrise(
                after: now,
                latitude: config.location.latitude,
                longitude: config.location.longitude
            )
        }

        // Sticky manual override takes precedence over the curve temperature.
        // Phase stays curve-derived so the menubar glyph remains honest.
        if let override = ConfigManager.activeOverride(in: config, now: now) {
            return ScheduleState(
                phase: auto.phase,
                temperature: override.temp,
                mode: .manual(until: override.until),
                nextTransition: override.until,
                nextPhase: nil, // "next" is the override expiry, not a curve phase
                sunrise: sunrise,
                sunset: sunset
            )
        }

        return ScheduleState(
            phase: auto.phase,
            temperature: auto.temperature,
            mode: .auto,
            nextTransition: nextTransition,
            nextPhase: auto.nextPhase,
            sunrise: sunrise,
            sunset: sunset
        )
    }

    /// The pure curve — no I/O, no clock, no solar lookup. Fully testable.
    public static func autoState(
        now: Date,
        sunrise: Date,
        sunset: Date,
        dayTemp: Int,
        nightFloor: Int
    ) -> (temperature: Int, phase: Phase, nextTransition: Date?, nextPhase: Phase?) {
        let wakeEnd = sunrise.addingTimeInterval(30 * 60)
        let duskStart = sunset.addingTimeInterval(-3 * 3600)
        let eveningEnd = sunset.addingTimeInterval(2 * 3600)
        // Guard against pathological configs (nightFloor above dusk end)
        let eveningFrom = max(duskEndTemp, nightFloor)

        if now < sunrise {
            // Pre-dawn: still night
            return (nightFloor, .night, sunrise, .wake)
        } else if now < wakeEnd {
            let progress = interpolationProgress(now: now, start: sunrise, end: wakeEnd)
            let temp = interpolate(from: nightFloor, to: dayTemp, progress: progress)
            return (temp, .wake, wakeEnd, .day)
        } else if now < duskStart {
            return (dayTemp, .day, duskStart, .dusk)
        } else if now < sunset {
            let progress = interpolationProgress(now: now, start: duskStart, end: sunset)
            let temp = interpolate(from: dayTemp, to: duskEndTemp, progress: progress)
            return (temp, .dusk, sunset, .evening)
        } else if now < eveningEnd {
            let progress = interpolationProgress(now: now, start: sunset, end: eveningEnd)
            let temp = interpolate(from: eveningFrom, to: nightFloor, progress: progress)
            return (temp, .evening, eveningEnd, .night)
        } else {
            // Night hold. Next transition (tomorrow's sunrise) needs a solar
            // lookup — callers fill it in.
            return (nightFloor, .night, nil, .wake)
        }
    }

    /// Next sunrise strictly after `now`.
    /// At 2am this is TODAY's sunrise; after sunrise it is tomorrow's.
    /// `calendar` defines "local" — its time zone should match the coordinates.
    /// Production uses the Mac's calendar; tests pin one so the runner's TZ can't leak in.
    public static func nextSunrise(
        after now: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> Date? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        // CRITICAL: anchor Solar at LOCAL NOON so the UTC date component matches
        // the local date (Sydney is UTC+10/11 — at 8:30am local the UTC date is
        // still yesterday). Load-bearing; do not "simplify".
        guard let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) else {
            return nil
        }
        if let todaySunrise = Solar(for: noonToday, coordinate: coordinate)?.sunrise,
           todaySunrise > now {
            return todaySunrise
        }
        guard let noonTomorrow = calendar.date(byAdding: .day, value: 1, to: noonToday) else {
            return nil
        }
        return Solar(for: noonTomorrow, coordinate: coordinate)?.sunrise
    }

    // MARK: - Private

    /// Today's solar times (noon-anchored), with a fixed 07:00/19:00 fallback
    /// so polar edge cases still produce a curve-shaped day.
    private static func solarTimes(for now: Date, latitude: Double, longitude: Double) -> (Date, Date) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let calendar = Calendar.current
        let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let solar = Solar(for: noonToday, coordinate: coordinate)

        if let sunrise = solar?.sunrise, let sunset = solar?.sunset {
            return (sunrise, sunset)
        }

        let fallbackSunrise = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        let fallbackSunset = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        return (fallbackSunrise, fallbackSunset)
    }

    private static func interpolationProgress(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1.0 }
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(1, elapsed / total))
    }

    private static func interpolate(from: Int, to: Int, progress: Double) -> Int {
        Int(Double(from) + (Double(to - from) * progress))
    }
}
