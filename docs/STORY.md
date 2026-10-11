# The trueshift story

How I'd walk an interviewer through trueshift. Written after the fact, from the code, the docs and the git history. (It started as iris, then redshift. Both names were taken, so it became trueshift when I open-sourced it.)

---

## The 30-second version

> At 10pm the sky says night, but my screen still says noon. I wanted my screen to tell the truth.
>
> So I built trueshift. It follows the real sun where I live: daylight white in the day, deep firelight red after dark. It's one of the first tools I built for myself that I use every day. It runs quietly in the background. It's just code, so when I want it to work differently, I change it.

---

## Why I built it

![The sky, a normal screen, and trueshift across one real Sydney day](img/why.png)

Screens show midday light at every hour, even when the sky outside is dark. Night Shift and f.lux help, but they stop at orange. They also run on a fixed timer, and they belong to someone else.

I wanted three things:
1. **The truth about the time**, matched to the real sky where I am.
2. **No friction.** It should run itself, and I should never have to think about it.
3. **Ownership.** If it's wrong for me, I fix it.

---

## What makes it mine

![Six details: deep red, no flicker, follows my sun, red not dark, my choice wins, runs itself](img/nuances.png)

A blue-light filter is the easy part. The value is in the details that fit my life:
- **Deep red, not orange.** It goes to 1000K, like firelight. Night Shift stops at 2700K.
- **No flicker.** Most screens dim by blinking the backlight. trueshift can hold the backlight steady and dim in software (more [below](#why-does-flicker-matter)).
- **It follows my sun.** The red arrives with the real sunset in Sydney, not at a fixed hour.
- **Red, not dark.** It never dims the screen. Only the color changes.
- **My choice wins.** If I move the slider, it holds until the next sunrise. Then auto takes over again.
- **Runs itself.** The whole setup is my latitude and longitude.

![Sydney in December vs June: the warming starts 3 hours apart](img/seasons.png)

This is the detail people miss. In June the screen starts warming at 13:53. In December it starts at 17:05. A fixed "red at 9pm" timer would be wrong for half the year.

---

## How it works

![How trueshift works: inputs, the shared core, two writers, the displays](img/architecture.png)

- **One core, two front ends.** A Swift library holds the sun curve. The command line tool and the menu bar app both use it, so they always agree.
- **The menu bar app** runs all the time. It re-applies the color every 300 ms and draws the deep red.
- **A background agent** runs every 5 minutes as a safety net. Even if the menu bar app isn't running, the screen still warms to 2700K.
- **One small config file** holds my location and any manual override.

About 2,700 lines of Swift and Objective-C, with 56 unit tests.

---

## The result

- I've used it every day since July 2026, on my MacBook and my external monitor.
- True 1000K deep red on both screens at once, verified on an M4 MacBook.
- PWM-safe mode, tested live: the backlight held at 100%, a forced change was corrected in 1.2 seconds or less, and turning it off restored my old brightness.

---

## The questions interviewers ask

### "Did you get it right the first time?"

No. I got it wrong twice: once in the product and once in the engineering.

![v1 tried to police me, v2 works for me](img/pivot.png)

**The product.** v1 (January) was an enforcer. After a "finish line" time, it drove the screen to near-black red so I'd have to stop working. In v2 (July) I removed all of that: no finish line, no bedtime, no dimming. The tool changes my screen's color, not my schedule. A screen should stay readable, and I didn't want my own tool adding friction. A tool should serve me, not police me.

![Six months, three diagnoses, one bug](img/diagnoses.png)

**The engineering.** One bug took six months and three diagnoses. The red didn't stick, and the screen flashed red every 5 minutes. In July I even marked the project blocked because I believed my new Mac's screen ignored the color change. It didn't. The real answer was simpler and stranger (next question). What fixed it was a better test, not a better theory.

### "What was technically hard?"

![A color change lives only as long as the program that made it](img/insight.png)

macOS throws away a program's deep-red color change the moment that program exits. My 5-minute background job made the change, exited a second later, and the screen snapped back. That was the red flash.

So I split the work by lifetime. The always-running menu bar app owns the deep red. The short-lived job only uses Apple's Night Shift engine, which survives exit but stops at 2700K. I then removed the deep-red code from the short-lived tool entirely, so the bug can't come back.

### "Why does flicker matter?"

![Same brightness, two ways: blinking backlight vs steady backlight with software dimming](img/pwm.png)

Most screens get dimmer by blinking the backlight hundreds of times a second (PWM). You can't see it, but some people report eye strain from it. trueshift can pin the backlight at 100% and dim the picture in software instead. I found this idea by studying TapZap, a paid app. It was the one thing TapZap had that trueshift didn't, and I built it in a day.

### "What's the weakest part?"

**It uses private Apple APIs.** No public API can do deep red, so I accepted the risk. Any macOS update could break it. If that happens, the background job still gives a 2700K floor.

Two smaller ones:
- **Deep red needs the menu bar app alive.** If it crashes, the screen falls back to orange, not white.
- **I can't measure flicker.** I can prove the backlight holds steady. Proving zero flicker needs a high-speed camera.

### "How do you test it?"

The sun curve is pure logic, with 56 unit tests. CI runs them twice, once in UTC and once in Sydney time, because one test used to pass only in Sydney. The tests need full Xcode, and my laptop has only the Command Line Tools. So I also built debug commands: `trueshift curve` prints the whole day, and `scripts/gammacheck.swift` reads back every screen's color table.

### "What would you do next?"

1. Ship it as a Homebrew install, so nobody has to build it.
2. Test PWM-safe on a Studio Display, where the re-pin timing may need to change.
3. Log why the background agent fails when it fails, with a timestamp.

---

## The theme

Technology should serve me, not the other way around. My screen shouldn't lie to my brain about what time it is. And when my own tool started policing me, I changed it to work for me.
