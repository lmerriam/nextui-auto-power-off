#!/bin/sh
# Tests for Auto Power Off, run off the device or on it:
#
#   tests/run.sh            # uses jq from PATH
#   JQ=/path/to/jq tests/run.sh
#
# The settings screen's helpers are replaced by stubs that play back scripted
# button presses, the RTC by a plain directory, and the shutdown command by a
# stub that records it was called. Nothing outside a temp directory is touched.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${JQ:=$(command -v jq)}"
[ -x "$JQ" ] || { echo "need jq (set JQ=)"; exit 2; }
SHELL_UNDER_TEST="${SHELL_UNDER_TEST:-/bin/sh}"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $*"; }
eq() { # want got what
	if [ "$1" = "$2" ]; then pass; else fail "$3: want '$1', got '$2'"; fi
}
exists() { if [ -e "$1" ]; then pass; else fail "missing $1"; fi; }
absent() { if [ ! -e "$1" ]; then pass; else fail "should not exist: $1"; fi; }

# A fresh card, pak and RTC for each test.
setup() {
	T="$(mktemp -d "${TMPDIR:-/tmp}/apo-test.XXXXXX")"
	export SDCARD_PATH="$T/sd" PLATFORM=tg5040
	export USERDATA_PATH="$SDCARD_PATH/.userdata/$PLATFORM"
	export SHARED_USERDATA_PATH="$SDCARD_PATH/.userdata/shared"
	export LOGS_PATH="$USERDATA_PATH/logs"
	export SYSTEM_PATH="$SDCARD_PATH/.system/$PLATFORM"
	export APO_RTC_DIR="$T/rtc" APO_TMP="$T/tmp" APO_WORK="$T/tmp/ui"
	# Never freeze the real launcher or emulator, even when run on a device.
	export APO_FREEZE="apo-test-no-such-process"
	export STUB="$T/stub"
	mkdir -p "$APO_RTC_DIR" "$APO_TMP" "$STUB" "$SHARED_USERDATA_PATH/.minui" "$SYSTEM_PATH/bin"
	: > "$APO_RTC_DIR/wakealarm"
	echo sunxi-rtc > "$APO_RTC_DIR/name"
	# The RTC's own time, far from the system clock's, so a hook that reads
	# the wrong clock fails.
	echo 1000000 > "$APO_RTC_DIR/since_epoch"

	PAK="$SDCARD_PATH/Tools/$PLATFORM/Auto Power Off.pak"
	mkdir -p "$PAK/bin/$PLATFORM"
	cp -R "$ROOT/src/." "$PAK/"
	ln -s "$JQ" "$PAK/bin/jq"
	cp "$ROOT/tests/stub-list.sh" "$PAK/bin/$PLATFORM/minui-list"
	cp "$ROOT/tests/stub-presenter.sh" "$PAK/bin/$PLATFORM/minui-presenter"
	chmod +x "$PAK"/*.sh "$PAK"/hooks/*.sh "$PAK/bin/$PLATFORM/"*

	# Shutdown is recorded, never performed, along with whether NextUI's own
	# power-off flag was set when it ran.
	printf '#!/bin/sh\necho "poweroff_next flag=$([ -f "%s/poweroff" ] && echo set)" >> "%s/shutdown"\n' "$APO_TMP" "$T" > "$SYSTEM_PATH/bin/poweroff_next"
	chmod +x "$SYSTEM_PATH/bin/poweroff_next"

	PRE="$USERDATA_PATH/.hooks/pre-sleep.d/autopoweroff.sh"
	POST="$USERDATA_PATH/.hooks/post-resume.d/autopoweroff.sh"
	STATE="$USERDATA_PATH/.autopoweroff"
}

teardown() { rm -rf "$T"; }

# presses LINE...: what the stub list does on each launch, one line per
# launch: "<exit code>|<jq filter turning its input into the state it writes>".
presses() { printf '%s\n' "$@" > "$STUB/list-script"; rm -f "$STUB/list-count" "$STUB"/list-input-*.json; }
launch() { (cd "$PAK" && JQ_BIN="$JQ" "$SHELL_UNDER_TEST" ./launch.sh) >/dev/null 2>&1; }
setting() { cat "$STATE/$1" 2>/dev/null; }

# Index of a time in the list: 900 1800 3600 7200 14400 28800 43200 86400 172800.
T2H=3

echo "settings screen"

setup
presses "0|.items[0].selected=1 | .items[1].selected=$T2H"
launch
eq 1 "$(setting enabled)" "saving On"
eq 7200 "$(setting timeout_secs)" "saving 2 hours"
exists "$PRE"; exists "$POST"; exists "$STATE/common.sh"
eq 1 "$(grep -c 'powers off after 2 hours asleep' "$STUB/presenter-log")" "save notice"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=$T2H"
launch
presses "0|.items[0].selected=0"
launch
eq 0 "$(setting enabled)" "switching off"
eq 7200 "$(setting timeout_secs)" "switching off keeps the chosen time"
absent "$PRE"; absent "$POST"
eq 1 "$(grep -c 'Auto Power Off is off' "$STUB/presenter-log")" "off notice"
presses "0|.items[0].selected=1"
launch
eq 1 "$(setting enabled)" "switching back on"
exists "$PRE"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=1"
launch
presses "2|.items[0].selected=0 | .items[1].selected=5"
launch
eq 1 "$(setting enabled)" "B leaves the setting alone"
eq 1800 "$(setting timeout_secs)" "B leaves the time alone"
exists "$PRE"
teardown

setup
rm -f "$APO_RTC_DIR/wakealarm"
presses "0|.items[0].selected=1"
launch
absent "$STATE/enabled"
absent "$STUB/list-input-1.json"
eq 1 "$(grep -c "can't wake itself" "$STUB/presenter-log")" "unsupported notice"
teardown

setup
# A card set up by an early test build: a time, no switch.
mkdir -p "$STATE"; echo 1800 > "$STATE/timeout_secs"
presses "2|."
launch
eq 1 "$("$JQ" '.items[0].selected' "$STUB/list-input-1.json")" "early build On shows as On"
eq 1 "$("$JQ" '.items[1].selected' "$STUB/list-input-1.json")" "early build time shows as 30 minutes"
teardown

setup
mkdir -p "$STATE"; echo 0 > "$STATE/timeout_secs"
presses "2|."
launch
eq 0 "$("$JQ" '.items[0].selected' "$STUB/list-input-1.json")" "early build Off shows as Off"
eq 2 "$("$JQ" '.items[1].selected' "$STUB/list-input-1.json")" "early build Off offers the default time"
teardown

setup
# An early build's 2-minute test time is no longer offered: it becomes 1 hour.
mkdir -p "$STATE"; echo 1 > "$STATE/enabled"; echo 120 > "$STATE/timeout_secs"
presses "2|."
launch
eq 2 "$("$JQ" '.items[1].selected' "$STUB/list-input-1.json")" "test time shows as 1 hour"
cp "$PAK/common.sh" "$STATE/common.sh"
mkdir -p "$(dirname "$PRE")"; cp "$PAK/hooks/pre-sleep.sh" "$PRE"
(cd "$T" && "$SHELL_UNDER_TEST" "$PRE") >/dev/null 2>&1
eq "+3600" "$(tail -n 1 "$APO_RTC_DIR/wakealarm")" "test time arms 1 hour"
teardown

setup
presses "2|."
launch
eq '["15 minutes","30 minutes","1 hour","2 hours","4 hours","8 hours","12 hours","24 hours","48 hours"]' \
	"$("$JQ" -c '.items[1].options' "$STUB/list-input-1.json")" "times on offer"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=8"
launch
eq 172800 "$(setting timeout_secs)" "saving 48 hours"
eq 1 "$(grep -c 'powers off after 48 hours asleep' "$STUB/presenter-log")" "48 hours notice"
(cd "$T" && "$SHELL_UNDER_TEST" "$PRE") >/dev/null 2>&1
eq "+172800" "$(tail -n 1 "$APO_RTC_DIR/wakealarm")" "alarm armed for 48 hours"
teardown

echo "sleep hooks"

# Fire the hooks the way NextUI's suspend script does.
hook() { (cd "$T" && "$SHELL_UNDER_TEST" "$1") >/dev/null 2>&1; }
# rtc_at SECONDS: the RTC reads that long after the time the alarm was set for.
rtc_at() { echo $(( $(cut -d' ' -f2 "$STATE/alarm_target") + $1 )) > "$APO_RTC_DIR/since_epoch"; }

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
echo "/mnt/SDCARD/Roms/Game.gba" > "$SHARED_USERDATA_PATH/.minui/auto_resume.txt"
hook "$PRE"
eq "+900" "$(tail -n 1 "$APO_RTC_DIR/wakealarm")" "alarm armed for 15 minutes"
eq "rtc 1000900" "$(cat "$STATE/alarm_target")" "target measured on the RTC"
exists "$STATE/auto_resume.bak"
# The user wakes it early: nothing happens.
rtc_at -600
hook "$POST"
absent "$T/shutdown"
absent "$STATE/alarm_target"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
echo "/mnt/SDCARD/Roms/Game.gba" > "$SHARED_USERDATA_PATH/.minui/auto_resume.txt"
hook "$PRE"
# The alarm wakes it, on time by the RTC whatever the system clock says.
# The emulator has dropped the resume pointer by now.
rtc_at 3
rm -f "$SHARED_USERDATA_PATH/.minui/auto_resume.txt"
hook "$POST"
eq "poweroff_next flag=set" "$(cat "$T/shutdown" 2>/dev/null)" "powers off the way NextUI does"
eq "/mnt/SDCARD/Roms/Game.gba" "$(cat "$SHARED_USERDATA_PATH/.minui/auto_resume.txt" 2>/dev/null)" "resume pointer put back"
# The stub returned, which a real shutdown never does: the hook undoes its
# changes so the device isn't left frozen.
absent "$APO_TMP/poweroff"
exists "$APO_TMP/nextui_exec"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
echo "/mnt/SDCARD/Roms/Game.gba" > "$SHARED_USERDATA_PATH/.minui/auto_resume.txt"
hook "$PRE"
# The alarm never woke it; the user does, long after the alarm time.
rtc_at 3600
hook "$POST"
absent "$T/shutdown"
absent "$STATE/alarm_target"
absent "$STATE/auto_resume.bak"
eq 1 "$(grep -c "alarm didn't wake the device" "$LOGS_PATH/autopoweroff.log")" "late wake logged"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
# An RTC that doesn't report its time: the system clock is used instead.
rm -f "$APO_RTC_DIR/since_epoch"
hook "$PRE"
eq sys "$(cut -d' ' -f1 "$STATE/alarm_target")" "falls back to the system clock"
echo "sys $(( $(date +%s) - 3 ))" > "$STATE/alarm_target"
hook "$POST"
eq "poweroff_next flag=set" "$(cat "$T/shutdown" 2>/dev/null)" "powers off on the system clock"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
# A target left by an earlier build: a bare system-clock time.
echo $(( $(date +%s) - 3 )) > "$STATE/alarm_target"
hook "$POST"
eq "poweroff_next flag=set" "$(cat "$T/shutdown" 2>/dev/null)" "reads an earlier build's target"
teardown

setup
presses "0|.items[0].selected=1 | .items[1].selected=0"
launch
# Switched off while a hook from an older install lingers: it stands down.
cp "$PRE" "$T/old-pre.sh"
presses "0|.items[0].selected=0"
launch
: > "$APO_RTC_DIR/wakealarm"
hook "$T/old-pre.sh"
eq "" "$(cat "$APO_RTC_DIR/wakealarm")" "no alarm while off"
teardown

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
