#!/usr/bin/env bash
# Build an image in build/, from pinned upstream source or from the context
# itself.
#
# Refuses to build when a base the context needs is not mirrored into our
# registry: a base resolved from a mutable public tag would make the build
# unreproducible even with the source commit pinned. Each base is passed as
# our mirror's tag and the pinned digest together, so a moved tag in our
# registry cannot change it either.
#
# A context's source.env says what it builds:
#   UPSTREAM_REPO, UPSTREAM_COMMIT, UPSTREAM_TAG   an upstream repository to
#       clone at a pinned commit (build/docker-agent/); without them the
#       context directory itself is the build context (build/agentry-unsafe-kali/)
#   IMAGE_NAME, IMAGE_TAG   the image; IMAGE_TAG from the environment wins
#   PLATFORMS               the architectures a multi-platform image is built
#       for, each natively, one per run with PLATFORM set; --merge then joins
#       the per-architecture tags into IMAGE_TAG
#
# Usage:
#   scripts/build.sh <name>                         # build build/<name>/, do not push
#   PUSH=1 scripts/build.sh <name>                  # build and push to $REGISTRY
#   PLATFORM=linux/arm64 IMAGE_TAG=… PUSH=1 scripts/build.sh <name>
#                                                   # one architecture, tagged <tag>-arm64
#   IMAGE_TAG=… scripts/build.sh --merge <name>     # join <tag>-<arch> for each of
#                                                   # PLATFORMS into <tag>; prints its digest
#
# Needs docker, and for an upstream context git and network access to it; for
# PUSH=1 and --merge a `docker login ghcr.io` with write access. Reads no
# credential itself.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="${REGISTRY:-ghcr.io/blaktron}"
MANIFEST="${MANIFEST:-images.tsv}"
PUSH="${PUSH:-0}"

merge=0
if [ "${1:-}" = "--merge" ]; then
	merge=1
	shift
fi
if [ $# -ne 1 ]; then
	echo "usage: scripts/build.sh [--merge] <name>" >&2
	exit 2
fi
name="$1"
ctx="build/$name"
if [ ! -d "$ctx" ]; then
	echo "no such build context: $ctx" >&2
	exit 2
fi

tagFromEnv="${IMAGE_TAG:-}"
UPSTREAM_REPO="" UPSTREAM_COMMIT="" UPSTREAM_TAG="" PLATFORMS=""
# shellcheck source=/dev/null
. "$ctx/source.env"
IMAGE_TAG="${tagFromEnv:-${IMAGE_TAG:-}}"
if [ -z "$IMAGE_TAG" ]; then
	echo "no IMAGE_TAG: $ctx/source.env sets none, so pass one" >&2
	exit 2
fi
dst="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

if [ "$merge" = 1 ]; then
	[ -n "$PLATFORMS" ] || {
		echo "$ctx builds one platform; there is nothing to merge" >&2
		exit 2
	}
	parts=()
	for p in ${PLATFORMS//,/ }; do
		parts+=("$dst-${p##*/}")
	done
	echo "merge ${parts[*]} → $dst"
	docker buildx imagetools create -t "$dst" "${parts[@]}"
	echo "merged; digest: $(docker buildx imagetools inspect "$dst" --format '{{.Manifest.Digest}}')"
	exit 0
fi

platformArgs=()
if [ -n "$PLATFORMS" ]; then
	if [ -z "${PLATFORM:-}" ]; then
		echo "$ctx is built per architecture: set PLATFORM to one of $PLATFORMS, then --merge" >&2
		exit 2
	fi
	case ",$PLATFORMS," in
	*",$PLATFORM,"*) ;;
	*)
		echo "PLATFORM $PLATFORM is not one of $PLATFORMS" >&2
		exit 2
		;;
	esac
	platformArgs=(--platform "$PLATFORM")
	dst="$dst-${PLATFORM##*/}"
fi

# ourRef <upstream ref> prints the ref in our registry, with its pinned
# digest, from images.tsv.
ourRef() {
	local name digest
	read -r name digest < <(awk -F'\t' -v u="$1" '!/^[[:space:]]*#/ && $2 == u { print $1, $3; exit }' "$MANIFEST")
	[ -n "${name:-}" ] || return 1
	echo "$REGISTRY/$name:${1##*:}@$digest"
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

if [ -n "$UPSTREAM_REPO" ]; then
	echo "clone $UPSTREAM_REPO @ $UPSTREAM_COMMIT"
	git init -q "$work/src"
	git -C "$work/src" remote add origin "$UPSTREAM_REPO"
	git -C "$work/src" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
	git -C "$work/src" checkout -q FETCH_HEAD
	cp "$ctx/Dockerfile" "$work/src/Dockerfile"
	buildargs+=(--build-arg GIT_TAG="$UPSTREAM_TAG" --build-arg GIT_COMMIT="$UPSTREAM_COMMIT")
else
	echo "context $ctx"
	cp -r "$ctx" "$work/src"
fi

echo "build $dst${PLATFORM:+ ($PLATFORM)}"
docker build \
	--file "$work/src/Dockerfile" \
	"${platformArgs[@]}" \
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
