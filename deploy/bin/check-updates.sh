#!/usr/bin/env bash
# Compare plugins.lock against the live SVP depot and report available upgrades.
#
#   ./bin/check-updates.sh              report newer versions (exit 1 if any)
#   ./bin/check-updates.sh --rehash     rewrite plugins.lock at the latest stable
#                                       versions, downloading and hashing each one
#
# Also reports the latest SPIP core release so the two never drift apart again.
# Intended for CI (nightly) as much as for humans — see README §Upgrading.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKFILE="$HERE/plugins.lock"
DEPOT_URL="https://plugins.spip.net/depots/principal.xml"
ARCHIVE_BASE="https://files.spip.org/spip-zone"
COMPOSER_REPO="https://get.spip.net/composer"

REHASH=0
[ "${1:-}" = "--rehash" ] && REHASH=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> Fetching depot manifest (~10 MB)..."
curl -fsSL -o "$WORK/principal.xml" "$DEPOT_URL"

echo "==> Checking SPIP core..."
core_latest=$(curl -fsSL "$COMPOSER_REPO/p2/spip/spip.json" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
vs = [p["version"].lstrip("v") for p in d["packages"]["spip/spip"]]
vs = [v for v in vs if re.fullmatch(r"[0-9.]+", v)]
print(max(vs, key=lambda v: tuple(int(n) for n in v.split("."))))
')
core_pinned=$(grep -E '^SPIP_VERSION=' "$HERE/core.lock" | cut -d= -f2)
if [ "$core_pinned" != "$core_latest" ]; then
	echo "  CORE UPDATE: SPIP $core_pinned -> $core_latest"
	echo "               https://blog.spip.net/ — read the release note before bumping."

	# core.lock pins the official zip by checksum, so a version bump needs new
	# URL/SHA/SIZE values, not just a new version string. Compute them here so
	# nobody has to work out the incantation under time pressure after an advisory.
	new_url="https://files.spip.net/spip/archives/spip-v${core_latest}.zip"
	if curl -fsSL -o "$WORK/spip.zip" "$new_url"; then
		new_size=$(wc -c < "$WORK/spip.zip" | tr -d ' ')
		new_sha=$(shasum -a 256 "$WORK/spip.zip" | cut -d' ' -f1)
		if [ "$REHASH" = "1" ]; then
			sed -i.bak \
				-e "s|^SPIP_VERSION=.*|SPIP_VERSION=${core_latest}|" \
				-e "s|^SPIP_URL=.*|SPIP_URL=${new_url}|" \
				-e "s|^SPIP_SHA256=.*|SPIP_SHA256=${new_sha}|" \
				-e "s|^SPIP_SIZE=.*|SPIP_SIZE=${new_size}|" \
				"$HERE/core.lock"
			rm -f "$HERE/core.lock.bak"
			echo "               core.lock updated to ${core_latest}."
		else
			echo "               to apply, run with --rehash, or set by hand:"
			echo "                 SPIP_URL=${new_url}"
			echo "                 SPIP_SHA256=${new_sha}"
			echo "                 SPIP_SIZE=${new_size}"
		fi
	else
		echo "               WARNING: could not fetch ${new_url} to compute a checksum."
	fi
else
	echo "  core up to date: SPIP $core_pinned"
fi

echo "==> Checking plugins..."
python3 - "$WORK/principal.xml" "$LOCKFILE" "$REHASH" <<'PY' > "$WORK/report"
import re, sys

xml_path, lock_path, rehash = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
xml = open(xml_path, encoding="utf-8", errors="replace").read()

def vkey(v):
    return tuple(int(n) if n.isdigit() else 0 for n in re.split(r"[.\-]", v))

# Index the depot by plugin prefix, keeping stable releases only.
depot = {}
for aid, body in re.findall(r'<archive id="([^"]+)"[^>]*>(.*?)</archive>', xml, re.S):
    pre = re.search(r'prefix="([^"]+)"', body)
    ver = re.search(r'version="([^"]+)"', body)
    fil = re.search(r"<file>([^<]+)</file>", body)
    siz = re.search(r"<size>([^<]+)</size>", body)
    sta = re.search(r'etat="([^"]+)"', body)
    if not (pre and ver and fil):
        continue
    if sta and sta.group(1) != "stable":
        continue
    depot.setdefault(pre.group(1).lower(), []).append(
        (ver.group(1), fil.group(1), siz.group(1) if siz else "")
    )

for line in open(lock_path, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    name, version, path, sha, size = line.split("|")
    entries = depot.get(name.lower(), [])
    if not entries:
        print(f"GONE|{name}|{version}|no stable release found in the depot")
        continue
    latest = max(entries, key=lambda e: vkey(e[0]))
    if vkey(latest[0]) > vkey(version):
        print(f"UPDATE|{name}|{version}|{latest[0]}|{latest[1]}|{latest[2]}")
    else:
        print(f"OK|{name}|{version}")
PY

updates=$(grep -c '^UPDATE|' "$WORK/report" || true)
gone=$(grep -c '^GONE|' "$WORK/report" || true)

while IFS='|' read -r kind name a b path size; do
	case "$kind" in
		OK)     echo "  ok        $name $a" ;;
		UPDATE) echo "  UPDATE    $name $a -> $b" ;;
		GONE)   echo "  MISSING   $name $a — $b" ;;
	esac
done < "$WORK/report"

if [ "$REHASH" = "1" ]; then
	echo "==> Rehashing lockfile at latest stable versions..."
	{
		# Preserve the comment header verbatim.
		sed -n '/^[^#]/q;p' "$LOCKFILE"
		while IFS='|' read -r kind name a b path size; do
			case "$kind" in
				OK)
					grep "^$name|" "$LOCKFILE"
					;;
				UPDATE)
					echo "    downloading $name $b..." >&2
					curl -fsSL -o "$WORK/dl.zip" "$ARCHIVE_BASE/$path"
					sha=$(shasum -a 256 "$WORK/dl.zip" | cut -d' ' -f1)
					actual=$(wc -c < "$WORK/dl.zip" | tr -d ' ')
					if [ -n "$size" ] && [ "$actual" != "$size" ]; then
						echo "FATAL: $name size mismatch vs depot manifest" >&2
						exit 1
					fi
					echo "$name|$b|$path|$sha|$actual"
					;;
				GONE)
					echo "FATAL: $name has no stable release upstream — resolve by hand" >&2
					exit 1
					;;
			esac
		done < "$WORK/report"
	} > "$WORK/plugins.lock.new"
	mv "$WORK/plugins.lock.new" "$LOCKFILE"
	echo "==> plugins.lock rewritten. Review the diff, then rebuild the image."
	exit 0
fi

if [ "$gone" -gt 0 ]; then
	echo "==> $gone plugin(s) missing upstream — needs manual attention."
	exit 2
fi
if [ "$updates" -gt 0 ]; then
	echo "==> $updates plugin update(s) available. Run with --rehash to apply."
	exit 1
fi
echo "==> Everything up to date."
