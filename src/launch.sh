#!/bin/sh
# Auto Power Off for NextUI: the settings screen.
#
# Turns the device fully off once it has been in deep sleep for the chosen
# time. The work happens in two NextUI hooks this screen installs (see
# hooks/); the screen only stores the setting and installs or removes them.
#
# Controls: left/right change a setting, A saves, B leaves without saving.

PAK_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$PAK_DIR/common.sh"

PRE_DIR="$USERDATA_PATH/.hooks/pre-sleep.d"
POST_DIR="$USERDATA_PATH/.hooks/post-resume.d"

BIN="$PAK_DIR/bin"
JQ="$BIN/jq"
LIST="$BIN/$PLATFORM/minui-list"
PRESENTER="$BIN/$PLATFORM/minui-presenter"
: "${APO_WORK:=$APO_TMP/autopoweroff-ui}"

# Rows of the settings list, by index.
ROW_ENABLED=0
ROW_TIMEOUT=1

###############################################################################
# Settings and hooks

install_hooks() {
	mkdir -p "$APO_STATE_DIR" "$PRE_DIR" "$POST_DIR"
	cp -f "$PAK_DIR/common.sh" "$APO_STATE_DIR/common.sh"
	cp -f "$PAK_DIR/hooks/pre-sleep.sh" "$PRE_DIR/$APO_HOOK_NAME"
	cp -f "$PAK_DIR/hooks/post-resume.sh" "$POST_DIR/$APO_HOOK_NAME"
	chmod +x "$APO_STATE_DIR/common.sh" "$PRE_DIR/$APO_HOOK_NAME" "$POST_DIR/$APO_HOOK_NAME"
}

remove_hooks() {
	rm -f "$PRE_DIR/$APO_HOOK_NAME" "$POST_DIR/$APO_HOOK_NAME"
	apo_clear_alarm
	rm -f "$APO_RESUME_BAK"
}

# save ENABLED TIMEOUT: store the settings and put the hooks in place.
save() {
	mkdir -p "$APO_STATE_DIR"
	echo "$1" > "$APO_ENABLED_FILE"
	echo "$2" > "$APO_TIMEOUT_FILE"
	if [ "$1" = 1 ]; then install_hooks; else remove_hooks; fi
	sync
	apo_log "settings: $(on_off "$1"), $(apo_label "$2")"
}

on_off() { if [ "$1" = 1 ]; then echo "On"; else echo "Off"; fi }

# Index of a time in APO_TIMEOUTS, or of the default when it isn't listed.
timeout_index() {
	i=0
	for t in $APO_TIMEOUTS; do
		[ "$t" = "$1" ] && { echo "$i"; return; }
		i=$((i + 1))
	done
	timeout_index "$APO_DEFAULT_TIMEOUT"
}

timeout_at() {
	i=0
	for t in $APO_TIMEOUTS; do
		[ "$i" = "$1" ] && { echo "$t"; return; }
		i=$((i + 1))
	done
	echo "$APO_DEFAULT_TIMEOUT"
}

###############################################################################
# Screens

# message TEXT [SECONDS]: a brief notice that closes itself.
message() {
	"$PRESENTER" --message "$1" --timeout "${2:-2}" >/dev/null 2>&1
}

# write_list ENABLED TIMEOUT_INDEX: the list's input, with the settings as
# given.
write_list() {
	labels=""
	for t in $APO_TIMEOUTS; do labels="$labels$(apo_label "$t")
"; done
	printf '%s' "$labels" | "$JQ" -R -s \
		--argjson enabled "$1" --argjson timeout "$2" '
		split("\n") | map(select(length > 0)) as $times |
		{
			items: [
				{name: "Auto Power Off", options: ["Off", "On"], selected: $enabled,
					features: {draw_arrows: true, confirm_text: "SAVE"}},
				{name: "Power off after", options: $times, selected: $timeout,
					features: {draw_arrows: true, confirm_text: "SAVE"}}
			]
		}' > "$APO_WORK/list.json"
}

missing_tools() {
	for f in "$JQ" "$LIST" "$PRESENTER"; do
		[ -x "$f" ] || chmod +x "$f" 2>/dev/null
		[ -x "$f" ] || return 0
	done
	return 1
}

###############################################################################

if missing_tools; then
	apo_log "launch: no settings screen for platform $PLATFORM"
	exit 1
fi

mkdir -p "$APO_WORK"
trap 'rm -rf "$APO_WORK"' EXIT

if ! apo_supported; then
	rtc_name=$(cat "$APO_RTC_DIR/name" 2>/dev/null)
	apo_log "launch: no RTC wake alarm (rtc=${rtc_name:-missing}), not supported"
	[ "$(apo_enabled)" = 1 ] && save 0 "$(apo_chosen_timeout)"
	"$PRESENTER" --message "This device can't wake itself from sleep, so Auto Power Off can't work here." \
		--confirm-show --confirm-text "OK" >/dev/null 2>&1
	exit 0
fi

enabled=$(apo_enabled)
timeout=$(apo_chosen_timeout)
write_list "$enabled" "$(timeout_index "$timeout")"

"$LIST" --file "$APO_WORK/list.json" --title "Auto Power Off" \
	--write-value state --write-location "$APO_WORK/state.json" \
	--always-show-confirm >/dev/null 2>&1
code=$?

case "$code" in
	0) ;;
	2|3) exit 0 ;;
	*)
		apo_log "launch: settings list failed ($code)"
		message "Something went wrong showing the settings" 3
		exit 1
		;;
esac

# What the screen showed when A was pressed.
shown_enabled=$("$JQ" -r ".items[$ROW_ENABLED].selected // empty" "$APO_WORK/state.json" 2>/dev/null)
shown_index=$("$JQ" -r ".items[$ROW_TIMEOUT].selected // empty" "$APO_WORK/state.json" 2>/dev/null)
case "$shown_enabled" in 0|1) ;; *) shown_enabled=$enabled ;; esac
case "$shown_index" in
	''|*[!0-9]*) shown_timeout=$timeout ;;
	*) shown_timeout=$(timeout_at "$shown_index") ;;
esac

save "$shown_enabled" "$shown_timeout"
if [ "$shown_enabled" = 1 ]; then
	message "Saved: powers off after $(apo_label "$shown_timeout") asleep"
else
	message "Saved: Auto Power Off is off"
fi
exit 0
