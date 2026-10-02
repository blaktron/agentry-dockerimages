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
#   - the Unsafe Mode image's index generator fails its self-test, its
#     extras list is not the closed recipe set, or base-unowned.txt is not
#     one command and one reason a row (build/agentry-unsafe-kali);
#   - the files image's fixture list names a file that is not there, a
#     fixture has no row, or a row names a decoder the image does not hold
#     (build/agentry-files).
#
# It pulls nothing and reads no credential, except in --unsafe-image and
# --files-image mode, which run the image they name.
#
# Usage:
#   scripts/check.sh              # check this checkout
#   scripts/check.sh --self-test  # break each rule in a copy and expect a failure
#   scripts/check.sh --unsafe-image <ref>
#       read the command index and the extras list out of a built
#       agentry-unsafe-kali and assert that every command in
#       build/agentry-unsafe-kali/fixture-commands.txt resolves through one of
#       them (plan unsafe-mode.md §4.1), list the commands the index left
#       out as ambiguous, and fail when a program on the image's own PATH has
#       no row in the index, the ambiguous list or base-unowned.txt
#       (agentry-dockerimages#23). This one pulls and runs the image: CONTAINER names
#       the runtime (default docker; Apple's `container` on the Mac build
#       host), and PLATFORM (e.g. linux/arm64) asks for, and checks, one
#       architecture. It runs under macOS's bash 3.2.
#   scripts/check.sh --files-image <ref>
#       decode each fixture in build/agentry-files/fixtures/ inside a built
#       agentry-files, with the argv the runner's decode role uses
#       (agentry-cli runnerimage/decode), with no network, every capability
#       dropped and a read-only root, and assert the phrase expect.tsv names
#       (plan file-handling.md §4; agentry-dockerimages#28). It also prints the
#       package record. CONTAINER and PLATFORM as for --unsafe-image.
#
# Needs bash, awk, shellcheck, and python3 with PyYAML; --unsafe-image needs
# a container runtime instead.
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
	python3 "$UNSAFE_CTX/make-index.py" --check-unowned "$UNSAFE_CTX/base-unowned.txt" || bad=1
	return "$bad"
}

FILES_CTX=build/agentry-files

# checkFiles holds the files image's fixture list to the fixtures: each row
# names a fixture that exists and a decoder the image holds, and each fixture
# has a row.
checkFiles() {
	local bad=0 f name tool _phrase
	while IFS=$'\t' read -r name tool _phrase; do
		case "$name" in '' | \#*) continue ;; esac
		if [ ! -f "$FILES_CTX/fixtures/$name" ]; then
			echo "$FILES_CTX/fixtures/expect.tsv: no fixture $name"
			bad=1
		fi
		case "$tool" in
		pandoc | pdftotext | tesseract) ;;
		*)
			echo "$FILES_CTX/fixtures/expect.tsv: $name: unknown decoder $tool"
			bad=1
			;;
		esac
	done <"$FILES_CTX/fixtures/expect.tsv"
	for f in "$FILES_CTX"/fixtures/*; do
		name="${f##*/}"
		[ "$name" = expect.tsv ] && continue
		if ! awk -F'\t' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$FILES_CTX/fixtures/expect.tsv"; then
			echo "$FILES_CTX/fixtures/$name: no row in expect.tsv"
			bad=1
		fi
	done
	return "$bad"
}

# filesImage decodes every fixture inside the image the way the decode
# container runs: no network, every capability dropped, no new privileges, a
# read-only root, the fixtures read-only, and a tmpfs for the output.
filesImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" name tool phrase argv out bad=0 n=0
	local run=("$runtime" run --rm --network none --cap-drop ALL --security-opt label=disable
		--security-opt no-new-privileges --read-only --tmpfs /out
		-v "$PWD/$FILES_CTX/fixtures:/in:ro")
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	echo "packages:"
	"${run[@]}" "$ref" cat /etc/agentry/files/packages | sed 's/^/  /'
	while IFS=$'\t' read -r name tool phrase; do
		case "$name" in '' | \#*) continue ;; esac
		n=$((n + 1))
		case "$tool" in
		pandoc) argv=(pandoc --sandbox --to=plain --wrap=none --output=/out/t.txt "/in/$name") ;;
		pdftotext) argv=(pdftotext -layout -enc UTF-8 -q "/in/$name" /out/t.txt) ;;
		tesseract) argv=(tesseract "/in/$name" /out/t -l eng) ;;
		esac
		# The decoder writes into the tmpfs; cat reads it back in the same
		# container, which is gone afterwards.
		if out=$("${run[@]}" "$ref" sh -c '"$@" >/dev/null 2>&1 && cat /out/t.txt' decode "${argv[@]}"); then
			if grep -qF -- "$phrase" <<<"$out"; then
				echo "ok   $name ($tool)"
			else
				echo "FAIL $name ($tool): decoded, but \"$phrase\" is not in the text"
				bad=1
			fi
		else
			echo "FAIL $name ($tool): the decoder failed"
			bad=1
		fi
	done <"$FILES_CTX/fixtures/expect.tsv"
	[ "$n" -gt 0 ] || {
		echo "FAIL no fixtures"
		bad=1
	}
	return "$bad"
}

# unsafeImage reads the three files out of the image, resolves each fixture
# command the way the CLI will (the extras list first, then the index), and
# holds every program on the image's own PATH to having a row.
unsafeImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" arch want tmp cmd how bad=0 n=0
	local run=("$runtime" run --rm)
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	tmp=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: tmp is local
	trap "rm -rf '$tmp'" EXIT
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
	echo "$ref ($arch): $(grep -vc '^#' "$tmp/commands.tsv") commands indexed, $(grep -vc '^#' "$tmp/ambiguous.tsv") ambiguous and left out:"
	# The ambiguities, as command(packages), wrapped: the plan has check.sh
	# report what the index leaves out rather than guess.
	awk -F'\t' '!/^#/ { printf "%s(%s) ", $1, $2 } END { print "" }' "$tmp/ambiguous.tsv" | fold -s -w 100 | sed 's/^/     /'
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
	[ "$bad" -eq 0 ] && echo "ok   all $n fixture commands resolve on $arch"
	# Every program on the base's own PATH has a row (agentry-dockerimages#23):
	# in the index, in the ambiguous list, or named in base-unowned.txt. One
	# without would be called unavailable by the CLI although the run can
	# start it. The directories are the image's ENV PATH, as make-index.py's
	# BASE_PATH; the grep is its COMMAND grammar, since a name outside it ([)
	# cannot be declared.
	# shellcheck disable=SC2016 # expanded in the image's shell
	"${run[@]}" "$ref" sh -c 'for d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do for f in "$d"/*; do if [ -x "$f" ] && [ ! -d "$f" ]; then echo "${f##*/}"; fi; done; done' |
		{ grep -E '^[A-Za-z0-9][A-Za-z0-9._+-]*$' || true; } | sort -u >"$tmp/path.txt"
	awk -F'\t' '!/^#/ && NF { print $1 }' "$tmp/commands.tsv" "$tmp/ambiguous.tsv" "$UNSAFE_CTX/base-unowned.txt" | sort -u >"$tmp/rows.txt"
	comm -23 "$tmp/path.txt" "$tmp/rows.txt" >"$tmp/norow.txt"
	if [ ! -s "$tmp/path.txt" ]; then
		echo "FAIL $ref: no program found on the base's PATH"
		bad=1
	elif [ -s "$tmp/norow.txt" ]; then
		echo "FAIL on the base's PATH with no row in the index, the ambiguous list or base-unowned.txt: $(tr '\n' ' ' <"$tmp/norow.txt")"
		bad=1
	else
		echo "ok   all $(grep -c . "$tmp/path.txt") programs on the base's PATH have a row"
	fi
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkScripts checkWorkflows checkBases checkUnsafe checkFiles; do
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
unowned checkUnsafe
fixture checkFiles
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
	unowned) printf 'policy-rc.d\ttwice\n' >>build/agentry-unsafe-kali/base-unowned.txt ;;
	fixture) printf 'missing.docx\tpandoc\tx\n' >>build/agentry-files/fixtures/expect.tsv ;;
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
--files-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --files-image <ref>" >&2
		exit 2
	}
	filesImage "$2"
	;;
'') runAll ;;
*)
	echo "usage: scripts/check.sh [--self-test | --unsafe-image <ref> | --files-image <ref>]" >&2
	exit 2
	;;
esac
