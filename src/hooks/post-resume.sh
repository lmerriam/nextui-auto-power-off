#!/bin/sh
# Auto Power Off: post-resume hook.
# Installed to $USERDATA_PATH/.hooks/post-resume.d/ and run by NextUI's
# bin/suspend in the background immediately after the device wakes.
#
# If the wake was caused by our RTC alarm (not by the user), keep the game's
# resume state and shut down the same way NextUI does.

: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${PLATFORM:=tg5040}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/$PLATFORM}"
. "$USERDATA_PATH/.autopoweroff/common.sh" || exit 0

[ -f "$APO_TARGET_FILE" ] || exit 0
target=$(cat "$APO_TARGET_FILE" 2>/dev/null)
now=$(date +%s)
apo_clear_alarm
case "$target" in ''|*[!0-9]*) exit 0 ;; esac

if [ "$now" -lt $(( target - APO_TOLERANCE )) ]; then
	apo_log "post-resume: user wake $(( target - now ))s before alarm, staying on"
	rm -f "$APO_RESUME_BAK"
	exit 0
fi

if [ "$now" -gt $(( target + APO_LATE_LIMIT )) ]; then
	apo_log "post-resume: woke $(( now - target ))s after the alarm time, so the alarm didn't wake the device; staying on. This device's clock may not be able to wake it from sleep."
	rm -f "$APO_RESUME_BAK"
	exit 0
fi

apo_log "post-resume: woken by alarm ($(( now - target ))s after target), powering off"

# Freeze the UI and emulator before they finish waking: this stops the
# emulator from deleting auto_resume.txt and keeps the screen work minimal.
# The resume state and save were already written before sleep.
for p in $APO_FREEZE; do
	killall -STOP "$p" 2>/dev/null
done

# Put the resume pointer back so the game resumes on next boot, exactly as
# if the user had powered off in-game.
if [ -f "$APO_RESUME_BAK" ]; then
	mkdir -p "$(dirname "$APO_AUTO_RESUME")"
	cp -f "$APO_RESUME_BAK" "$APO_AUTO_RESUME"
	rm -f "$APO_RESUME_BAK"
	apo_log "post-resume: kept resume state for $(cat "$APO_AUTO_RESUME")"
fi

# Same flags NextUI's own power-off sets, so its launch loop won't relaunch.
rm -f "$APO_TMP/nextui_exec"
touch "$APO_TMP/poweroff"
sync

# poweroff_next is NextUI's shutdown helper (stops processes, unmounts the SD
# card, cuts power via the PMIC). Fall back to the generic poweroff.
if command -v poweroff_next >/dev/null 2>&1; then
	poweroff_next
elif [ -x "$SYSTEM_PATH/bin/poweroff_next" ]; then
	"$SYSTEM_PATH/bin/poweroff_next"
else
	apo_log "post-resume: poweroff_next not found, using poweroff"
	poweroff
fi

# Only reached if shutdown failed (a successful one kills this script).
# Undo everything so the device isn't left frozen.
apo_log "post-resume: shutdown command returned $?, restoring UI"
rm -f "$APO_TMP/poweroff"
touch "$APO_TMP/nextui_exec"
for p in $APO_FREEZE; do
	killall -CONT "$p" 2>/dev/null
done
exit 1
