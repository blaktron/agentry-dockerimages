#!/bin/sh
# Fetch the Chrome for Testing build the lockfile's Playwright names, for this
# architecture, and lay it out where Playwright looks for it.
#
#   fetch.sh <source.env> <browsers.json> <out>
#
# Fails closed: unless browsers.json's chromium revision and version are
# source.env's, unless the archive's SHA-256 is source.env's for TARGETARCH,
# and unless the executable is where Playwright's registry expects it.
# Playwright's own installer fetches this same archive (cdn.playwright.dev
# redirects to Google's bucket); fetching it here is what holds it to a
# SHA-256. Runs in the Dockerfile's fetch stage, never in a person's run.
#
# <out> then holds chromium-<revision>/ (chrome-linux64/ on amd64,
# chrome-linux-arm64/ on arm64, with the two markers Playwright's installer
# leaves) and chromium.record, one line the Dockerfile adds to the image's
# record: `chromium <revision> <version> <arch> <sha256>`.
set -eu
[ $# -eq 3 ] || {
	echo "usage: fetch.sh <source.env> <browsers.json> <out>" >&2
	exit 2
}
env="$1" browsers="$2" out="$3"
# shellcheck source=/dev/null
. "$env"

refuse() {
	echo "fetch.sh: $*" >&2
	exit 1
}

case "${TARGETARCH:-}" in
amd64) dir=chrome-linux64 path=linux64 sum="$CHROMIUM_SHA256_AMD64" ;;
arm64) dir=chrome-linux-arm64 path=linux-arm64 sum="$CHROMIUM_SHA256_ARM64" ;;
*) refuse "no Chrome for Testing build for TARGETARCH=${TARGETARCH:-unset}" ;;
esac

# browsers.json is the lockfile's playwright-core's own: the build the server
# will launch. source.env must name the same one.
got=$(node -e '
const b = require(process.argv[1]).browsers.find(b => b.name === "chromium");
console.log(b.revision + " " + b.browserVersion);
' "$browsers")
[ "$got" = "$CHROMIUM_REVISION $CHROMIUM_VERSION" ] ||
	refuse "browsers.json names chromium $got; source.env names $CHROMIUM_REVISION $CHROMIUM_VERSION"

work=$(mktemp -d)
zip="$work/chrome.zip"
url="$CHROMIUM_URL/$CHROMIUM_VERSION/$path/$dir.zip"
echo "fetch $url"
curl -fsSL --retry 5 --retry-delay 10 --proto '=https' --tlsv1.2 -o "$zip" "$url"
echo "$sum  $zip" | sha256sum -c - || refuse "$url does not match source.env's SHA-256"

target="$out/chromium-$CHROMIUM_REVISION"
mkdir -p "$target"
unzip -q "$zip" -d "$target"
rm -rf "$work"
[ -x "$target/$dir/chrome" ] || refuse "no executable at $target/$dir/chrome"
# Playwright's own installer leaves these two markers; the registry reads the
# first as "installed" and the second as "host requirements checked", which
# the Dockerfile's install-deps did.
: >"$target/INSTALLATION_COMPLETE"
: >"$target/DEPENDENCIES_VALIDATED"
printf 'chromium %s %s %s %s\n' "$CHROMIUM_REVISION" "$CHROMIUM_VERSION" "$TARGETARCH" "$sum" >"$out/chromium.record"
