# Security policy

## Supported versions

Only the latest release gets security fixes.

## Report a vulnerability

Do not open a public issue for a security problem.

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Describe the problem, the steps to reproduce it, and the impact.

## What trueshift can touch

- Your screen color, through Apple's CoreBrightness (Night Shift) engine and display gamma tables.
- Your backlight level, when PWM-safe mode is on.
- One config file at `~/.config/trueshift/config.yaml`.
- One launchd agent at `~/Library/LaunchAgents/com.trueshift.agent.plist`, if you install it.

Trueshift has no network code. It does not need administrator rights.
