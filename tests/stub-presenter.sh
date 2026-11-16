#!/bin/sh
# Stands in for minui-presenter in tests: logs each message ("page ..." for a
# help page, the screens with NEXT or DONE) and, for screens that wait for a
# button, exits with $STUB/presenter-exit (0 if absent).
msg="" confirm="" waits=1
while [ $# -gt 0 ]; do
	case "$1" in
		--message) msg="$2"; shift ;;
		--confirm-text) confirm="$2"; shift ;;
		--timeout) [ "$2" != 0 ] && waits=0; shift ;;
	esac
	shift
done
case "$confirm" in
	NEXT|DONE) echo "page $msg" >> "$STUB/presenter-log" ;;
	*) echo "$msg" >> "$STUB/presenter-log" ;;
esac
[ "$waits" = 1 ] && exit "$(cat "$STUB/presenter-exit" 2>/dev/null || echo 0)"
exit 0
