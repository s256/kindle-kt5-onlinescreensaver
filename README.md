# onlinescreensaver

Displays a Home Assistant dashboard screenshot on a Kindle Touch (D01200) e-ink screen, with battery-optimized sleep/wake cycling.
Everything you find here is either based on [peterson](https://www.mobileread.com/forums/showthread.php?t=236104)'s work or [StephanStrobel](https://forum.fhem.de/index.php?action=profile;u=3960) from the [great FHEM Community Forum, which delivered the last necessary steps](https://forum.fhem.de/index.php?topic=21821.695).

I'm publishing this here, to conserve the code and make it more accesible for others. 

## How it works

```
┌─────────────────────────────────────────┐
│  HA Server (e.g. hass-lovelace-kindle-  │
│  screensaver) renders dashboard to PNG  │
│  and serves it via HTTP on port 5000    │
└──────────────────┬──────────────────────┘
                   │ HTTP GET (600x800 PNG)
                   │ ?batteryLevel=85&isCharging=No
                   ▼
┌─────────────────────────────────────────┐
│  Kindle D01200 running onlinescreensaver  │
│                                         │
│  1. Wake from suspend (screensaver mode)│
│  2. Defer powerd suspend                │
│  3. Read battery level & charging state │
│  4. Enable WiFi, download image         │
│  5. Copy image to screensaver folder    │
│  6. Display image with eips             │     │
│  7. Disable WiFi (if configured)        │
│  8. rtcwake -a suspends to RAM          │
│  9. PMIC RTC alarm fires → go to 1    │
└─────────────────────────────────────────┘
```

### Working WITH the framework

Unlike projects that stop the Kindle framework (`initctl stop framework`), this script keeps it running and works with the native power state machine:

```
Active ──(powerButton)──> Screen Saver ──(powerd)──> Suspended
  ^                            │                         │
  └────(powerButton)───────────┘       rtcwake ──────────┘
```

- The script keeps the device in **screensaver mode**, where the framework hides the UI (taskbar, etc.)
- `deferSuspend` keeps powerd from suspending while we download and display the image
- After the awake window, the script calls `rtcwake -a` directly to suspend with an RTC alarm — no event-driven approach needed
- On wake, the device is still in screensaver mode — no taskbar, clean display
- If the user presses the **power button** to wake the Kindle, the script detects this (device exits screensaver mode) and pauses until the user puts it back to sleep
- Pressing the **power button** exits screensaver mode normally and restores the Kindle UI

This approach is modeled after the [onlinescreensaver](https://www.mobileread.com/forums/showthread.php?t=236104) extension, adapted for the D01200's specific RTC hardware.

### Why `rtcwake -a` on rtc1?

The D01200 has two RTC devices:

| Device | Driver | Can set alarms | Can wake from suspend |
|---|---|---|---|
| `/dev/rtc0` | `mxc_rtc` (SoC) | Yes | **No** — no hardware wake line |
| `/dev/rtc1` | `pmic_rtc` (PMIC) | Yes | **Yes** — connected to the PMIC wake interrupt |

The sysfs interface (`/sys/class/rtc/rtc0/wakealarm`) doesn't exist on D01200, and even if alarms are set on rtc0 via ioctl, they cannot generate a wake interrupt from suspend. Only the **PMIC RTC (rtc1)** has the hardware wake line.

The `rtcwake` command uses the kernel ioctl interface to atomically set an alarm and suspend in one call. The **`-a` flag** (use `/etc/adjtime` to determine local vs UTC) is required because rtc1 resets to epoch 0 on every reboot — the script syncs it from the system clock at startup using `hwclock -w`.

**Working command:** `rtcwake -a -d /dev/rtc1 -s <seconds> -m mem`

### Battery & charging info

The script reads battery level and charging status and appends them as query parameters:
```
http://your-server:5000/image?batteryLevel=85&isCharging=No
```
This allows your HA dashboard to display the Kindle's battery state.

## Prerequisites

- Kindle Touch D01200, jailbroken with SSH access
- [linkss (Link's ScreenSaver hack)](https://www.mobileread.com/forums/showthread.php?t=195474) installed — provides the screensaver folder at `/mnt/us/linkss/screensavers/`
- A server on your LAN generating the dashboard PNG (e.g. [hass-lovelace-kindle-screensaver](https://github.com/sibbl/hass-lovelace-kindle-screensaver))
- The image must be exactly **600x800 pixels** (the D01200 screen resolution)
- `wget`, `eips`, `rtcwake`, `lipc-get-prop`, `lipc-set-prop`, `lipc-wait-event` available on the Kindle (all present on stock jailbroken firmware)

## Files

| File | Purpose |
|---|---|
| `scheduler.sh` | Main script — run this in the background |
| `config.sh` | Your configuration (edit this) |
| `diags.sh` | Diagnostic script to test which RTC device and flags work on your Kindle |
| `/mnt/us/extensions/onlinescreensaver/diags/onlinescreensaver.log` | Log file (created at runtime) |

## Installation

1. **Edit `config.sh`** on your computer with your settings (see [Configuration](#configuration) below).

2. **Copy the folder to the Kindle** via SSH/SCP:
   ```sh
   scp -r onlinescreensaver root@<kindle-ip>:/mnt/us/extensions/
   ```

3. **Run it:**
   ```sh
   /mnt/us/extensions/onlinescreensaver/bin/scheduler.sh &
   ```

4. **Check the log** to verify it's working:
   ```sh
   cat /mnt/us/extensions/onlinescreensaver/diags/onlinescreensaver.log
   ```

## Configuration

Edit `config.sh` before deploying. All values are also defined with defaults in `scheduler.sh`, so `config.sh` only needs to contain the values you want to override.

| Variable | Default | Description |
|---|---|---|
| `IMAGE_URL` | `http://192.168.1.100:5000/image` | URL of the dashboard PNG. Battery level and charging status are appended as query parameters automatically. |
| `REFRESH_INTERVAL` | `900` | Seconds between refreshes. 900 = 15 minutes. |
| `RTC` | `1` | RTC device number. `1` (pmic_rtc) is correct for D01200 — this is the only RTC that can wake from suspend. |
| `DISABLE_WIFI` | `1` | Turn WiFi off between refreshes to save battery. Set to `0` to keep WiFi on. |
| `WIFI_TIMEOUT` | `30` | Seconds to wait for WiFi to connect before giving up. |
| `PING_HOST` | `192.168.1.1` | IP to ping to verify network connectivity. Use your router or HA server IP. |
| `BATTERY_CRITICAL` | `2` | Battery percentage at which the script stops refreshing and deep-sleeps for 24h. |
| `AWAKE_DELAY` | `120` | Seconds to stay awake after displaying the image. Keeps WiFi up so you can SSH in. The device stays in screensaver mode during this window (no taskbar). |
| `SCREENSAVER_DIR` | `/mnt/us/linkss/screensavers` | Path to the Kindle's screensaver folder (from linkss hack). |
| `SCREENSAVER_FILE` | `bg_xsmall_ss00.png` | Filename within the screensaver folder to overwrite with our image. |
| `LOGFILE` | `./scheduler.log` | Log file path. Set to `/dev/null` to disable logging. |
| `LOG_MAX_SIZE` | `102400` | Max log size in bytes before rotation (default 100KB). |
| `REMOTE_LOG` | None | Configure rsyslog (TCP!) remote host to receive logs. e.g. `192.168.0.5:514`| 

## Stopping the script

Find and kill the process:
```sh
ps aux | grep scheduler
kill <pid>
```

Or if you backgrounded it in the current shell session:
```sh
kill %1
```

To restore normal Kindle operation after stopping the script, press the power button.

## Troubleshooting

**Script runs but Kindle doesn't wake up:**
- Verify `rtcwake` works manually from SSH: `rtcwake -a -d /dev/rtc1 -s 30 -m mem` (the `-a` flag and `/dev/rtc1` are both critical on D01200)
- Make sure `RTC=1` in config.sh — rtc0 (mxc_rtc) cannot wake the device from suspend, only rtc1 (pmic_rtc) can
- Check that the system clock is correct (`date`) — rtc1 resets to epoch 0 on reboot, and the script syncs it at startup. If the system clock is wrong, rtcwake alarms will be wrong too
- Check the log for "Clock sync" and "Suspending" messages

**Taskbar appears on screen:**
- The script should enter screensaver mode automatically. Check that `lipc-set-prop com.lab126.powerd powerButton 1` works manually
- Verify with: `lipc-get-prop com.lab126.powerd status` — should show "Screen Saver"

**Screen shows wrong image / default screensaver:**
- Make sure linkss is installed: `ls /mnt/us/linkss/screensavers/`
- Check that `SCREENSAVER_FILE` matches an existing filename in that folder
- The script copies the image there AND uses `eips` as belt-and-suspenders

**Image doesn't display:**
- Verify the URL returns a valid 600x800 PNG: `wget -O /tmp/test.png <your-url>` then `eips -f -g /tmp/test.png`
- Check that your HA screenshot service is running and accessible from the Kindle's network

**WiFi doesn't connect:**
- Increase `WIFI_TIMEOUT` (try 60)
- Make sure `PING_HOST` is reachable (use your router IP, not an internet host)
- Check if WiFi credentials are saved on the Kindle

**Power button doesn't restore normal Kindle UI:**
- This shouldn't happen with the current approach since the framework is running. Press the power button once to exit screensaver mode
- If the screen looks corrupted, press power button twice (once to exit screensaver, once to re-enter, which triggers a clean redraw)

**Log file:**
- Read the log: `cat /mnt/us/extensions/onlinescreensaver/diags/onlinescreensaver.log`

## Why not use the onlinescreensaver extension?

The [onlinescreensaver](https://www.mobileread.com/forums/showthread.php?t=236104) extension sets the RTC alarm via sysfs:
```sh
echo $TIMESTAMP > /sys/class/rtc/rtc0/wakealarm
```
Then it relies on `powerd` to suspend the device and uses `lipc-wait-event com.lab126.powerd resuming` to detect wake. On the D01200:

1. `/sys/class/rtc/rtc0/wakealarm` doesn't exist (the mxc_rtc driver doesn't expose this sysfs interface)
2. Even if you set alarms on rtc0 via ioctl, it cannot generate a wake interrupt — the hardware wake line is only connected to the PMIC RTC (rtc1)
3. The event-driven approach (`lipc-wait-event ... readyToSuspend`) has a race condition where powerd can suspend the device before the event listener is set up

This script uses the same framework-cooperative architecture but:
- Uses **rtc1** (pmic_rtc) which has the hardware wake interrupt
- Uses `rtcwake -a` which atomically sets the alarm and suspends via ioctl
- Calls rtcwake **directly** after the awake window instead of waiting for a powerd event, avoiding the race condition

## Battery life

With `DISABLE_WIFI=1` and a 15-minute refresh interval (96 refreshes/day), expect several weeks of battery life. The main power consumers are:

- WiFi on/connect/download: ~10-15 seconds per cycle
- Awake window (SSH access): 120 seconds per cycle at idle (configurable)
- e-ink refresh: negligible
- Suspend-to-RAM: very low draw (~1-2mA)

To extend battery life further, increase `REFRESH_INTERVAL`, reduce `AWAKE_DELAY`, or do both at night by modifying the script.
