# Changelog

All notable changes to trueshift are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-11

v0.1.0 is the first public release. trueshift was built and used privately for about nine months before this release. Those private versions were not published.

### Added
- Color schedule from the real sunrise and sunset at your location: wake, day, dusk, evening and night phases.
- Deep red down to 1000K through the menu bar app (TrueshiftBar). CoreBrightness covers 2700K and up when the app is not running.
- `trueshift set`, `off` and `resume`. A manual change holds until the next sunrise.
- `trueshift status` and `status --json`.
- `trueshift curve` prints one day's schedule. `--date`, `--latitude` and `--longitude` preview any day and place.
- `trueshift install` and `uninstall` for the background agent (every 5 minutes).
- PWM-safe mode (`trueshift pwm on|off`, `trueshift dim 20-100`): pins the backlight at 100% on Apple displays and dims the image in software.
- Tests for the schedule, config, color conversion and gamma layer. CI runs them under UTC and Australia/Sydney.

[Unreleased]: https://github.com/AaqifZ/trueshift/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AaqifZ/trueshift/releases/tag/v0.1.0
