# Contributing

Bug reports and small pull requests are welcome.

## Set up

1. Install macOS 14 or later and Xcode (the tests need it).
2. Clone and build:
   ```bash
   git clone https://github.com/AaqifZ/trueshift.git
   cd trueshift
   swift build
   ```
3. Run the tests:
   ```bash
   swift test
   ```

## Make a change

1. Make a branch from `main`.
2. Keep the change small and focused.
3. Add or update tests in `Tests/TrueshiftCoreTests/` for changes to the core.
4. Add a line to `CHANGELOG.md` under `[Unreleased]`.
5. Open a pull request. Say what changed, why, and how you tested it.

## Key ideas

- **Schedule.** Five phases anchored to your real sunrise and sunset: wake, day, dusk, evening, night. See `Sources/TrueshiftCore/Schedule.swift`.
- **Two writers.** The CLI and background agent use CoreBrightness only (2700K and up). The menu bar app adds gamma for deep red below 2700K, because gamma changes end when the writing process exits.
- **Color, not brightness.** The schedule never changes brightness. Only PWM-safe mode touches the backlight.

Display changes are hard to test in CI. For those, describe what you saw on which display.

## License

Your contributions are licensed under the MIT License.
