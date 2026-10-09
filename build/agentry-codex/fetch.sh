#!/bin/sh
# Fetch OpenAI's Codex release binary for this architecture into <out>, and
# fail unless it is the one source.env pins and OpenAI signed. Run by
# build/agentry-codex/Dockerfile's fetch stage, under busybox sh, with
# TARGETARCH set by the build; each download is tried three times.
#
#   1. codex-<triple>.tar.gz must match its SHA-256 in source.env, and hold
#      exactly the one binary.
#   2. The binary must verify against its .sigstore bundle as OpenAI's
#      release workflow at CODEX_TAG and CODEX_COMMIT (verify.sh).
#   3. Then three negative controls, on every build: the same verifier must
#      refuse a copy of the binary with one byte changed, the genuine binary
#      under another tag's identity, and the genuine binary at another
#      commit, each for that reason. A verifier that accepts any of them
#      would accept anything, so the build stops.
#   4. LICENSE and NOTICE at CODEX_COMMIT must match their SHA-256.
#
# <out> then holds codex, codex.sigstore, release (what was fetched, for the
# image's /etc/agentry/codex/release) and licenses/{LICENSE,NOTICE}.
#
# Usage: fetch.sh <source.env> <verify.sh> <out>
set -eu

[ $# -eq 3 ] || {
	echo "usage: fetch.sh <source.env> <verify.sh> <out>" >&2
	exit 2
}
# shellcheck source=/dev/null
. "$1"
verify="$2"
out="$3"

case "${TARGETARCH:-}" in
amd64)
	triple=x86_64-unknown-linux-musl
	tarsha="$CODEX_SHA256_AMD64"
	;;
arm64)
	triple=aarch64-unknown-linux-musl
	tarsha="$CODEX_SHA256_ARM64"
	;;
*)
	echo "fetch.sh: no Codex release pinned for architecture '${TARGETARCH:-}'" >&2
	exit 1
	;;
esac

work=$(mktemp -d)
mkdir -p "$out/licenses"

# get <url> <file>
get() {
	tries=0
	until wget -q -O "$2" "$1"; do
		tries=$((tries + 1))
		if [ "$tries" -ge 3 ]; then
			echo "fetch.sh: could not fetch $1" >&2
			exit 1
		fi
		sleep 5
	done
}

# sha <file> <want>
sha() {
	if ! echo "$2  $1" | sha256sum -c -s; then
		echo "fetch.sh: $1: SHA-256 is $(sha256sum "$1" | cut -d' ' -f1), not $2" >&2
		exit 1
	fi
}

release="https://github.com/openai/codex/releases/download/$CODEX_TAG"
get "$release/codex-$triple.tar.gz" "$work/codex.tar.gz"
sha "$work/codex.tar.gz" "$tarsha"
members=$(tar -tzf "$work/codex.tar.gz")
if [ "$members" != "codex-$triple" ]; then
	echo "fetch.sh: codex-$triple.tar.gz holds '$members', not the one binary codex-$triple" >&2
	exit 1
fi
tar -xzf "$work/codex.tar.gz" -C "$work"
mv "$work/codex-$triple" "$out/codex"
rm "$work/codex.tar.gz"
get "$release/codex-$triple.sigstore" "$out/codex.sigstore"

sh "$verify" "$out/codex" "$out/codex.sigstore" "$CODEX_TAG" "$CODEX_COMMIT"
echo "fetch.sh: codex-$triple verified as openai/codex rust-release.yml at $CODEX_TAG ($CODEX_COMMIT)"

# The negative controls. The changed byte is 1 MB in, inside the code, set to
# its complement so it always differs.
at=1000000
if [ "$(wc -c <"$out/codex")" -le "$at" ]; then
	echo "fetch.sh: the binary is under $at bytes; the negative control cannot change a byte inside it" >&2
	exit 1
fi
cp "$out/codex" "$work/tampered"
byte=$(od -An -tu1 -j "$at" -N1 "$work/codex" | tr -d ' ')
# shellcheck disable=SC2059 # the format is the escaped byte itself
printf "\\$(printf '%03o' $((255 - byte)))" | dd of="$work/tampered" bs=1 seek="$at" conv=notrunc status=none
if cmp -s "$out/codex" "$work/tampered"; then
	echo "fetch.sh: could not make the tampered copy" >&2
	exit 1
fi
# refuse <what> <reason> <verify.sh arguments…>: the verifier must refuse,
# and for the reason named, so a control that failed for another reason (a
# Sigstore fetch that did not answer) never counts as a refusal. The reasons
# are cosign's own messages; a cosign that words them differently stops the
# build here until they are updated.
refuse() {
	what="$1"
	reason="$2"
	shift 2
	if sh "$verify" "$@" >"$work/refusal" 2>&1; then
		echo "fetch.sh: REFUSING: the verifier accepted $what" >&2
		exit 1
	fi
	if ! grep -qF "$reason" "$work/refusal"; then
		echo "fetch.sh: the verifier refused $what, but not because \"$reason\":" >&2
		cat "$work/refusal" >&2
		exit 1
	fi
	echo "fetch.sh: negative control: $what is refused ($reason)"
}
refuse "a binary with one byte changed" "matching bundle to payload" \
	"$work/tampered" "$out/codex.sigstore" "$CODEX_TAG" "$CODEX_COMMIT"
rm "$work/tampered"
refuse "the binary under another tag's identity" "expected GitHub Workflow Ref not found" \
	"$out/codex" "$out/codex.sigstore" rust-v0.0.0 "$CODEX_COMMIT"
refuse "the binary at another commit" "expected GitHub Workflow SHA not found" \
	"$out/codex" "$out/codex.sigstore" "$CODEX_TAG" 0000000000000000000000000000000000000000

get "https://raw.githubusercontent.com/openai/codex/$CODEX_COMMIT/LICENSE" "$out/licenses/LICENSE"
sha "$out/licenses/LICENSE" "$CODEX_LICENSE_SHA256"
get "https://raw.githubusercontent.com/openai/codex/$CODEX_COMMIT/NOTICE" "$out/licenses/NOTICE"
sha "$out/licenses/NOTICE" "$CODEX_NOTICE_SHA256"

chmod 755 "$out/codex"
chmod 644 "$out/codex.sigstore" "$out/licenses/LICENSE" "$out/licenses/NOTICE"
{
	echo "version=$CODEX_VERSION"
	echo "tag=$CODEX_TAG"
	echo "commit=$CODEX_COMMIT"
	echo "asset=codex-$triple.tar.gz"
	echo "asset_sha256=$tarsha"
	echo "binary_sha256=$(sha256sum "$out/codex" | cut -d' ' -f1)"
	echo "signer=https://github.com/openai/codex/.github/workflows/rust-release.yml@refs/tags/$CODEX_TAG"
	echo "licence=$CODEX_LICENSE"
} >"$out/release"
chmod 644 "$out/release"
rm -rf "$work"
echo "fetch.sh: done"
