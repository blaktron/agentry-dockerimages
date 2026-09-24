#!/usr/bin/env bash
# Check the repository without a registry: the manifest, the scripts, the
# workflows and the build contexts' base refs. The `ci` workflow runs it on
# every pull request.
#
# It fails when:
#   - a row of images.tsv does not have five tab-separated fields, its digest
#     is not sha256:<64 hex>, its kind is not mirror or build, or it has no role;
#   - a script in scripts/ fails `bash -n` or shellcheck;
#   - a workflow in .github/workflows/ does not parse as YAML;
#   - a build context's bases.env names a ref that has no row in images.tsv.
#
# It pulls nothing and reads no credential.
#
# Usage:
#   scripts/check.sh              # check this checkout
#   scripts/check.sh --self-test  # break each rule in a copy and expect a failure
#
# Needs bash, awk, shellcheck, and python3 with PyYAML.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST="${MANIFEST:-images.tsv}"

checkManifest() {
	local bad=0 line n=0
	while IFS= read -r line; do
		n=$((n + 1))
		# Rows only: comments and blank lines are skipped.
		if [[ "$line" =~ ^[[:space:]]*(#|$) ]]; then continue; fi
		local name _upstream digest kind role extra
		IFS=$'\t' read -r name _upstream digest kind role extra <<<"$line"
		if [ -z "$role" ] || [ -n "${extra:-}" ]; then
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
bad = 0
for path in sys.argv[1:]:
    try:
        doc = yaml.safe_load(open(path))
    except yaml.YAMLError as e:
        print(f"{path}: does not parse: {e}")
        bad = 1
        continue
    # PyYAML reads the key `on` as the boolean True.
    if not isinstance(doc, dict) or "jobs" not in doc or not ({"on", True} & doc.keys()):
        print(f"{path}: not a workflow (no `on` or no `jobs`)")
        bad = 1
sys.exit(bad)
EOF
}

checkBases() {
	local bad=0 f key ref
	for f in build/*/bases.env; do
		[ -e "$f" ] || continue
		while IFS='=' read -r key ref; do
			if [[ "$key" =~ ^[[:space:]]*(#|$) ]]; then continue; fi
			if ! awk -F'\t' -v u="$ref" '!/^[[:space:]]*#/ && $2 == u { found = 1 } END { exit !found }' "$MANIFEST"; then
				echo "$f: $key=$ref has no row in $MANIFEST"
				bad=1
			fi
		done <"$f"
	done
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkScripts checkWorkflows checkBases; do
		if "$step"; then
			echo "ok   $step"
		else
			echo "FAIL $step"
			bad=1
		fi
	done
	return "$bad"
}

# selfTest copies the checkout once per rule, breaks that rule, and expects
# the check to fail; then expects the untouched copy to pass.
selfTest() {
	local src tmp bad=0 name got want step
	src=$(pwd)
	# The shellcheck case appends a literal unexpanded variable on purpose.
	# shellcheck disable=SC2016
	breakCase() {
		case "$1" in
		digest) sed -i '0,/\tsha256:[0-9a-f]*\t/s//\tlatest\t/' images.tsv ;;
		role) awk 'BEGIN { FS = OFS = "\t" } !done && !/^#/ && NF == 5 { NF = 4; done = 1 } 1' images.tsv >x && mv x images.tsv ;;
		syntax) printf '\nif then\n' >>scripts/pin.sh ;;
		shellcheck) printf '\necho $undefined_but_unquoted\n' >>scripts/pin.sh ;;
		workflow) printf 'jobs: [\n' >>.github/workflows/images.yaml ;;
		bases) printf 'EXTRA_IMAGE=example/unmirrored:1\n' >>build/docker-agent/bases.env ;;
		esac
	}
	for name in clean digest role syntax shellcheck workflow bases; do
		tmp=$(mktemp -d)
		cp -r "$src/." "$tmp/"
		(cd "$tmp" && breakCase "$name")
		if (cd "$tmp" && scripts/check.sh >"$tmp.out" 2>&1); then
			got=pass
		else
			got=fail
		fi
		want=fail
		[ "$name" = clean ] && want=pass
		# A broken case must fail at the step that owns its rule, not by accident.
		case "$name" in
		digest | role) step=checkManifest ;;
		syntax | shellcheck) step=checkScripts ;;
		workflow) step=checkWorkflows ;;
		bases) step=checkBases ;;
		*) step= ;;
		esac
		if [ -n "$step" ] && ! grep -q "^FAIL $step\$" "$tmp.out"; then
			got="fail, but not at $step"
		fi
		if [ "$got" = "$want" ]; then
			echo "ok   self-test $name: $got"
		else
			echo "FAIL self-test $name: want $want, got $got"
			sed 's/^/     /' "$tmp.out"
			bad=1
		fi
		rm -rf "$tmp" "$tmp.out"
	done
	return "$bad"
}

case "${1:-}" in
--self-test) selfTest ;;
'') runAll ;;
*)
	echo "usage: scripts/check.sh [--self-test]" >&2
	exit 2
	;;
esac
