# Auto Power Off

A NextUI pak that turns your handheld fully off once it has been asleep for a
time you choose, so a device left asleep in a bag doesn't run its battery flat.
If a game was running, it resumes right where you left off the next time you
turn the device on.

## Devices

| Device | Platform | Status |
|---|---|---|
| TrimUI Brick | `tg5040` | Supported, tested |
| TrimUI Smart Pro | `tg5040` | Supported: same platform as the Brick |
| TrimUI Smart Pro S | `tg5050` | Not yet: testers wanted |
| Anbernic H700 devices (RG35XX family, RG40XX, RG CubeXX…) | `h700` | Not yet: testers wanted |

The pak needs the device's clock to be able to wake it from sleep, which
depends on the hardware. NextUI runs the same sleep hooks on the Smart Pro S
and H700 devices, so the pak is likely to work there too. If you have one and
can try the steps under [Check it works on your device](#check-it-works-on-your-device)
using a copy installed by hand, please
[open an issue](https://github.com/lmerriam/nextui-auto-power-off/issues) with
what happened and the log.

## Install

From the **Pak Store** on your device: find **Auto Power Off** and install it.

By hand: download `Auto.Power.Off.pak.zip` from the
[latest release](https://github.com/lmerriam/nextui-auto-power-off/releases/latest),
unzip it into a folder named `Auto Power Off.pak`, and copy that folder to
`Tools/<platform>/` on your SD card (for example `Tools/tg5040/`).

## Use

Open **Tools → Auto Power Off**.

| Setting | What it does |
|---|---|
| **Auto Power Off** | On or Off. Turning it off keeps your chosen time for next time. |
| **Power off after** | How long the device stays asleep before it powers off: 15 or 30 minutes; 1, 2, 4, 8 or 12 hours; or 1 or 2 days (24 or 48 hours). |

**Left / Right** change a setting, **A** saves, **B** leaves without saving.

## How it works

The timer starts when NextUI puts the device into **deep sleep**, a little
while after the screen turns off. Waking the device before the time is up
cancels it.

When the time is up, the device's clock wakes it just long enough to power
off cleanly, the same way NextUI does when you power off from the menu. If a
game was running, NextUI already saved it and its resume state before going
to sleep, so the game resumes on the next start.

NextUI doesn't deep sleep while the device is charging, so it never powers off
then.

Under the hood, the pak installs two NextUI hooks when it's on, and removes
them when it's off:

- `.userdata/<platform>/.hooks/pre-sleep.d/autopoweroff.sh` sets the clock's
  wake alarm just before deep sleep, and keeps a copy of NextUI's resume
  pointer.
- `.userdata/<platform>/.hooks/post-resume.d/autopoweroff.sh` runs on waking.
  If you woke the device, it clears the alarm and does nothing else. If the
  alarm woke it, it puts the resume pointer back and powers off.

Settings live in `.userdata/<platform>/.autopoweroff/`.

## Check it works on your device

1. Set **Power off after** to **15 minutes** and turn it on.
2. Start a game, press the power button to sleep, and leave the device alone.
3. After NextUI's deep-sleep delay plus 15 minutes, it should be off.
4. Turn it on: the game should resume where you left it.
5. Set the time you actually want.

A log of what happened is kept in `.userdata/<platform>/logs/autopoweroff.log`.
If the device never powers off, its clock probably can't wake it from sleep:
the log shows `pre-sleep: alarm armed`, then nothing until you woke it, and
then `the alarm didn't wake the device`. In that case the pak stays out of the
way and never powers the device off as you wake it.
Please [open an issue](https://github.com/lmerriam/nextui-auto-power-off/issues)
with your device and the log.

## Limits

- Games are kept only when they run in NextUI's own emulator. Standalone
  emulator paks don't save a resume state before sleep, so their progress
  since the last in-game save is lost.
- Waking the device in the last 30 seconds before the alarm may still power it
  off.
- The screen may light up briefly just before the device powers off.

## Building

```sh
scripts/build.sh   # writes dist/Auto.Power.Off.pak.zip
tests/run.sh       # off-device tests; needs jq
```

The build downloads the helper programs the settings screen uses at pinned
versions and checks them against pinned checksums. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for what's included.

## License

MIT. See [LICENSE](LICENSE).
