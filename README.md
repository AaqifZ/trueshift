# trueshift

**Your screen shouldn't lie to your brain about what time it is.**

trueshift makes your Mac's screen follow the real sun where you live. In the day it shows daylight white. After dark it shows deep firelight red, at full brightness. It runs in the background, so you never think about it.

![The sky, a normal screen, and trueshift across one day in Sydney](docs/img/why.png)

## Why not Night Shift or f.lux?

![Six details: deep red, no flicker, follows your sun, red not dark, your choice wins, runs itself](docs/img/nuances.png)

- **Deep red, not orange.** trueshift goes down to 1000K. Night Shift stops at about 2700K.
- **It follows your sun.** The red arrives with your real sunset, so it changes with the seasons.
- **Red, not dark.** It never schedules brightness. Only the color changes.
- **No flicker (optional).** PWM-safe mode holds the backlight at 100% and dims the image in software.
- **Your choice wins.** A manual change holds until the next sunrise. Then the schedule takes over again.
- **Small and open.** About 2,700 lines of Swift. No network code. No admin rights.

![Sydney in December vs June: the warming starts 3 hours apart](docs/img/seasons.png)

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 or later (Xcode or the Command Line Tools)

## Install

1. Build the tool:
   ```bash
   git clone https://github.com/AaqifZ/trueshift.git
   cd trueshift
   swift build -c release
   cp .build/release/trueshift /usr/local/bin/
   ```
2. Set your location. The first run creates the config file:
   ```bash
   trueshift status
   ```
   Then edit `~/.config/trueshift/config.yaml`:
   ```yaml
   location:
     latitude: -33.87    # your latitude
     longitude: 151.21   # your longitude
   ```
3. Install the background agent. It runs every 5 minutes:
   ```bash
   trueshift install
   ```
4. Install the menu bar app. You need it for deep red below 2700K and for PWM-safe mode:
   ```bash
   scripts/bundle-app.sh
   open /Applications/TrueshiftBar.app
   ```

## Use

```bash
trueshift status            # current color, phase and mode
trueshift status --json     # the same, for scripts (Raycast, Alfred)
trueshift set 1000          # set a color now; holds until the next sunrise
trueshift off               # filter off until the next sunrise
trueshift resume            # return to the automatic schedule
trueshift pwm on            # PWM-safe mode on (applied by the menu bar app)
trueshift dim 60            # software brightness for PWM-safe mode (20-100)
trueshift uninstall         # remove the background agent
```

The menu bar app has the same controls: presets, a color slider, and Resume Auto.

## The schedule

| Phase | When | Color |
|---|---|---|
| Wake | sunrise to sunrise + 30 min | 1000K to 5500K |
| Day | until sunset − 3 h | 5500K |
| Dusk | sunset − 3 h to sunset | 5500K to 2700K |
| Evening | sunset to sunset + 2 h | 2700K to 1000K |
| Night | until sunrise | 1000K |

Optional settings in `config.yaml`:

```yaml
schedule:
  day_temp: 5500      # daytime color
  night_floor: 1000   # night color
  deep_red: true      # false = stop at 2700K
```

## How it works

![How trueshift works: inputs, the shared core, two writers, the displays](docs/img/architecture.png)

macOS gives two ways to change screen color:
- **CoreBrightness**, the engine behind Night Shift. The change stays after the program exits, but it stops at 2700K.
- **Gamma tables.** They go down to deep red, but macOS removes the change when the program that made it exits.

So the background agent uses CoreBrightness only. The always-running menu bar app adds the gamma layer for deep red. If the menu bar app is not running, the screen still warms to 2700K.

Read [docs/STORY.md](docs/STORY.md) for the full story, including the bugs. Read [docs/DECISIONS.md](docs/DECISIONS.md) for the design decisions.

## Known limits

- **Private APIs.** CoreBrightness and the backlight calls are not public. A macOS update can break them. If gamma breaks, the 2700K floor still works.
- **PWM-safe works on Apple displays only:** the built-in display, Studio Display and Pro Display XDR. Other monitors keep their own brightness.
- **PWM-safe raises the black level** on LCD panels in a dark room. This is normal for this method.
- **Your Mac's timezone must match your location.** trueshift uses the local clock to find "today".
- **No per-app exceptions.** The color applies to the whole screen.

## Credits

The night color targets follow Dr Jack Kruse's work on light and circadian health. trueshift uses [Solar](https://github.com/ceeK/Solar), [Yams](https://github.com/jpsim/Yams) and [Swift Argument Parser](https://github.com/apple/swift-argument-parser).

## License

MIT. See [LICENSE](LICENSE).
