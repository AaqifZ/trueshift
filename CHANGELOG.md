# Changelog

All notable changes to Trueshift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Renamed to **trueshift**. Earlier private versions were called iris, then
  redshift. Both names belong to other projects. The binary is now `trueshift`,
  the menu bar app is `TrueshiftBar`, the config lives at
  `~/.config/trueshift/config.yaml`, and the agent label is `com.trueshift.agent`.
- Tests run in the `Australia/Sydney` timezone in CI, to match the test fixtures.

## [2.1.0] - 2026-07-25

### Added
- **PWM-Safe mode.** It pins the backlight to 100% and dims the image in
  software. The full backlight stops PWM flicker. The software dim scales the
  gamma table. It works on Apple displays: built-in, Studio Display, and Pro
  Display XDR. Third-party monitors keep their own brightness control.
- `trueshift pwm on|off` — turn PWM-Safe on or off. The setting is sticky.
- `trueshift dim <20-100>` — set the software brightness percent.
- `trueshift pwm-probe` (hidden) — show per-display eligibility and brightness.
  Add `--round-trip` to pin then restore each display.
- TrueshiftBar panel: a PWM-Safe toggle and a software-brightness slider. The
  controls gray out when no display can be pinned.
- `status` shows the PWM-Safe state. `status --json` adds a `pwm_safe` block.

### Notes
- TrueshiftBar applies PWM-Safe. The CLI alone sets the preference only.
- A clean quit restores the backlight. A hard crash leaves the pin. The next
  launch restores the state.
- Trade-off: full backlight plus a software dim raises the black level on LCD
  panels in a dark room. This is normal for this method.

## [2.0.0] - 2026-07-23

### Changed
- **Auto = blue-light reduction only.** The schedule drives color temperature;
  brightness is never touched. Deep red at full brightness is the point.
- New temp-only curve: wake / day / dusk / evening / night, sun-anchored.
  Tunables: `day_temp` (5500), `night_floor` (1000), `deep_red` (true).
- `trueshift set <K>` is now temp-only and STICKY until the next sunrise.
- `trueshift off` is sticky filter-off until the next sunrise.
- TrueshiftBar rebuilt: NSStatusItem + popover panel with Day/Sunset/Night
  presets, a log-scaled live slider (1000–6500K), and Resume Auto.
  Quit / Launch at Login moved to right-click on the menubar icon.

### Added
- `trueshift resume` — clear the manual override, return to the curve.
- GammaLayer: true sub-2700K deep red on ALL displays (internal included)
  at full backlight, maintained by the persistent TrueshiftBar.
  Verified 2026-07-23: internal Apple Silicon displays DO accept gamma from
  persistent processes (the old "no-op" lore was a process-lifetime
  misdiagnosis).
- `trueshift curve` (hidden) — print the day's schedule for verification.

### Removed
- Power-down enforcement, finish line, bedtime — v2 is a control panel,
  not an enforcer.
- Presentation mode (superseded by slider-to-6500K / `trueshift off`).
- All brightness scheduling and sub-2700K brightness compensation.

## [0.2.0] - 2026-01-17

### Added
- Comprehensive test suite for TrueshiftCore (61 tests)
- GitHub Actions CI/CD pipeline
- SwiftLint configuration
- Community contribution guidelines
- Issue and PR templates

## [0.1.0] - 2026-01-17

### Added
- Initial release of Trueshift circadian display controller
- **TrueshiftCore Library**
  - 6-phase day schedule (morning, preSunset, evening, night, powerDown, sleep)
  - Solar time calculations using sunrise/sunset
  - Color temperature conversion (Kelvin to RGB gamma)
  - YAML configuration with sensible defaults
  - Finish line concept for work compression
- **CLI Tool (`trueshift`)**
  - `trueshift auto` - Start automatic adjustment daemon
  - `trueshift off` - Reset display to defaults
  - `trueshift set <temp> <brightness>` - Manual override
  - `trueshift status` - Show current state and schedule
  - `trueshift bedtime <time>` - Set bedtime
  - `trueshift present <minutes>` - Presentation mode
  - `trueshift install` - Install as macOS service
- **Menu Bar App (TrueshiftBar)**
  - System tray integration
  - Real-time status display
  - Quick controls for common actions
- **Configuration**
  - YAML config at `~/.config/trueshift/config.yaml`
  - Customizable temperature values per phase
  - Location-based solar calculations
  - Tonight bedtime override support

### Philosophy
- Based on Jack Kruse blue light research
- Ryan Doris "Finish Line" work compression concept
- Aggressive post-sunset filtering for circadian health

[0.1.0]: https://github.com/AaqifZ/trueshift/releases/tag/v0.1.0
