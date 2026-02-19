#!/bin/sh
#
# ha-dashboard.sh - Home Assistant Dashboard for Kindle D01200 (Kindle Touch)
#
# Downloads a dashboard screenshot from a server and displays it on the
# Kindle's e-ink screen, working WITH the Kindle's native screensaver and
# power management system.
#
# Usage:
#   /mnt/us/extensions/kindle-ha-dashboard/ha-dashboard.sh &
#
# How it works:
#   The script keeps the device in screensaver mode, where the framework
#   hides the UI (taskbar, etc.) and displays our image. When the framework
#   transitions to readyToSuspend, we intercept it and use rtcwake to
#   suspend with an RTC alarm. On wake, the device is still in screensaver
#   mode — we update the image and the cycle repeats.
#   Pressing the power button exits screensaver mode normally.
#
# Designed for Kindle Touch D01200 where /sys/class/rtc/rtc0/wakealarm
# does NOT work but rtcwake -a does.
#

# ---- CONFIGURATION --------------------------------------------------------
# Edit these to match your setup, or override in config.sh.

# URL of the dashboard image (must be 600x800 PNG for Kindle Touch)
# Battery level and charging status are appended as query parameters.
IMAGE_URL="http://192.168.1.100:5000/image"

# Seconds between refreshes (default: 900 = 15 minutes)
REFRESH_INTERVAL=900

# RTC device number (usually 0, try 1 if 0 doesn't work)
RTC=1

# Turn WiFi off between refreshes to save battery? (1=yes, 0=no)
DISABLE_WIFI=1

# Seconds to wait for WiFi connection before giving up
WIFI_TIMEOUT=30

# Host/IP to ping to verify network connectivity
PING_HOST="192.168.1.1"

# Where to store the downloaded image
IMAGE_FILE="/tmp/ha-dashboard.png"

# Kindle screensaver folder and filename. The downloaded image is copied
# here so the Kindle's native screensaver mechanism displays our image
# instead of the default when entering sleep.
SCREENSAVER_DIR="/mnt/us/linkss/screensavers"
SCREENSAVER_FILE="bg_xsmall_ss00.png"

# Log file (set to /dev/null to disable logging)
LOGFILE="./ha-dashboard.log"

# Maximum log file size in bytes before rotation (100KB)
LOG_MAX_SIZE=102400

# Battery percentage at which to stop refreshing and just sleep
BATTERY_CRITICAL=2

# Seconds to stay awake after displaying the image before allowing suspend.
# During this window WiFi stays on so you can SSH in for maintenance.
AWAKE_DELAY=120

# ---- END CONFIGURATION ----------------------------------------------------

# Resolve script directory for finding config overrides
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load user overrides if present (place your config in config.sh)
if [ -f "${SCRIPT_DIR}/config.sh" ]; then
    . "${SCRIPT_DIR}/config.sh"
fi

# ---- FUNCTIONS -------------------------------------------------------------

log() {
    MSG="$(date '+%Y-%m-%d %H:%M:%S') | $1"
    echo "$MSG"
    [ "$LOGFILE" = "/dev/null" ] && return
    echo "$MSG" >> "$LOGFILE"
}

rotate_log() {
    [ "$LOGFILE" = "/dev/null" ] && return
    if [ -f "$LOGFILE" ]; then
        LOGSIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$LOGSIZE" -gt "$LOG_MAX_SIZE" ] 2>/dev/null; then
            mv "$LOGFILE" "${LOGFILE}.old"
            log "Log rotated"
        fi
    fi
}

get_battery_level() {
    # powerd_test -s is the reliable source on D01200; output looks like:
    #   Battery Level: 85%
    # The awk strips everything except digits.
    LEVEL=$(/usr/bin/powerd_test -s 2>/dev/null | awk -F: '/Battery Level/ {gsub(/[^0-9]/,"",$2); print $2}')
    if [ -n "$LEVEL" ]; then
        echo "$LEVEL"
    else
        echo "0"
    fi
}

get_charging_status() {
    # powerd_test -s output looks like:
    #   Charging: Yes
    STATUS=$(/usr/bin/powerd_test -s 2>/dev/null | awk -F: '/Charging/ {gsub(/^ +| +$/,"",$2); print $2}')
    if [ -n "$STATUS" ]; then
        echo "$STATUS"
    else
        echo "No"
    fi
}

wifi_is_on() {
    lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null || echo "0"
}

wifi_on() {
    log "Enabling WiFi"
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
}

wifi_off() {
    log "Disabling WiFi"
    lipc-set-prop com.lab126.cmd wirelessEnable 0 2>/dev/null
}

wait_for_network() {
    TIMER=0
    while [ "$TIMER" -lt "$WIFI_TIMEOUT" ]; do
        if /bin/ping -c 1 -w 2 "$PING_HOST" >/dev/null 2>&1; then
            log "Network is up (took ${TIMER}s)"
            return 0
        fi
        TIMER=$((TIMER + 1))
        sleep 1
    done
    log "Network timeout after ${WIFI_TIMEOUT}s"
    return 1
}

# Prevent powerd from suspending while we work.
# The argument is a duration in milliseconds.
defer_suspend() {
    lipc-set-prop com.lab126.powerd deferSuspend "$1" 2>/dev/null
}

is_in_screensaver() {
    lipc-get-prop com.lab126.powerd status 2>/dev/null | grep -q "Screen Saver"
}

enter_screensaver() {
    if ! is_in_screensaver; then
        log "Entering screensaver mode"
        lipc-set-prop com.lab126.powerd powerButton 1 2>/dev/null
        # Wait for the framework to transition
        sleep 3
    fi
}

# Copy image into the screensaver folder and refresh the e-ink display.
display_image() {
    if [ ! -f "$1" ]; then
        log "Image file not found: $1"
        return 1
    fi

    # Copy to screensaver folder so the Kindle shows our image
    if [ -d "$SCREENSAVER_DIR" ]; then
        cp "$1" "${SCREENSAVER_DIR}/${SCREENSAVER_FILE}"
        log "Copied image to screensaver folder"
    else
        log "Screensaver dir ${SCREENSAVER_DIR} not found"
    fi

    # Write directly to framebuffer. In screensaver mode the framework
    # won't overwrite this, so our image persists cleanly.
    eips -f -g "$1" 2>/dev/null
    log "Displayed image on screen"
}


# ---- MAIN LOOP -------------------------------------------------------------

log "=== ha-dashboard starting ==="
log "Image URL: ${IMAGE_URL}"
log "Refresh interval: ${REFRESH_INTERVAL}s"
log "Awake delay: ${AWAKE_DELAY}s"
log "WiFi management: $([ "$DISABLE_WIFI" -eq 1 ] && echo 'disable between refreshes' || echo 'always on')"

# Sync pmic_rtc (rtc1) clock from system time. The pmic_rtc resets to
# epoch 0 on reboot and must be set before rtcwake can calculate alarms.
YEAR=$(date +%Y)
if [ "$YEAR" -lt 2026 ] 2>/dev/null; then
    log "WARNING: System clock looks wrong (year=$YEAR). Syncing system from rtc0 first."
    hwclock -s -f /dev/rtc0 2>/dev/null
    YEAR=$(date +%Y)
    log "After rtc0 sync: year=$YEAR"
fi

hwclock -w -f /dev/rtc${RTC} 2>/dev/null
RTC1_EPOCH=$(cat /sys/class/rtc/rtc${RTC}/since_epoch 2>/dev/null || echo 0)
SYS_EPOCH=$(date +%s)
DRIFT=$((SYS_EPOCH - RTC1_EPOCH))
if [ "$DRIFT" -lt -5 ] || [ "$DRIFT" -gt 5 ]; then
    log "WARNING: rtc${RTC} drift=${DRIFT}s after sync, retrying"
    hwclock -w -f /dev/rtc${RTC} 2>/dev/null
fi
log "Clock sync: system epoch=${SYS_EPOCH}, rtc${RTC} epoch=${RTC1_EPOCH}, drift=${DRIFT}s"

# Enter screensaver mode on first run so the framework hides the UI.
# This makes the power button work correctly for toggling in/out.
enter_screensaver

while true; do
    rotate_log
    log "--- refresh cycle start ---"

    # If the device is not in screensaver mode, the user has manually
    # woken it (power button). Don't interfere — wait until they put
    # it back to sleep before running our cycle.
    if ! is_in_screensaver; then
        log "Device is active (user woke it). Waiting for screensaver..."
        lipc-wait-event -s 86400 com.lab126.powerd goingToScreenSaver 2>/dev/null
        log "User entered screensaver mode, resuming dashboard cycle"
        sleep 3  # let framework finish the transition
    fi

    # Keep powerd from suspending while we download + SSH window
    defer_suspend $(( (AWAKE_DELAY + 300) * 1000 ))

    # Check battery
    BATTERY=$(get_battery_level)
    IS_CHARGING=$(get_charging_status)
    log "Battery: ${BATTERY}% (charging: ${IS_CHARGING})"

    if [ "$BATTERY" -le "$BATTERY_CRITICAL" ] 2>/dev/null; then
        log "Battery critically low (${BATTERY}%). Sleeping for 24h."
        rtcwake -a -d /dev/rtc${RTC} -m mem -s 86400
        continue
    fi

    # Enable WiFi if needed
    WIFI_WAS_OFF=0
    if [ "$(wifi_is_on)" = "0" ]; then
        WIFI_WAS_OFF=1
        wifi_on
    fi

    # Download image with battery info as query params
    if wait_for_network; then
        FETCH_URL="${IMAGE_URL}?batteryLevel=${BATTERY}&isCharging=${IS_CHARGING}"
        log "Fetching: ${FETCH_URL}"
        if wget -q -O "${IMAGE_FILE}.tmp" "$FETCH_URL" 2>/dev/null; then
            mv "${IMAGE_FILE}.tmp" "$IMAGE_FILE"
            log "Image downloaded successfully"
        else
            log "wget failed, will display previous image if available"
            rm -f "${IMAGE_FILE}.tmp"
        fi
    else
        log "No network, will display previous image if available"
    fi

    # Display the dashboard image (we're in screensaver mode here)
    display_image "$IMAGE_FILE"

    # Stay awake for AWAKE_DELAY seconds (SSH window).
    # WiFi stays on so you can connect for maintenance.
    # The device remains in screensaver mode (no taskbar).
    log "Staying awake for ${AWAKE_DELAY}s (SSH window)"
    sleep "$AWAKE_DELAY"

    # Turn off WiFi only if we were the ones who turned it on
    if [ "$DISABLE_WIFI" -eq 1 ] && [ "$WIFI_WAS_OFF" -eq 1 ]; then
        wifi_off
    fi

    # Suspend directly with rtcwake. We're already in screensaver mode
    # so the framework is happy. No need to wait for readyToSuspend —
    # that approach has a race condition where powerd can suspend the
    # device before we set up the event listener.
    log "Suspending for ${REFRESH_INTERVAL}s via rtcwake -a (rtc${RTC})"
    rtcwake -a -d /dev/rtc${RTC} -s "$REFRESH_INTERVAL" -m mem 2>&1 | tee -a "$LOGFILE"
    # Immediately defer suspend so powerd doesn't re-suspend before our loop runs
    defer_suspend $(( (AWAKE_DELAY + 300) * 1000 ))
    log "Woke up from suspend (rtcwake exit: $?)"
done
