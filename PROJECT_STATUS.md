# Trueshift — Project Status

> Circadian display control for macOS. Temp-only: deep red at night, full brightness always.

**Last updated:** 2026-07-25 (v2.1 — PWM-safe)
**Session summary:** Studied TapZap (commercial PWM/blue-light app). It matches trueshift on blue-light depth and app weight; its one un-cloned feature was PWM-safe dimming. Built PWM-safe mode: pin backlight to 100% (kills PWM flicker), dim the image by scaling the gamma table. All Apple displays, sticky, per-display (externals we can't pin keep their own brightness). **Live-tested end to end on M4 built-in (2026-07-25):** pin 0.90→1.00 ✓, gamma dim to 0.60 ✓, drift re-assert 0.50→1.00 in ≤1.2s ✓, disable restored 0.89 + identity gamma ✓.

## Current State

**Phase:** v2.1.0 — PWM-safe added (control panel, not enforcer) ✓ shipped + live-verified

**Branch:** `main` (default; single source of truth — the old `feature/trueshift-design-refresh` was consolidated into `main` on 2026-08-17)

**CLI:** `/opt/homebrew/bin/trueshift` · launchd agent `com.trueshift.agent` (auto every 5 min)
**TrueshiftBar:** /Applications/TrueshiftBar.app (NSStatusItem + popover panel)
**Config:** `~/.config/trueshift/config.yaml` — v2 schema:
```yaml
location:
  latitude: -33.87
  longitude: 151.21
# optional:
# schedule:
#   day_temp: 5500      # default
#   night_floor: 1000   # default (Kruse deep red)
#   deep_red: true      # default; false = 2700K floor everywhere
# state:                # managed by the app — sticky manual override
#   override_until: ISO8601
#   override_temp: K
# pwm_safe:              # PWM-safe mode (sticky); bar enforces, CLI sets intent
#   enabled: false
#   software_brightness: 1.0   # 0.2–1.0 (floored to guard gamma banding)
#   saved_brightness: <built-in pre-pin value, for crash-safe restore>
```

## v2.1 PWM-Safe (2026-07-25)

**Mechanism:** pin backlight to 100% via `DisplayServicesSetBrightness` (LED runs DC-continuous → no PWM flicker), then dim the image by folding a per-display scalar into the gamma table (`GammaRGB.withBrightness`). Orthogonal to CCT — dim survives filter-off (identity color × dim at 6500K).

**Eligibility:** `DisplayServicesCanChangeBrightness` (built-in + Studio Display + Pro Display XDR). Third-party externals can't be pinned → not dimmed either (keep own brightness). Per-display dims map in `GammaLayer.sync(targetKelvin:dims:)`.

**Engine (`DisplayEngine.reconcilePWM`):** snapshot pre-pin brightness on enable, pin eligible displays, drift re-assert every 3rd tick (~0.9s) so auto-brightness/user keys can't win, restore snapshots on disable. Built-in's pre-pin value persists to `saved_brightness` (crash-safe); externals in-memory only (IDs aren't reboot-stable). `reset(restoreBrightness:false)` from the bar so filter-off never clobbers a PWM-restored value.

**Lifecycle:** clean quit (`applicationWillTerminate`) restores brightness; sticky config re-pins on relaunch. Hard crash leaves pin (screen bright, safe) → self-heals next launch.

**Verify:** `trueshift pwm-probe [--round-trip]`. Honest limit: we confirm the pin holds + dim renders, NOT the photometry (flicker needs a spectrometer/high-speed cam — same limit TapZap has short of their spectrometer photo).

## v2 Design (2026-07-23)

**Philosophy shift:** v1 was an enforcer (power-down dimming after a finish line). v2 is a control panel: auto = blue-light reduction ONLY, brightness is never scheduled (Aaqif works at night — deep red at full brightness). Zero-friction manual control.

**Curve (temp only, sun-anchored):**
| phase | window | temp |
|---|---|---|
| wake | sunrise → +30m | nightFloor → dayTemp |
| day | sunrise+30m → sunset−3h | dayTemp (5500) |
| dusk | sunset−3h → sunset | dayTemp → 2700 |
| evening | sunset → +2h | 2700 → nightFloor |
| night | sunset+2h → sunrise | nightFloor (1000) |

**Manual override:** slider drag / preset tap / `trueshift set <K>` → sticky until NEXT SUNRISE. `trueshift resume` or the panel's Resume Auto clears early. Honored by bar + agent via shared state (config.yaml, atomic writes, mtime-watched by the bar at 300ms).

**Display architecture (two layers):**
- **CoreBrightness pipeline** (2700–6000K hardware range): handles 2700K+. System-wide, persists across process exit. The short-lived CLI/agent uses ONLY this → graceful 2700K floor when the bar isn't running.
- **GammaLayer** (persistent TrueshiftBar only): residual gamma `fromKelvin(k)/fromKelvin(2700)` on ALL displays for sub-2700K. Identity at ≥2700K. True 1000K at full backlight.

**CLI:** `set <K>` (sticky) · `resume` · `auto` (agent tick; honors override) · `off` (filter off, sticky) · `pwm on|off` · `dim <20-100>` · `status [--json]` · `curve` / `pwm-probe` (hidden debug; the test substitutes on this XCTest-less machine) · `install`/`uninstall`

## Debugging display issues (read before touching DisplayController/GammaLayer)

Hard-won facts — three diagnoses over six months, one falsified later:

1. **`CGSetDisplayTransferByTable` (gamma) is process-lifetime only.** WindowServer silently restores gamma when the writing process exits. Any short-lived CLI writing gamma = visible ~1s flash, zero lasting effect (the red-flash bug). Persistent apps (TrueshiftBar) are the only valid gamma writers. v2 makes this structural: the CLI has no gamma code path at all.
2. **CORRECTED 2026-07-23: internal displays DO accept gamma from persistent processes.** The old learning ("gamma silently no-ops on Apple Silicon internal displays") was a misdiagnosis — the July 6 test wrote gamma from a short-lived CLI and the revert-on-exit looked like a no-op. Verified live on M4/macOS 26: a persistent process held deep-red gamma on the built-in display, visibly, for its whole lifetime.
3. **CoreBrightness (`CBBlueLightClient`) is system-wide and persistent** — prefer it for everything ≥2700K; it's the only mechanism that survives process exit.
4. **Re-arming the pipeline (`setEnabled` + `setMode`) replays the Night Shift transition animation.** Never call unconditionally — check `CBBridge_getStatus()` first. Also: after `reset()` (filter off), do NOT call `apply()` again or it re-arms; DisplayEngine guards with `didReset`.
5. **Verify, don't assume:** `swift scripts/gammacheck.swift` dumps every display's gamma. `trueshift set <K> -v` prints the full decision trace. `trueshift curve` prints the whole day's schedule.
6. Symptom → suspect: *transient ~1s flash* = gamma write from a short-lived process; *animated ramp* = pipeline re-arm; *permanent wrong color* = schedule/config/override bug.

## Next Steps

- [x] **CI TZ-dependent test fixed** (2026-10-07): `testNextSunriseAfterDawnIsTomorrow` judged "tomorrow" with the runner's calendar while using Sydney coordinates. Under UTC, Sydney's next sunrise (≈19:00–21:00 UTC) falls on the same UTC day, so the test failed. Code was correct. `Schedule.nextSunrise` now takes `calendar:` (default `.current`); tests pin Sydney + a fixed date. CI runs a TZ matrix (UTC + Australia/Sydney) in place of the old `TZ=Australia/Sydney` mask.
- [x] **PWM live test** (2026-07-25): pin, dim, drift re-assert, disable-restore all verified on M4 built-in via CLI + gammacheck. New bar installed to /Applications.
- [ ] Panel UX pass on the PWM slider (the CLI path is proven; still want a hands-on drag check + banding look near the 20% floor)
- [ ] Multi-display test on a Studio Display / Pro Display XDR (drift re-assert latency over DDC-ish path — may need to loosen the 3-tick cadence)
- [ ] Live-drag UX check: temp slider feel, preset ease timing (tune 1.0s if needed)
- [ ] v2.1 ideas: Homebrew formula, sunrise-reminder notification, per-display deep_red toggle

## Key Files

| File | Purpose |
|---|---|
| `Sources/TrueshiftCore/Schedule.swift` | v2 curve — pure `autoState()` + override-aware `current()` |
| `Sources/TrueshiftCore/Config.swift` | v2 schema + manual-override state API |
| `Sources/TrueshiftCore/DisplayController.swift` | CCT pipeline (CoreBrightness), CCT-only |
| `Sources/TrueshiftCore/GammaLayer.swift` | Sub-2700K deep red + per-display software dim, ALL displays, persistent-only |
| `Sources/TrueshiftCore/DisplayController.swift` | CCT pipeline + `DisplayServicesBridge` (pin/restore/eligibility) |
| `Sources/TrueshiftBar/DisplayEngine.swift` | Single-tick owner of all display writes; `reconcilePWM` owns the backlight pin |
| `Sources/TrueshiftBar/TrueshiftBarApp.swift` | NSStatusItem host + panel UI |
| `scripts/bundle-app.sh` | Build + install TrueshiftBar.app |
