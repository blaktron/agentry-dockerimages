#!/usr/bin/env bash
# Check the repository without a registry: the manifest, the scripts, the
# workflows and the build contexts' base refs. The `ci` workflow runs it on
# every pull request.
#
# It fails when:
#   - a row of images.tsv does not have five tab-separated fields, its digest
#     is not sha256:<64 hex>, its kind is not mirror or build, or it has no role;
#   - a script in scripts/ fails `bash -n` or shellcheck;
#   - a workflow in .github/workflows/ does not parse, or is not a workflow;
#   - a job on a self-hosted runner can be reached by a pull request from a
#     fork: this repository is public, and a self-hosted runner persists
#     between jobs, so such a job must carry the fork guard below;
#   - a build context's bases.env names a ref that has no row in images.tsv;
#   - the Unsafe Mode image's index generator fails its self-test, or its
#     extras list is not the closed recipe set (build/agentry-unsafe-kali).
#
# It pulls nothing and reads no credential.
#
# Usage:
#   scripts/check.sh              # check this checkout
#   scripts/check.sh --self-test  # break each rule in a copy and expect a failure
#   scripts/check.sh --unsafe-image <ref>
#       read the command index and the extras list out of a built
#       agentry-unsafe-kali and assert that every command in
#       build/agentry-unsafe-kali/fixture-commands.txt resolves through one of
#       them (plan unsafe-mode.md §4.1). This one runs the image: CONTAINER
#       names the runtime (default docker; Apple's `container` on the Mac
#       build host), and PLATFORM (e.g. linux/arm64) asks for, and checks,
#       one architecture.
#
# Needs bash, awk, shellcheck, and python3 with PyYAML.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST="${MANIFEST:-images.tsv}"

checkManifest() {
	local bad=0 line n=0 name _upstream digest kind role extra
	while IFS= read -r line; do
		n=$((n + 1))
		if [[ "$line" =~ ^[[:space:]]*(#|$) ]]; then continue; fi
		IFS=$'\t' read -r name _upstream digest kind role extra <<<"$line"
		if [ -z "${role//[[:space:]]/}" ] || [ -n "${extra:-}" ]; then
			echo "images.tsv:$n: want 5 tab-separated fields (name, upstream, digest, kind, role): ${name:-?}"
			bad=1
			continue
		fi
		if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
			echo "images.tsv:$n: not pinned by digest: $name ($digest)"
			bad=1
		fi
		case "$kind" in
		mirror | build) ;;
		*)
			echo "images.tsv:$n: kind is not mirror or build: $name ($kind)"
			bad=1
			;;
		esac
	done <"$MANIFEST"
	return "$bad"
}

checkScripts() {
	local bad=0 f
	for f in scripts/*.sh; do
		bash -n "$f" || {
			echo "$f: bash -n failed"
			bad=1
		}
	done
	shellcheck scripts/*.sh || bad=1
	return "$bad"
}

checkWorkflows() {
	python3 - .github/workflows/*.y*ml <<'EOF'
import sys, yaml
GUARD = "github.event.pull_request.head.repo.full_name == github.repository"
bad = 0
for path in sys.argv[1:]:
    try:
        doc = yaml.safe_load(open(path))
    except yaml.YAMLError as e:
        print(f"{path}: does not parse: {e}")
        bad = 1
        continue
    # PyYAML reads the key `on` as the boolean True.
    on = doc.get("on", doc.get(True)) if isinstance(doc, dict) else None
    if on is None or not isinstance(doc.get("jobs"), dict):
        print(f"{path}: not a workflow (no `on` or no `jobs`)")
        bad = 1
        continue
    triggers = [on] if isinstance(on, str) else list(on)
    if not {"pull_request", "pull_request_target"} & set(triggers):
        continue
    for job, spec in doc["jobs"].items():
        runs_on = spec.get("runs-on", "")
        labels = [runs_on] if isinstance(runs_on, str) else list(runs_on)
        if "self-hosted" in labels and GUARD not in str(spec.get("if", "")):
            print(f"{path}: job {job} runs on a self-hosted runner and a fork's pull request can reach it; add `if: {GUARD}`")
            bad = 1
sys.exit(bad)
EOF
}

# checkBases reads bases.env the way scripts/build.sh does: a value ends at
# `#`, and whitespace is dropped.
checkBases() {
	local bad=0 f key ref
	for f in build/*/bases.env; do
		[ -e "$f" ] || continue
		while IFS='=' read -r key ref || [ -n "$key" ]; do
			case "$key" in
			'' | \#*) continue ;;
			esac
			ref="${ref%%#*}"
			ref="$(echo "$ref" | tr -d '[:space:]')"
			if ! awk -F'\t' -v u="$ref" '!/^[[:space:]]*#/ && $2 == u { found = 1 } END { exit !found }' "$MANIFEST"; then
				echo "$f: $key=$ref has no row in $MANIFEST"
				bad=1
			fi
		done <"$f"
	done
	return "$bad"
}

UNSAFE_CTX=build/agentry-unsafe-kali

checkUnsafe() {
	local bad=0
	python3 "$UNSAFE_CTX/make-index.py" --self-test || bad=1
	python3 "$UNSAFE_CTX/make-index.py" --check-extras "$UNSAFE_CTX/extras.tsv" || bad=1
	return "$bad"
}

# unsafeImage reads the two files out of the image and resolves each fixture
# command the way the CLI will: the extras list first, then the index.
unsafeImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" arch want tmp cmd how bad=0 n=0
	local run=("$runtime" run --rm)
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	tmp=$(mktemp -d)
	"${run[@]}" "$ref" cat /etc/agentry/unsafe/commands.tsv >"$tmp/commands.tsv"
	"${run[@]}" "$ref" cat /etc/agentry/unsafe/extras.tsv >"$tmp/extras.tsv"
	"${run[@]}" "$ref" cat /etc/agentry/unsafe/ambiguous.tsv >"$tmp/ambiguous.tsv"
	arch=$("${run[@]}" "$ref" dpkg --print-architecture)
	if [ -n "${PLATFORM:-}" ]; then
		want="${PLATFORM##*/}"
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref: asked for $PLATFORM, the image is $arch"
			bad=1
		fi
	fi
	echo "$ref ($arch): $(grep -vc '^#' "$tmp/commands.tsv") commands indexed, $(grep -vc '^#' "$tmp/ambiguous.tsv") ambiguous and left out"
	while read -r cmd; do
		case "$cmd" in '' | \#*) continue ;; esac
		n=$((n + 1))
		how=$(awk -F'\t' -v c="$cmd" '!/^#/ && $2 == c { print "extras " $1 " " $3 (NF > 3 ? " " $4 : ""); exit }' "$tmp/extras.tsv")
		[ -n "$how" ] || how=$(awk -F'\t' -v c="$cmd" '!/^#/ && $1 == c { print "index " $2; exit }' "$tmp/commands.tsv")
		if [ -n "$how" ]; then
			printf 'ok   %-16s %s\n' "$cmd" "$how"
		else
			printf 'FAIL %-16s resolves through neither the extras list nor the index\n' "$cmd"
			bad=1
		fi
	done <"$UNSAFE_CTX/fixture-commands.txt"
	rm -rf "$tmp"
	[ "$bad" -eq 0 ] && echo "ok   all $n fixture commands resolve on $arch"
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkScripts checkWorkflows checkBases checkUnsafe; do
		if "$step"; then
			echo "ok   $step"
		else
			echo "FAIL $step"
			bad=1
		fi
	done
	return "$bad"
}

# The self-test's cases: <name> <the step that must fail>. breakCase breaks
# each in a copy of the checkout; `clean` breaks nothing and must pass.
SELF_TEST_CASES="
clean -
digest checkManifest
role checkManifest
syntax checkScripts
shellcheck checkScripts
workflow checkWorkflows
fork checkWorkflows
bases checkBases
extras checkUnsafe
"

# The shellcheck case appends a literal unexpanded variable on purpose.
# shellcheck disable=SC2016
breakCase() {
	case "$1" in
	clean) ;;
	digest) sed -i '0,/\tsha256:[0-9a-f]*\t/s//\tlatest\t/' images.tsv ;;
	role) awk 'BEGIN { FS = OFS = "\t" } !done && !/^#/ && NF == 5 { NF = 4; done = 1 } 1' images.tsv >x && mv x images.tsv ;;
	syntax) printf '\nif then\n' >>scripts/pin.sh ;;
	shellcheck) printf '\necho $undefined_but_unquoted\n' >>scripts/pin.sh ;;
	workflow) printf 'jobs: [\n' >>.github/workflows/ci.yaml ;;
	fork) sed -i 's/runs-on: ubuntu-latest/runs-on: [self-hosted, linux, x64]/' .github/workflows/ci.yaml ;;
	bases) printf 'EXTRA_IMAGE=example/unmirrored:1\n' >>build/docker-agent/bases.env ;;
	extras) printf 'pip\tx\tx>=1\n' >>build/agentry-unsafe-kali/extras.tsv ;;
	esac
}

selfTest() {
	local src tmp out bad=0 name step got want
	src=$(pwd)
	while read -r name step; do
		[ -n "$name" ] || continue
		tmp=$(mktemp -d)
		out="$tmp.out"
		cp -r "$src/." "$tmp/"
		(cd "$tmp" && breakCase "$name")
		if (cd "$tmp" && scripts/check.sh >"$out" 2>&1); then got=pass; else got=fail; fi
		want=fail
		[ "$step" = - ] && want=pass
		# A broken case must fail at the step that owns its rule, not by accident.
		if [ "$got" = fail ] && [ "$step" != - ] && ! grep -q "^FAIL $step\$" "$out"; then
			got="fail, but not at $step"
		fi
		if [ "$got" = "$want" ]; then
			echo "ok   self-test $name: $got"
		else
			echo "FAIL self-test $name: want $want, got $got"
			sed 's/^/     /' "$out"
			bad=1
		fi
		rm -rf "$tmp" "$out"
	done <<<"$SELF_TEST_CASES"
	return "$bad"
}

case "${1:-}" in
--self-test) selfTest ;;
--unsafe-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --unsafe-image <ref>" >&2
		exit 2
	}
	unsafeImage "$2"
	;;
'') runAll ;;
*)
	echo "usage: scripts/check.sh [--self-test | --unsafe-image <ref>]" >&2
	exit 2
	;;
esac
