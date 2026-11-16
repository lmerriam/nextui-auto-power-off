#!/bin/sh
# Shared settings and helpers for Auto Power Off.
# Sourced by launch.sh and by the installed sleep/resume hooks.

: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${PLATFORM:=tg5040}"
: "${SYSTEM_PATH:=$SDCARD_PATH/.system/$PLATFORM}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/$PLATFORM}"
: "${SHARED_USERDATA_PATH:=$SDCARD_PATH/.userdata/shared}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"

# Overridable for testing off-device.
: "${APO_RTC_DIR:=/sys/class/rtc/rtc0}"
: "${APO_TMP:=/tmp}"
# Processes held still while powering off: the emulator and the launcher.
: "${APO_FREEZE:=minarch.elf nextui.elf}"

APO_STATE_DIR="$USERDATA_PATH/.autopoweroff"
APO_ENABLED_FILE="$APO_STATE_DIR/enabled"        # 1 = on, 0 = off
APO_TIMEOUT_FILE="$APO_STATE_DIR/timeout_secs"   # chosen time, kept while off
APO_TARGET_FILE="$APO_STATE_DIR/alarm_target"    # system epoch when the alarm should fire
APO_RESUME_BAK="$APO_STATE_DIR/auto_resume.bak"  # copy of NextUI's resume pointer
APO_LOG="$LOGS_PATH/autopoweroff.log"
APO_HOOK_NAME="autopoweroff.sh"
APO_WAKEALARM="$APO_RTC_DIR/wakealarm"
APO_AUTO_RESUME="$SHARED_USERDATA_PATH/.minui/auto_resume.txt"

# How early (seconds) a wake can come before the alarm target and still be
# treated as the alarm. RTC alarms have 1 s resolution plus resume latency.
APO_TOLERANCE=30

# How late (seconds) a wake can come after the alarm target and still be the
# alarm. The alarm wakes the device within a few seconds of its time; a wake
# much later means the alarm never woke it and the user did, on a device whose
# clock can't wake it from sleep. Powering off then would switch the device
# off just as the user picks it up.
APO_LATE_LIMIT=120

apo_log() {
	mkdir -p "$LOGS_PATH" 2>/dev/null
	# Keep the log small: trim to the last 200 lines once it passes 400.
	if [ -f "$APO_LOG" ] && [ "$(wc -l < "$APO_LOG")" -gt 400 ]; then
		tail -n 200 "$APO_LOG" > "$APO_LOG.tmp" && mv "$APO_LOG.tmp" "$APO_LOG"
	fi
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$APO_LOG"
}

# The time the user chose, in seconds, whether or not the pak is on. A time
# the settings screen no longer offers (early builds had a 2-minute test
# time) counts as the default.
APO_DEFAULT_TIMEOUT=3600
apo_chosen_timeout() {
	t=""
	[ -f "$APO_TIMEOUT_FILE" ] && t=$(cat "$APO_TIMEOUT_FILE" 2>/dev/null)
	for offered in $APO_TIMEOUTS; do
		[ "$t" = "$offered" ] && { echo "$t"; return; }
	done
	echo "$APO_DEFAULT_TIMEOUT"
}

# 1 when the pak is on. Early test builds had no switch: a time of 0 meant
# off, so a card set up by one keeps working as it was.
apo_enabled() {
	e=""
	[ -f "$APO_ENABLED_FILE" ] && e=$(cat "$APO_ENABLED_FILE" 2>/dev/null)
	case "$e" in
		1) echo 1 ;;
		0) echo 0 ;;
		*)
			t=$(cat "$APO_TIMEOUT_FILE" 2>/dev/null)
			case "$t" in ''|*[!0-9]*|0) echo 0 ;; *) echo 1 ;; esac
			;;
	esac
}

# Seconds of deep sleep before powering off, or 0 when the pak is off. This
# is what the sleep hooks act on.
apo_timeout() {
	if [ "$(apo_enabled)" = 1 ]; then apo_chosen_timeout; else echo 0; fi
}

# The times on offer, in seconds, in the order the settings screen lists
# them, with their labels.
APO_TIMEOUTS="900 1800 3600 7200 14400 28800"
apo_label() {
	case "$1" in
		900) echo "15 minutes" ;;
		1800) echo "30 minutes" ;;
		3600) echo "1 hour" ;;
		7200) echo "2 hours" ;;
		14400) echo "4 hours" ;;
		28800) echo "8 hours" ;;
		*) echo "$(( $1 / 60 )) minutes" ;;
	esac
}

# Whether this device's clock can wake it from sleep, which powering off
# after a set time depends on.
apo_supported() {
	[ -w "$APO_WAKEALARM" ]
}

apo_clear_alarm() {
	[ -w "$APO_WAKEALARM" ] && echo 0 > "$APO_WAKEALARM" 2>/dev/null
	rm -f "$APO_TARGET_FILE"
}
