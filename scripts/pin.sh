#!/usr/bin/env bash
# Re-resolve every upstream ref in images.tsv and report where a tag has moved.
#
# It never edits images.tsv. Moving a pin means reviewing what changed
# upstream: edit the manifest by hand, then re-run scripts/mirror.sh.
#
# Usage: scripts/pin.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST="${MANIFEST:-images.tsv}"
rows=$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")
moved=0
total=0

while IFS=$'\t' read -r name upstream pinned _kind _role; do
	total=$((total + 1))
	current=$(docker buildx imagetools inspect "$upstream" --format '{{.Manifest.Digest}}' 2>/dev/null || echo UNRESOLVED)
	if [ "$current" = "$pinned" ]; then
		printf 'ok      %-24s %s\n' "$name" "$upstream"
	else
		printf 'MOVED   %-24s %s\n' "$name" "$upstream"
		printf '          pinned  %s\n' "$pinned"
		printf '          now     %s\n' "$current"
		moved=$((moved + 1))
	fi
done <<<"$rows"

echo
echo "$moved of $total upstream tags have moved since this manifest was pinned"
echo "a moved tag does not change what we publish: mirror.sh copies by digest"
