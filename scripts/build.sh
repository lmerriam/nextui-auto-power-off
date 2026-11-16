#!/bin/sh
# Builds dist/Auto.Power.Off.pak.zip: the pak's files plus the helper
# binaries it runs, fetched at pinned versions and checked against pinned
# SHA-256 sums. The zip holds the pak folder's contents at its root, as the
# NextUI Pak Store expects.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.cache"
STAGE="$ROOT/dist/stage"
ZIP="$ROOT/dist/Auto.Power.Off.pak.zip"

LIST_VERSION=0.16.0
PRESENTER_VERSION=0.14.0
JQ_VERSION=1.8.1

# name|url|sha256
DEPS="
minui-list-tg5040-nextui|https://github.com/josegonzalez/minui-list/releases/download/$LIST_VERSION/minui-list-tg5040-nextui|0888e85d727c24aa96b99c71e29566fce7e818d7c85152082b460be31f7bfab1
minui-presenter-tg5040-nextui|https://github.com/josegonzalez/minui-presenter/releases/download/$PRESENTER_VERSION/minui-presenter-tg5040-nextui|264785d9aa3e5f9ac2074c539e480ea1fd6dbe220ee3a52734511aa9ec759830
jq-linux-arm64|https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-arm64|6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
"

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

fetch() { # name url sum
	mkdir -p "$CACHE"
	if [ ! -f "$CACHE/$1" ] || [ "$(sha256 "$CACHE/$1")" != "$3" ]; then
		echo "fetching $1"
		curl -fsSL -o "$CACHE/$1.part" "$2"
		got="$(sha256 "$CACHE/$1.part")"
		if [ "$got" != "$3" ]; then
			rm -f "$CACHE/$1.part"
			echo "checksum mismatch for $1: got $got, want $3" >&2
			exit 1
		fi
		mv "$CACHE/$1.part" "$CACHE/$1"
	fi
}

echo "$DEPS" | while IFS='|' read -r name url sum; do
	if [ -n "$name" ]; then fetch "$name" "$url" "$sum"; fi
done

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/bin"
cp -R "$ROOT/src/." "$STAGE/"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
# Platforms this release supports; pak.json's "platforms" must match. Add one
# here (with its two binaries pinned above) once it has been tested.
for platform in tg5040; do
	mkdir -p "$STAGE/bin/$platform"
	cp "$CACHE/minui-list-$platform-nextui" "$STAGE/bin/$platform/minui-list"
	cp "$CACHE/minui-presenter-$platform-nextui" "$STAGE/bin/$platform/minui-presenter"
done
cp "$CACHE/jq-linux-arm64" "$STAGE/bin/jq"
find "$STAGE" -name '*.sh' -exec chmod 755 {} +
chmod 755 "$STAGE"/bin/jq "$STAGE"/bin/*/*

# The card is FAT32, so the zip's own timestamps and attributes don't matter;
# -X leaves out macOS extras.
(cd "$STAGE" && zip -qrX "$ZIP" .)
rm -rf "$STAGE"
echo "built $ZIP ($(du -h "$ZIP" | cut -f1))"
