#!/usr/bin/env bash
# Build an image in build/ from pinned upstream source.
#
# Refuses to build when a base the context needs is not mirrored into our
# registry: a base resolved from a mutable public tag would make the build
# unreproducible even with the source commit pinned.
#
# Usage:
#   scripts/build.sh <name>          # build build/<name>/, do not push
#   PUSH=1 scripts/build.sh <name>   # build and push to $REGISTRY
#
# Needs docker, git and network access to the upstream repository; for PUSH=1 a
# `docker login ghcr.io` with write access. Reads no credential itself.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="${REGISTRY:-ghcr.io/blaktron}"
MANIFEST="${MANIFEST:-images.tsv}"
PUSH="${PUSH:-0}"

if [ $# -ne 1 ]; then
	echo "usage: scripts/build.sh <name>" >&2
	exit 2
fi
name="$1"
ctx="build/$name"
if [ ! -d "$ctx" ]; then
	echo "no such build context: $ctx" >&2
	exit 2
fi

# shellcheck source=/dev/null
. "$ctx/source.env"

# ourRef <upstream ref> prints the ref in our registry, from images.tsv.
ourRef() {
	local row
	row=$(awk -F'\t' -v u="$1" '$2 == u { print $1; exit }' "$MANIFEST")
	[ -n "$row" ] || return 1
	echo "$REGISTRY/$row:${1##*:}"
}

missing=""
buildargs=()
while IFS='=' read -r key upstream; do
	case "$key" in
	'' | \#*) continue ;;
	esac
	upstream="${upstream%%#*}"
	upstream="$(echo "$upstream" | tr -d '[:space:]')"
	if ref=$(ourRef "$upstream"); then
		buildargs+=(--build-arg "$key=$ref")
		echo "base  $key = $ref"
	else
		missing="${missing}        $key = $upstream
"
	fi
done <"$ctx/bases.env"

if [ -n "$missing" ]; then
	echo "REFUSING to build $name." >&2
	echo "These bases are not mirrored, so the build would resolve a mutable" >&2
	echo "tag from a public registry:" >&2
	printf '%s' "$missing" >&2
	echo "Pin them in images.tsv and run scripts/mirror.sh, then retry." >&2
	exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "clone $UPSTREAM_REPO @ $UPSTREAM_COMMIT"
git init -q "$work/src"
git -C "$work/src" remote add origin "$UPSTREAM_REPO"
git -C "$work/src" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$work/src" checkout -q FETCH_HEAD

cp "$ctx/Dockerfile" "$work/src/Dockerfile"

dst="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "build $dst"
docker build \
	--file "$work/src/Dockerfile" \
	--build-arg GIT_TAG="$UPSTREAM_TAG" \
	--build-arg GIT_COMMIT="$UPSTREAM_COMMIT" \
	"${buildargs[@]}" \
	--tag "$dst" \
	"$work/src"

echo "built $dst ($(docker image inspect "$dst" --format '{{.Id}}'))"

if [ "$PUSH" = "1" ]; then
	docker push "$dst"
	echo "pushed; digest: $(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
else
	echo "not pushed (PUSH=1 to push)"
fi
