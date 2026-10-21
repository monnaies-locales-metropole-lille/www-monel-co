#!/usr/bin/env bash
# Compare plugins.lock against the live SVP depot and report available upgrades.
#
#   ./bin/check-updates.sh              report newer versions (exit 1 if any)
#   ./bin/check-updates.sh --rehash     rewrite plugins.lock at the latest stable
#                                       versions, downloading and hashing each one
#
# Also reports the latest SPIP core release so the two never drift apart again,
# and whether the PHP in our last built image is behind its php:X.Y-apache base.
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

# Set when core.lock is behind upstream and the drift has not been applied. The
# plugin report below cannot carry this: a core-only drift leaves every plugin
# "ok", and an exit 0 makes the nightly workflow close the tracking issue.
core_update=0

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
	core_update=1
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
			core_update=0
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

# The runtime stage builds FROM a floating php:X.Y-apache tag, so a PHP security
# release only reaches the site when someone tags a new release. On 2026-10-21
# (PHP2Shell, CVE-2026-109618/109619) nothing here noticed; the site was taken
# offline by hand until 8.4.27 reached the base image.
#
# Compares PHP_VERSION in the config of our last built image (:latest) against the
# current base image. Both carry it as an env var inherited from the official
# image, so this reads two manifests and two configs and pulls nothing.
php_update=0

# Print PHP_VERSION from the linux/amd64 image of <registry>/<repo>:<tag>, using a
# bearer token. Prints nothing if anything along the way fails.
image_php_version() {
	local registry=$1 repo=$2 tag=$3 token=$4 manifest digest config
	local accept_index='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
	local accept_manifest='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

	manifest=$(curl -fsSL -H "Authorization: Bearer $token" -H "Accept: $accept_index, $accept_manifest" \
		"https://$registry/v2/$repo/manifests/$tag") || return 0
	# A multi-arch index (and ours, which also holds provenance/SBOM attestations
	# as unknown/unknown entries) needs one more hop to the amd64 manifest.
	digest=$(python3 -c '
import json, sys
m = json.load(sys.stdin)
for d in m.get("manifests", []):
    p = d.get("platform", {})
    if p.get("os") == "linux" and p.get("architecture") == "amd64":
        print(d["digest"]); break
' <<< "$manifest")
	if [ -n "$digest" ]; then
		manifest=$(curl -fsSL -H "Authorization: Bearer $token" -H "Accept: $accept_manifest" \
			"https://$registry/v2/$repo/manifests/$digest") || return 0
	fi
	digest=$(python3 -c 'import json, sys; print(json.load(sys.stdin)["config"]["digest"])' <<< "$manifest") || return 0
	# Docker Hub redirects blobs to a CDN; curl does not forward a custom
	# Authorization header across hosts, which is what the CDN wants.
	config=$(curl -fsSL -H "Authorization: Bearer $token" "https://$registry/v2/$repo/blobs/$digest") || return 0
	python3 -c '
import json, sys
for e in json.load(sys.stdin)["config"].get("Env") or []:
    if e.startswith("PHP_VERSION="):
        print(e.split("=", 1)[1])
' <<< "$config"
}

echo "==> Checking PHP base image..."
base_ref=$(grep -E '^FROM php:[^ ]+' "$HERE/Dockerfile" | awk '{print $2}' | head -1)
base_tag=${base_ref#php:}
php_series=$(grep -oE '^[0-9]+\.[0-9]+' <<< "$base_tag")
own_repo="monnaies-locales-metropole-lille/monel-spip"

hub_token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/php:pull" \
	| python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])' || true)
php_base=$(image_php_version registry-1.docker.io library/php "$base_tag" "$hub_token" || true)

php_release=$(curl -fsSL "https://www.php.net/releases/index.php?json&version=$php_series" \
	| python3 -c 'import json, sys; print(json.load(sys.stdin).get("version", ""))' || true)

# GITHUB_TOKEN with packages:read in CI. Locally, a token with read:packages, e.g.
#   GITHUB_TOKEN=$(gh auth token) ./bin/check-updates.sh
php_image=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
	ghcr_token=$(curl -fsL -u "token:$GITHUB_TOKEN" \
		"https://ghcr.io/token?service=ghcr.io&scope=repository:$own_repo:pull" \
		| python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])' || true)
	[ -n "$ghcr_token" ] && php_image=$(image_php_version ghcr.io "$own_repo" latest "$ghcr_token" || true)
fi

# Is $1 strictly older than $2?
version_lt() {
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

if [ -z "$php_base" ]; then
	echo "  WARNING: could not read PHP_VERSION from $base_ref on Docker Hub."
elif [ -z "$php_image" ]; then
	echo "  base $base_ref is PHP $php_base; skipped comparing with our image"
	echo "  (needs GITHUB_TOKEN with read:packages to read ghcr.io/$own_repo)."
elif version_lt "$php_image" "$php_base"; then
	php_update=1
	echo "  PHP UPDATE: image PHP $php_image -> base $base_ref PHP $php_base"
	echo "              Tag a new release; no code change is needed, the build picks up"
	echo "              the new base image. Then bump monel_image_tag in deploiement-cyclos."
else
	echo "  php up to date: PHP $php_image ($base_ref)"
fi

# Informational: PHP has released but the official image has not caught up. There
# is nothing to rebuild yet, so this does not fail the check.
if [ -n "$php_release" ] && [ -n "$php_base" ] && version_lt "$php_base" "$php_release"; then
	echo "  note: php.net has PHP $php_release, $base_ref still on $php_base — rebuild once it moves."
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
if [ "$core_update" = "1" ] || [ "$php_update" = "1" ] || [ "$updates" -gt 0 ]; then
	if [ "$core_update" = "1" ]; then
		echo "==> SPIP core is behind upstream — see above."
	fi
	if [ "$php_update" = "1" ]; then
		echo "==> The image's PHP is behind its base image — see above."
	fi
	if [ "$updates" -gt 0 ]; then
		echo "==> $updates plugin update(s) available. Run with --rehash to apply."
	fi
	exit 1
fi
echo "==> Everything up to date."
