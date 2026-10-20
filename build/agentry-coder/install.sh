#!/bin/sh
# Install the toolchain source.env names from snapshot.debian.org at
# source.env's timestamp, so every package this installs is the one that
# timestamp's archive held, then hold the Go and Node the Dockerfile copied
# in to source.env and write the image's record.
#
#   install.sh <source.env> <out>
#
# Fails closed: unless each of the three signed indexes the snapshot serves
# (trixie, trixie-updates, trixie-security) matches source.env's SHA-256,
# which pins every package in them, unless every package in PACKAGES is
# installed, unless /usr/local/go is GO_VERSION and Node is NODE_MAJOR, and
# unless each tool the image promises answers. Runs in the Dockerfile, never
# in a person's run.
#
# The sources are plain http: the base has no CA certificates yet. apt holds
# every index to the archive's signature (the base's debian-archive-keyring)
# and every package to the index's SHA-256. Check-Valid-Until is off because
# a snapshot's signed Release files expire a week after they were made, so the
# indexes' own SHA-256s are what stop an older signed index being served in
# their place.
#
# <out>/record then holds one line per tool, `<tool> <version>`, and the
# snapshot, for /etc/agentry/coder/record.
set -eu
[ $# -eq 2 ] || {
	echo "usage: install.sh <source.env> <out>" >&2
	exit 2
}
src="$1" out="$2"
# shellcheck source=/dev/null
. "$src"

refuse() {
	echo "install.sh: $*" >&2
	exit 1
}

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

# shellcheck disable=SC2086 # $apt and $PACKAGES are word lists
retry $apt install -y $PACKAGES || refuse "installing the toolchain failed"
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
for p in $PACKAGES; do
	[ "$(dpkg-query -W -f '${db:Status-Status}' "$p" 2>/dev/null)" = installed ] ||
		refuse "$p is not installed"
done

# Go and Node, copied in by the Dockerfile before this runs.
[ "$(/usr/local/go/bin/go env GOVERSION)" = "go$GO_VERSION" ] ||
	refuse "/usr/local/go is $(/usr/local/go/bin/go env GOVERSION), not go$GO_VERSION"
node=$(/usr/local/bin/node --version)
case "$node" in
"v$NODE_MAJOR".*) ;;
*) refuse "node is $node, not Node $NODE_MAJOR" ;;
esac

# Each tool answers, and its version goes in the record.
mkdir -p "$out"
{
	echo "go $GO_VERSION"
	echo "node ${node#v}"
	echo "npm $(/usr/local/bin/npm --version)"
	echo "python3 $(python3 -c 'import platform; print(platform.python_version())')"
	echo "pip $(python3 -m pip --version | cut -d' ' -f2)"
	echo "gcc $(gcc -dumpfullversion)"
	echo "g++ $(g++ -dumpfullversion)"
	echo "make $(make --version | sed -n '1s/^GNU Make //p')"
	echo "cmake $(cmake --version | sed -n '1s/^cmake version //p')"
	echo "pkg-config $(pkg-config --version)"
	echo "git $(git --version | cut -d' ' -f3)"
	echo "curl $(curl --version | sed -n '1s/^curl \([^ ]*\).*/\1/p')"
	echo "jq $(jq --version | sed 's/^jq-//')"
	echo "snapshot $DEBIAN_SNAPSHOT"
} >"$out/record"
while read -r tool version; do
	[ -n "$version" ] || refuse "$tool did not say its version"
done <"$out/record"
