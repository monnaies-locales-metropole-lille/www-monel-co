#!/bin/sh
# Fetch and verify the pinned contrib plugins listed in plugins.lock.
#
# Runs at image build time only. Every archive is checksum-verified before it is
# unpacked; a mismatch aborts the build. Nothing is downloaded at runtime.
#
# Usage: fetch-plugins.sh <lockfile> <destination-plugins-dir>

set -eu

LOCKFILE="${1:?usage: fetch-plugins.sh <lockfile> <dest>}"
DEST="${2:?usage: fetch-plugins.sh <lockfile> <dest>}"
BASE_URL="${SPIP_ARCHIVE_BASE:-https://files.spip.org/spip-zone}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$DEST"

count=0
while IFS='|' read -r name version path sha size; do
	case "$name" in ''|\#*) continue ;; esac

	archive="$WORK/$name.zip"
	echo "==> $name $version"

	if ! curl -fsSL --retry 3 --retry-delay 2 -o "$archive" "$BASE_URL/$path"; then
		echo "FATAL: download failed for $name $version ($BASE_URL/$path)" >&2
		exit 1
	fi

	actual_size=$(wc -c < "$archive" | tr -d ' ')
	if [ "$actual_size" != "$size" ]; then
		echo "FATAL: size mismatch for $name $version" >&2
		echo "  expected $size bytes, got $actual_size" >&2
		exit 1
	fi

	actual_sha=$(sha256sum "$archive" | cut -d' ' -f1)
	if [ "$actual_sha" != "$sha" ]; then
		echo "FATAL: checksum mismatch for $name $version" >&2
		echo "  expected $sha" >&2
		echo "  actual   $actual_sha" >&2
		echo "  The upstream archive changed. Do NOT bypass this — verify upstream first." >&2
		exit 1
	fi

	# Archives contain a single top-level dir with a version suffix
	# (e.g. saisies-6.3.5/). Normalise it to the plugin prefix so the
	# deployed tree is stable across upgrades.
	extract="$WORK/x-$name"
	mkdir -p "$extract"
	unzip -q "$archive" -d "$extract"

	top=$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -1)
	if [ -z "$top" ] || [ ! -f "$top/paquet.xml" ]; then
		echo "FATAL: $name archive has no paquet.xml at its root — not a SPIP plugin?" >&2
		exit 1
	fi

	rm -rf "${DEST:?}/$name"
	mv "$top" "$DEST/$name"
	count=$((count + 1))
done < "$LOCKFILE"

echo "==> $count plugins installed into $DEST"

# Belt and braces: nothing under plugins/ should ever be writable at runtime.
find "$DEST" -type d -exec chmod 0555 {} +
find "$DEST" -type f -exec chmod 0444 {} +
