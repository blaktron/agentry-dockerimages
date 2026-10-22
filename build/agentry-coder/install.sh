#!/bin/sh
# Install the toolchain source.env names from snapshot.debian.org at
# source.env's timestamp, so every package this installs is the one that
# timestamp's archive held, then the release binaries it pins, each held to
# its SHA-256, then hold the Go and Node the Dockerfile copied in to
# source.env and write the image's record.
#
#   install.sh <source.env> <out>
#
# Fails closed: unless each of the three signed indexes the snapshot serves
# (trixie, trixie-updates, trixie-security) matches source.env's SHA-256,
# which pins every package in them, unless every package in PACKAGES is
# installed, unless every release binary and licence matches its SHA-256 and
# answers with its pinned version, unless /usr/local/go is GO_VERSION and
# Node is NODE_MAJOR, and unless each tool the image promises answers. Runs in the Dockerfile, never
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

# The release binaries source.env pins. Each download goes to a temporary
# folder, is held to its SHA-256 before anything reads it, and only then is
# unpacked; the binary is installed root-owned and 0755 into /usr/local/bin,
# its licence into /usr/share/licenses/agentry-coder/<tool>. https only, with
# the CA certificates just installed, and no redirect to plain http.
arch=$(dpkg --print-architecture)
case "$arch" in
amd64 | arm64) ;;
*) refuse "no pinned release binaries for $arch" ;;
esac
# pick <amd64 value> <arm64 value> prints this architecture's.
pick() { if [ "$arch" = amd64 ]; then echo "$1"; else echo "$2"; fi; }
dl=$(mktemp -d)
fetch() { # fetch <url> <sha256> <file>
	retry curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -o "$dl/$3" "$1" ||
		refuse "downloading $1 failed"
	echo "$2  $dl/$3" | sha256sum -c - || refuse "$1 is not the download source.env pins"
}
licence() { # licence <tool> <file>
	install -D -m 0644 "$2" "/usr/share/licenses/agentry-coder/$1/LICENSE"
}

fetch "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_linux_$arch.tar.gz" "$(pick "$GH_SHA256_AMD64" "$GH_SHA256_ARM64")" gh.tar.gz
tar -xzf "$dl/gh.tar.gz" -C "$dl" "gh_${GH_VERSION}_linux_$arch/bin/gh" "gh_${GH_VERSION}_linux_$arch/LICENSE"
install -m 0755 "$dl/gh_${GH_VERSION}_linux_$arch/bin/gh" /usr/local/bin/gh
licence gh "$dl/gh_${GH_VERSION}_linux_$arch/LICENSE"

fetch "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/$GLAB_VERSION/glab_${GLAB_VERSION}_linux_$arch.tar.gz" "$(pick "$GLAB_SHA256_AMD64" "$GLAB_SHA256_ARM64")" glab.tar.gz
mkdir "$dl/glab"
tar -xzf "$dl/glab.tar.gz" -C "$dl/glab" bin/glab LICENSE
install -m 0755 "$dl/glab/bin/glab" /usr/local/bin/glab
licence glab "$dl/glab/LICENSE"

fetch "https://gitea.com/gitea/tea/releases/download/v$TEA_VERSION/tea-$TEA_VERSION-linux-$arch.xz" "$(pick "$TEA_SHA256_AMD64" "$TEA_SHA256_ARM64")" tea.xz
xz -dc "$dl/tea.xz" >"$dl/tea"
install -m 0755 "$dl/tea" /usr/local/bin/tea
fetch "https://gitea.com/gitea/tea/raw/tag/v$TEA_VERSION/LICENSE" "$TEA_LICENSE_SHA256" tea-LICENSE
licence tea "$dl/tea-LICENSE"

fetch "https://github.com/google/osv-scanner/releases/download/v$OSV_SCANNER_VERSION/osv-scanner_linux_$arch" "$(pick "$OSV_SCANNER_SHA256_AMD64" "$OSV_SCANNER_SHA256_ARM64")" osv-scanner
install -m 0755 "$dl/osv-scanner" /usr/local/bin/osv-scanner
fetch "https://raw.githubusercontent.com/google/osv-scanner/v$OSV_SCANNER_VERSION/LICENSE" "$OSV_SCANNER_LICENSE_SHA256" osv-scanner-LICENSE
licence osv-scanner "$dl/osv-scanner-LICENSE"

# gitleaks names amd64 x64.
glarch=$arch
[ "$arch" = amd64 ] && glarch=x64
fetch "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_$glarch.tar.gz" "$(pick "$GITLEAKS_SHA256_AMD64" "$GITLEAKS_SHA256_ARM64")" gitleaks.tar.gz
mkdir "$dl/gitleaks"
tar -xzf "$dl/gitleaks.tar.gz" -C "$dl/gitleaks" gitleaks LICENSE
install -m 0755 "$dl/gitleaks/gitleaks" /usr/local/bin/gitleaks
licence gitleaks "$dl/gitleaks/LICENSE"
rm -rf "$dl"

# Each tool answers, and its version goes in the record. The CLIs that
# report usage or look for updates are told not to, here as in the image.
export GH_TELEMETRY=false GH_NO_UPDATE_NOTIFIER=1 GH_NO_EXTENSION_UPDATE_NOTIFIER=1 \
	GLAB_SEND_TELEMETRY=false GLAB_CHECK_UPDATE=false
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
	echo "gh $(gh --version | sed -n '1s/^gh version \([^ ]*\).*/\1/p')"
	echo "glab $(glab --version | sed -n '1s/^glab \([^ ]*\).*/\1/p')"
	echo "tea $(tea --version | sed 's/\x1b\[[0-9;]*m//g' | sed -n '1s/^Version: \([^[:space:]]*\).*/\1/p')"
	echo "osv-scanner $(osv-scanner --version | sed -n 's/^osv-scanner version: //p')"
	echo "gitleaks $(gitleaks version)"
	echo "snapshot $DEBIAN_SNAPSHOT"
} >"$out/record"
while read -r tool version; do
	[ -n "$version" ] || refuse "$tool did not say its version"
done <"$out/record"
for pair in "gh $GH_VERSION" "glab $GLAB_VERSION" "tea $TEA_VERSION" "osv-scanner $OSV_SCANNER_VERSION" "gitleaks $GITLEAKS_VERSION"; do
	grep -qx "$pair" "$out/record" || refuse "${pair% *} is not ${pair#* }, the version source.env pins"
done
