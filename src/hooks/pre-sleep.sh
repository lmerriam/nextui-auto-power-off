#!/bin/sh
# Auto Power Off: pre-sleep hook.
# Installed to $USERDATA_PATH/.hooks/pre-sleep.d/ and run by NextUI's
# bin/suspend synchronously, right before the device enters deep sleep.
#
# Arms the RTC wake alarm so the device wakes itself after the configured
# time, and backs up NextUI's resume pointer. If a game is running, NextUI's
# emulator has already written its save file and resume state (slot 9) and
# auto_resume.txt before it got here (Menu_beforeSleep in minarch).

: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${PLATFORM:=tg5040}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/$PLATFORM}"
. "$USERDATA_PATH/.autopoweroff/common.sh" || exit 0

timeout=$(apo_timeout)
[ "$timeout" -gt 0 ] || exit 0

if [ ! -w "$APO_WAKEALARM" ]; then
	apo_log "pre-sleep: no writable RTC wake alarm at $APO_WAKEALARM, cannot arm"
	exit 0
fi

# Make sure the RTC is allowed to wake the system (harmless if unsupported).
[ -w "$APO_RTC_DIR/device/power/wakeup" ] && echo enabled > "$APO_RTC_DIR/device/power/wakeup" 2>/dev/null

# Back up the resume pointer: the emulator deletes it as soon as it wakes,
# and we need it back if we end up powering off.
if [ -f "$APO_AUTO_RESUME" ]; then
	cp -f "$APO_AUTO_RESUME" "$APO_RESUME_BAK"
	game="$(cat "$APO_AUTO_RESUME")"
else
	rm -f "$APO_RESUME_BAK"
	game=""
fi

# The kernel only accepts a new alarm after the old one is cleared.
echo 0 > "$APO_WAKEALARM" 2>/dev/null
# "+N" = N seconds from the RTC's current time, so RTC/system clock offset
# doesn't matter.
if echo "+$timeout" > "$APO_WAKEALARM" 2>/dev/null; then
	clock=$(apo_clock)
	echo "$clock $(( $(apo_now "$clock") + timeout ))" > "$APO_TARGET_FILE"
	sync
	apo_log "pre-sleep: alarm armed for ${timeout}s (wakealarm=$(cat "$APO_WAKEALARM" 2>/dev/null) clock=$clock rtc=$(apo_now rtc) sys=$(apo_now sys)) game=${game:-none}"
else
	rm -f "$APO_TARGET_FILE"
	apo_log "pre-sleep: kernel rejected wake alarm, not armed"
fi

exit 0
