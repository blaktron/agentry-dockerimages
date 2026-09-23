#!/usr/bin/env bash
# Copy every `mirror` row of images.tsv into our own registry, by digest.
#
# `docker buildx imagetools create` copies a manifest registry-to-registry:
# the layers never come to this machine, and a multi-platform manifest list
# survives intact, so what we publish is byte-identical to what upstream
# published, for every architecture. Because the manifest bytes are copied
# unchanged, THE DIGEST IS THE SAME on both sides — a consumer can pin
# ghcr.io/blaktron/agentry-alpine@sha256:5291… and get exactly the bytes
# alpine:3.22@sha256:5291… named. The script verifies that after each copy.
#
# Usage:
#   scripts/mirror.sh                 # every mirror row
#   scripts/mirror.sh <name> [...]    # only these names
#
# Needs docker and a `docker login ghcr.io` with a token that can write
# packages in the namespace. This script reads no credential.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="${REGISTRY:-ghcr.io/blaktron}"
MANIFEST="${MANIFEST:-images.tsv}"
ONLY="$*"

want() {
	[ -z "$ONLY" ] && return 0
	local n
	for n in $ONLY; do
		[ "$n" = "$1" ] && return 0
	done
	return 1
}

copied=0
failed=0

while IFS=$'\t' read -r name upstream digest kind _role; do
	[ "${kind:-}" = "mirror" ] || continue
	want "$name" || continue

	case "$digest" in
	sha256:*) ;;
	*)
		echo "SKIP  $name: not pinned by digest ($digest)" >&2
		failed=$((failed + 1))
		continue
		;;
	esac

	repo="${upstream%%:*}"
	tag="${upstream##*:}"
	src="${repo}@${digest}"
	dst="${REGISTRY}/${name}:${tag}"

	echo "==> ${name}"
	echo "    upstream  ${src}"
	echo "    ours      ${dst}"

	if ! docker buildx imagetools create -t "$dst" "$src"; then
		echo "FAIL  $name: copy failed" >&2
		failed=$((failed + 1))
		continue
	fi

	got=$(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}' 2>/dev/null || echo none)
	if [ "$got" = "$digest" ]; then
		echo "    verified  $got"
		copied=$((copied + 1))
	else
		echo "FAIL  $name: destination digest $got, expected $digest" >&2
		failed=$((failed + 1))
	fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")

echo
echo "mirrored $copied, failed $failed"
[ "$failed" -eq 0 ]
