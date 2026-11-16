#!/bin/sh
# Stands in for minui-list in tests. Each launch takes the next line of
# $STUB/list-script, "<exit code>|<jq filter>", writes the filter applied to
# its input as the state, saves its input as list-input-N.json, and exits
# with the code.
file="" out=""
while [ $# -gt 0 ]; do
	case "$1" in
		--file) file="$2"; shift ;;
		--write-location) out="$2"; shift ;;
	esac
	shift
done
n=$(( $(cat "$STUB/list-count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB/list-count"
cp "$file" "$STUB/list-input-$n.json"
line=$(sed -n "${n}p" "$STUB/list-script")
[ -n "$line" ] || exit 2
code=${line%%|*}
filter=${line#*|}
"$JQ_BIN" "$filter" "$file" > "$out"
exit "$code"
