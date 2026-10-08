#!/bin/sh
# Fetch every row of fetch.tsv into <out>, and refuse any file whose SHA-256
# is not the row's. Run by build/typst/Dockerfile's fetch stage, under
# busybox sh; each download is tried three times.
#
# Usage: fetch.sh <fetch.tsv> <out>
set -eu

list="$1"
out="$2"
tab=$(printf '\t')
n=0
while IFS="$tab" read -r dest url sha licence; do
	case "$dest" in '' | \#*) continue ;; esac
	case "$url" in
	https://*) ;;
	*)
		echo "fetch.tsv: $dest: not an https URL: $url" >&2
		exit 1
		;;
	esac
	[ -n "$licence" ] || {
		echo "fetch.tsv: $dest: no licence" >&2
		exit 1
	}
	mkdir -p "$out/$(dirname "$dest")"
	tries=0
	until wget -q -O "$out/$dest" "$url"; do
		tries=$((tries + 1))
		if [ "$tries" -ge 3 ]; then
			echo "fetch.sh: could not fetch $url" >&2
			exit 1
		fi
		sleep 5
	done
	if ! echo "$sha  $out/$dest" | sha256sum -c -s; then
		echo "fetch.sh: $dest: SHA-256 is not $sha" >&2
		exit 1
	fi
	n=$((n + 1))
done <"$list"
echo "fetched $n files, each matching its SHA-256"
