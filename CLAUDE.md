# trueshift — agent orientation

Circadian display control for macOS. Temp-only: deep red at night, full brightness
always. Ships a CLI plus a menubar app (TrueshiftBar). Swift package.

## Read these first
- `PROJECT_STATUS.md` — current state, architecture, key files, next steps. Start here.
- `docs/STORY.md` and `docs/DECISIONS.md` — why the design is the way it is.
- Before you change display code, read the "Debugging display issues" section in
  `PROJECT_STATUS.md`. It holds six months of hard-won facts.

## Where the behavior lives
The engine is `Sources/TrueshiftCore/`. This is what makes it work.
- `DisplayController.swift` — CCT pipeline (CoreBrightness) + backlight pin/restore.
- `GammaLayer.swift` — sub-2700K deep red + per-display software dim. Persistent-process only.
- `Schedule.swift` — the day curve (pure functions).
- `Config.swift` — config schema + manual-override state.

The front-ends sit on top of Core:
- `Sources/Trueshift/` — the CLI. One file per command in `Commands/`.
- `Sources/TrueshiftBar/` — the menubar app. `DisplayEngine.swift` owns all display writes.
- `Sources/CoreBrightnessBridge/` — ObjC shim to the private CoreBrightness API.

## Critical constraint (do not relearn the hard way)
Gamma writes (`CGSetDisplayTransferByTable`) last only for the writing process's
lifetime. A short-lived CLI that writes gamma causes a ~1 second flash and nothing
else. Only persistent processes (TrueshiftBar) can write gamma. The CLI has no gamma
path on purpose. Keep it that way.

## Build, run, test
- Build: `swift build`
- Run the CLI: `swift run trueshift status`
- Install the CLI + launchd agent: `swift run trueshift install`
- Build and install the menubar app: `scripts/bundle-app.sh`
- Tests: `swift test` runs in CI (GitHub runners have Xcode). On a CLT-only machine
  `swift test` fails; verify live instead with `trueshift pwm-probe` and
  `swift scripts/gammacheck.swift`.

## Current phase
v2.1.0 — PWM-safe mode, shipped and live-verified 2026-07-25. See
`PROJECT_STATUS.md` → "Next Steps" for open items.

## Story
`docs/STORY.md` is the north star (interview walkthrough). Edit diagrams in `docs/img/src/` and rebuild them with `docs/img/src/render.sh`.
