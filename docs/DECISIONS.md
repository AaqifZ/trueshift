# Technical Decisions

This document captures the technical choices made in building Trueshift, with rationale for each. Use this when extending or debugging the tool.

---

## Why Swift CLI (not Electron/Node)?

**Decision date:** 2026-01-14

**Choice:** Native Swift CLI using Swift Package Manager

**Rationale:**
- Native macOS access to Core Graphics gamma APIs
- No runtime dependencies (single binary)
- Fast startup for launchd agent (runs every 5 minutes)
- ArgumentParser provides excellent CLI ergonomics

**Alternatives considered:**
- Electron: Too heavy for a background tool
- Node.js: Would need native bindings for Core Graphics
- Python: Slower startup, dependency management issues

---

## Why Core Graphics gamma tables (not DDC)?

**Decision date:** 2026-01-14

**Choice:** `CGSetDisplayTransferByFormula` for gamma adjustment

**Rationale:**
- Works on ALL displays (internal + external)
- No special hardware requirements
- Simple API, reliable results
- DDC requires specific monitor support and connection types

**Risks:**
- **macOS Tahoe (26) may break this.** Reports suggest `CGSetDisplayTransferByTable` is silently ignored on Tahoe. Monitor Apple releases.
- If gamma APIs fail, investigate:
  - DDC-CI via I2C (hardware brightness control)
  - Night Shift private APIs
  - ColorSync profile manipulation

**Alternatives considered:**
- DDC-CI: Better for hardware brightness, but limited compatibility
- Night Shift APIs: Private, could break with updates

---

## Why launchd (not cron)?

**Decision date:** 2026-01-14

**Choice:** launchd user agent in `~/Library/LaunchAgents/`

**Rationale:**
- macOS-native, survives sleep/wake correctly
- Runs missed jobs on wake (cron doesn't)
- User-space agent (no root required)
- Better logging integration

**Implementation:**
- Agent runs `trueshift auto` every 5 minutes (300 seconds)
- Logs to `/tmp/trueshift.log`
- `RunAtLoad: true` for immediate start

---

## Why YAML config (not JSON)?

**Decision date:** 2026-01-14

**Choice:** YAML configuration in `~/.config/trueshift/config.yaml`

**Rationale:**
- Human-readable, easy to edit manually
- Comments supported (can explain settings)
- Yams library is lightweight and reliable
- Follows XDG-style config location

**Alternatives considered:**
- JSON: No comments, harder to read
- TOML: Less common in Swift ecosystem
- plist: More verbose, less portable

---

## Default Temperature Values

**Decision date:** 2026-01-14

| Phase | Kelvin | Source |
|-------|--------|--------|
| Day | 5500K | Natural daylight (~5500-6500K) |
| Pre-sunset transition | 5500→2700K | Gradual warmth |
| Evening | 2700→1200K | Jack Kruse recommendation |
| Night | 1200→1000K | Firelight (~1000K) |
| Aggressive | 100K | "Unusable red" — intentional friction |

**Note:** These are more aggressive than f.lux (default 2700K) or Night Shift. This is intentional based on Jack Kruse's recommendations.

---

## Phase Calculation Logic

**Decision date:** 2026-01-14

**Phases relative to sunset:**

1. **Morning** (Sunrise → Sunset-2h): No filtering
2. **Pre-sunset** (Sunset-2h → Sunset): Gradual warmth
3. **Evening** (Sunset → Sunset+2h): Strong filter
4. **Night** (Sunset+2h → Finish line): Maximum red
5. **Power Down** (Finish line → Bedtime): Aggressive dimming
6. **Sleep** (Bedtime → Sunrise): Screen should be off

**Key design choice:** Finish line is user-configurable and separate from bedtime. This allows the Power Down window to trigger the ritual before bed.

---

## Brightness Interpolation

**Decision date:** 2026-01-14

**Choice:** Linear interpolation between phase boundaries

**Implementation:**
```swift
let progress = (now - phaseStart) / (phaseEnd - phaseStart)
let temp = startTemp + (endTemp - startTemp) * progress
```

**Rationale:**
- Smooth transitions avoid jarring changes
- User barely notices gradual shifts
- Matches how natural light fades

---

## Why Menu Bar App (TrueshiftBar)?

**Decision date:** 2026-01-14

**Choice:** SwiftUI menu bar app using `MenuBarExtra`

**Rationale:**
- User wanted visual feedback like f.lux/TRUESHIFT
- Shows current temperature, brightness, and phase at a glance
- Quick access to schedule info (sunrise, sunset, finish line, bedtime)
- Power Down Ritual reminder displayed during power-down phase

**Architecture:**
- Shared `TrueshiftCore` library between CLI and menu bar app
- Menu bar app refreshes every 30 seconds
- Uses same Schedule/Config logic as CLI

**Features:**
- Phase icon in menu bar (sun/moon based on phase)
- Temperature display (e.g., "28" for 2800K)
- Schedule times with highlighted finish line during power-down
- Apply Now / Disable buttons for quick control

---

## Future Considerations

### If gamma APIs break on Tahoe
- Investigate DDC-CI for external monitors
- Consider Night Shift private APIs as fallback
- May need separate code paths per display type

### Per-app exceptions
- Could use Accessibility APIs to detect frontmost app
- Skip filtering for color-critical apps (Photoshop, etc.)
- Would need allow-list in config

### Project-tracker integration
- `trueshift status --json` already outputs machine-readable format
- Could integrate with recovery tracking
- Power Down phase could trigger notifications

---

*Last updated: 2026-01-14 (added TrueshiftBar menu bar app)*

---

# Numbered decisions (v2 onward, backfilled 2026-10-04)

The sections above record the v1 choices (January 2026). The decisions below come from the v2 and v2.1 commits and `PROJECT_STATUS.md`. To change one, add a new decision and mark the old one "Replaced by Dn".

## D1. Control panel, not enforcer (2026-07-23)
- **Decision:** Remove the finish line, bedtime, power-down dimming and presentation mode. Auto changes color temperature only.
- **Why:** The author works at night and wants deep red at full brightness. Friction was rejected.
- **Replaces:** v1 "Phase Calculation Logic" (Power Down phase) and "Default Temperature Values" (100K aggressive).

## D2. Brightness is never scheduled (2026-07-23)
- **Decision:** The schedule never writes brightness.

## D3. Manual override is sticky until the next sunrise (2026-07-23)
- **Decision:** A slider, preset or `trueshift set <K>` holds until the next sunrise. `trueshift resume` clears it early.
- **Why:** Auto must not undo a manual choice 5 minutes later.

## D4. Two display layers, split by process lifetime (2026-07-23)
- **Decision:** CoreBrightness for 2700K and up (any process). Gamma for below 2700K (TrueshiftBar only). The CLI has no gamma code path.
- **Why:** A gamma write lasts only for the life of the writing process. A short-lived CLI that writes gamma causes a 1-second flash and nothing else.
- **Replaces:** v1 "Why Core Graphics gamma tables (not DDC)?".

## D5. Re-arm the Night Shift pipeline only when it is down (2026-07-18)
- **Decision:** Read the pipeline status first. Re-arm only when it is off. Small drift gets a silent nudge.
- **Why:** An unconditional re-arm replays the Night Shift transition animation every tick.

## D6. PWM-safe: pin the backlight, dim in software (2026-07-25)
- **Decision:** Pin eligible Apple displays to 100% backlight and dim by scaling the gamma table. Re-assert the pin about every 0.9 s. Restore the saved brightness on a clean quit.
- **Why:** A full backlight runs without PWM flicker. A study of TapZap, a commercial app, showed this was the one feature trueshift did not have.
- **Accepted cost:** A higher black level on LCD panels in a dark room. Third-party monitors are not pinned.
