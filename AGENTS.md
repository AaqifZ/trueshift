# trueshift: notes for coding agents

Swift package for macOS 14+. A command line tool (`trueshift`) and a menu bar app (`TrueshiftBar`) share one core library.

## Layout
- `Sources/TrueshiftCore/`: the schedule (pure functions), config, CoreBrightness control, gamma layer.
- `Sources/Trueshift/Commands/`: one file per CLI command.
- `Sources/TrueshiftBar/`: the menu bar app. `DisplayEngine.swift` owns all display writes.
- `Sources/CoreBrightnessBridge/`: Objective-C shim to the private CoreBrightness API.
- `Tests/TrueshiftCoreTests/`: unit tests for the core.

## Build and test
- Build: `swift build`
- Run: `swift run trueshift status`
- Test: `swift test` (needs full Xcode; CI runs it under UTC and Australia/Sydney)
- Print the day's curve: `swift run trueshift curve`

## Rules
- Gamma changes last only while the writing process runs. Only TrueshiftBar writes gamma. Do not add a gamma path to the CLI.
- The schedule changes color only. Do not write brightness outside PWM-safe mode.
- Tests must not depend on the machine's time zone. Pass a calendar explicitly.
- Keep `CHANGELOG.md` current.
