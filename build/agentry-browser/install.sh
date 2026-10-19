#!/bin/sh
# Install Debian's Chromium at the version source.env pins, and the fonts a
# page needs, from snapshot.debian.org at source.env's timestamp, so every
# package this installs is the one that timestamp's archive held.
#
#   install.sh <source.env> <browsers.json> <out>
#
# Fails closed: unless each of the three signed indexes the snapshot serves
# (trixie, trixie-updates, trixie-security) matches source.env's SHA-256,
# which pins every package in them, unless the chromium and
# chromium-common packages downloaded at source.env's Debian version match
# source.env's SHA-256s for TARGETARCH, unless that is the version installed,
# unless the executable is where the image points the server, and unless the
# lockfile's Playwright (browsers.json) was made for this Chromium's major
# version or the next one, the pairing Playwright drives Chromium's DevTools
# protocol for. Runs in the Dockerfile, never in a person's run.
#
# The sources are plain http: the base has no CA certificates yet. apt holds
# every index to the archive's signature (the base's debian-archive-keyring)
# and every package to the index's SHA-256, and the two Chromium packages are
# also held to source.env's. Check-Valid-Until is off because a snapshot's
# signed Release files expire a week after they were made, so the indexes'
# own SHA-256s are what stop an older signed index being served in their
# place.
#
# <out> then holds chromium.record, one line the Dockerfile adds to the
# image's record: `chromium <version> <debian version> <arch> <sha256>
# <snapshot>`.
set -eu
[ $# -eq 3 ] || {
	echo "usage: install.sh <source.env> <browsers.json> <out>" >&2
	exit 2
}
src="$1" browsers="$2" out="$3"
# shellcheck source=/dev/null
. "$src"

refuse() {
	echo "install.sh: $*" >&2
	exit 1
}

case "${TARGETARCH:-}" in
amd64) sum="$CHROMIUM_SHA256_AMD64" commonSum="$CHROMIUM_COMMON_SHA256_AMD64" ;;
arm64) sum="$CHROMIUM_SHA256_ARM64" commonSum="$CHROMIUM_COMMON_SHA256_ARM64" ;;
*) refuse "no Chromium pin for TARGETARCH=${TARGETARCH:-unset}" ;;
esac

[ "${CHROMIUM_DEB_VERSION%%-*}" = "$CHROMIUM_VERSION" ] ||
	refuse "CHROMIUM_DEB_VERSION $CHROMIUM_DEB_VERSION is not a package of Chromium $CHROMIUM_VERSION"

# browsers.json is the lockfile's playwright-core's own: the Chromium build
# that Playwright release was made against.
want=$(node -e '
const b = require(process.argv[1]).browsers.find(b => b.name === "chromium");
console.log(b.browserVersion.split(".")[0]);
' "$browsers")
have="${CHROMIUM_VERSION%%.*}"
[ "$have" = "$want" ] || [ "$have" = "$((want - 1))" ] ||
	refuse "Playwright $PLAYWRIGHT_VERSION was made for Chromium $want; source.env pins $CHROMIUM_VERSION"

rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
cat >/etc/apt/sources.list.d/snapshot.sources <<SOURCES
Types: deb
URIs: http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT
Suites: trixie trixie-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
Check-Valid-Until: no

Types: deb
URIs: http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
Check-Valid-Until: no
SOURCES

# The snapshot archive is slow and fails now and then; each step is retried
# half a minute apart, and a failure is never taken as a success.
tries=5
retry() {
	n=1
	until "$@"; do
		[ "$n" -ge "$tries" ] && return 1
		n=$((n + 1))
		sleep 30
	done
}
export DEBIAN_FRONTEND=noninteractive
apt="apt-get -o Acquire::Retries=5 -o APT::Install-Recommends=false -o APT::Install-Suggests=false"
# shellcheck disable=SC2086 # $apt is a word list
retry $apt update || refuse "apt-get update from the snapshot failed"

# Each signed index apt kept must be the one source.env pins, and there must
# be exactly these three.
lists=/var/lib/apt/lists
[ "$(find "$lists" -maxdepth 1 -name '*_InRelease' | wc -l)" = 3 ] ||
	refuse "apt kept other indexes than trixie, trixie-updates and trixie-security"
for pair in "debian_${DEBIAN_SNAPSHOT}_dists_trixie $DEBIAN_INDEX_SHA256_TRIXIE" \
	"debian_${DEBIAN_SNAPSHOT}_dists_trixie-updates $DEBIAN_INDEX_SHA256_TRIXIE_UPDATES" \
	"debian-security_${DEBIAN_SNAPSHOT}_dists_trixie-security $DEBIAN_INDEX_SHA256_TRIXIE_SECURITY"; do
	f="$lists/snapshot.debian.org_archive_${pair% *}_InRelease"
	echo "${pair#* }  $f" | sha256sum -c - || refuse "$f is not the index source.env pins"
done

# The two Chromium packages are downloaded and held to source.env's SHA-256
# before anything is installed from them.
work=$(mktemp -d)
chown _apt "$work"
# shellcheck disable=SC2086 # $apt is a word list
(cd "$work" && retry $apt download "chromium=$CHROMIUM_DEB_VERSION" "chromium-common=$CHROMIUM_DEB_VERSION") ||
	refuse "downloading chromium $CHROMIUM_DEB_VERSION failed"
deb="$work/chromium_$(echo "$CHROMIUM_DEB_VERSION" | sed 's/:/%3a/')_$TARGETARCH.deb"
common="$work/chromium-common_$(echo "$CHROMIUM_DEB_VERSION" | sed 's/:/%3a/')_$TARGETARCH.deb"
echo "$sum  $deb" | sha256sum -c - || refuse "$deb does not match source.env's SHA-256"
echo "$commonSum  $common" | sha256sum -c - || refuse "$common does not match source.env's SHA-256"

# The fonts Playwright installs beside its own Chromium on Debian 13, without
# the X server: the browser runs headless.
fonts="fonts-liberation fonts-noto-color-emoji fonts-unifont xfonts-scalable fonts-ipafont-gothic fonts-wqy-zenhei fonts-tlwg-loma-otf fonts-freefont-ttf"
# shellcheck disable=SC2086 # $apt and $fonts are word lists
retry $apt install -y "$deb" "$common" $fonts || refuse "installing chromium $CHROMIUM_DEB_VERSION failed"
rm -rf "$work" /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

[ "$(dpkg-query -W -f '${Version}' chromium)" = "$CHROMIUM_DEB_VERSION" ] &&
	[ "$(dpkg-query -W -f '${Version}' chromium-common)" = "$CHROMIUM_DEB_VERSION" ] ||
	refuse "chromium installed is not $CHROMIUM_DEB_VERSION"
[ -x /usr/lib/chromium/chromium ] || refuse "no executable at /usr/lib/chromium/chromium"

mkdir -p "$out"
printf 'chromium %s %s %s %s %s\n' "$CHROMIUM_VERSION" "$CHROMIUM_DEB_VERSION" "$TARGETARCH" "$sum" "$DEBIAN_SNAPSHOT" >"$out/chromium.record"
