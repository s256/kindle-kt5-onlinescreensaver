#!/bin/sh
#
# debug-rtcwake.sh - Diagnose rtcwake on Kindle D01200
#
# Run interactively:
#   ./debug-rtcwake.sh 2>&1 | tee debug-rtcwake.log
#

SLEEP_SECS=60

echo "=========================================="
echo "  rtcwake debug - $(date)"
echo "=========================================="
echo ""

echo "=== SYSTEM INFO ==="
echo "System time:     $(date)"
echo "System UTC:      $(date -u)"
echo "Epoch:           $(date +%s)"
echo "Kernel:          $(uname -r)"
echo ""

echo "=== RTC0 (mxc_rtc) ==="
echo "RTC time:        $(cat /sys/class/rtc/rtc0/date) $(cat /sys/class/rtc/rtc0/time)"
echo "RTC since_epoch: $(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null)"
echo "System epoch:    $(date +%s)"
DIFF=$(( $(date +%s) - $(cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null || echo 0) ))
echo "Difference:      ${DIFF}s (should be ~3600 if RTC=UTC and you're GMT+1)"
echo ""

echo "=== /etc/adjtime ==="
if [ -f /etc/adjtime ]; then
    cat /etc/adjtime
else
    echo "(file does not exist)"
fi
echo ""

echo "=== POWER STATE ==="
lipc-get-prop com.lab126.powerd status 2>/dev/null
echo ""

echo "=== DRY RUNS (mode=on, no actual suspend) ==="
echo ""
echo "--- rtcwake (no flag) ---"
rtcwake -d /dev/rtc0 -s 5 -m on 2>&1
echo "Exit: $?"
echo ""
echo "--- rtcwake -a ---"
rtcwake -a -d /dev/rtc0 -s 5 -m on 2>&1
echo "Exit: $?"
echo ""
echo "--- rtcwake -u ---"
rtcwake -u -d /dev/rtc0 -s 5 -m on 2>&1
echo "Exit: $?"
echo ""
echo "--- rtcwake -l ---"
rtcwake -l -d /dev/rtc0 -s 5 -m on 2>&1
echo "Exit: $?"
echo ""

echo "=========================================="
echo "  SUSPEND TESTS (${SLEEP_SECS}s each)"
echo "  If device does NOT wake, press power"
echo "  button, then note which test failed."
echo "=========================================="
echo ""

run_test() {
    NAME="$1"
    shift
    echo ">>> TEST: ${NAME}"
    echo "    Command:  $@"
    echo "    Before:   $(date) (epoch $(date +%s))"
    lipc-set-prop com.lab126.powerd deferSuspend 10000 2>/dev/null
    "$@" 2>&1
    echo "    After:    $(date) (epoch $(date +%s))"
    echo "    Exit:     $?"
    echo "<<< END ${NAME}"
    echo ""
}

echo "Test 1: rtcwake -u (UTC mode) — press Enter to start"
read dummy
run_test "rtcwake -u rtc0" rtcwake -u -d /dev/rtc0 -s $SLEEP_SECS -m mem

echo "Test 2: rtcwake -a (adjtime) — press Enter to start"
read dummy
run_test "rtcwake -a rtc0" rtcwake -a -d /dev/rtc0 -s $SLEEP_SECS -m mem

echo "Test 3: rtcwake -l (local) — press Enter to start"
read dummy
run_test "rtcwake -l rtc0" rtcwake -l -d /dev/rtc0 -s $SLEEP_SECS -m mem

echo "Test 4: rtcwake (no flag) — press Enter to start"
read dummy
run_test "rtcwake (none) rtc0" rtcwake -d /dev/rtc0 -s $SLEEP_SECS -m mem

echo "=========================================="
echo "  DONE - $(date)"
echo "=========================================="
echo ""
echo "Check 'Before' vs 'After' times above."
echo "A ~${SLEEP_SECS}s gap = RTC wake worked."
echo "A short gap = you pressed power button (failed)."
