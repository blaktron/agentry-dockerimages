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
#     or no phrase
#     (build/agentry-files);
#   - the Typst image's fetch list has a row that is not four fields, names
#     no pinned commit, has no SHA-256 or no known licence, or repeats a path;
#     its patch is missing, empty or not named in source.env; or its font
#     list is empty (build/typst).
#
# It pulls nothing and reads no credential, except in --unsafe-image,
# --files-image and --typst-image mode, which run the image they name.
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
#       (plan file-handling.md §4; agentry-dockerimages#28), as the invoking
#       uid with the decode container's environment and limits. It prints the
#       package record and fails on any setuid or setgid file. PLATFORM
#       (e.g. linux/arm64) asks for, and checks, one architecture. It also
#       runs clamscan, with the argv the decode role uses, against a one-line
#       signature database made here (the EICAR test file's MD5), and fails
#       unless the EICAR file and a zip of it are found and every fixture is
#       clean (agentry-dockerimages#30).
#   scripts/check.sh --typst-image <ref>
#       run a built agentry-typst with no network, every capability dropped,
#       a read-only root and the invoking uid (plan scratch-and-pdf-reports
#       §5, D24, D26, D27; agentry-dockerimages#48): `typst fonts` must list
#       every family in build/typst/fixtures/fonts.txt; the fixture report
#       (CJK, Arabic, Hindi and more, emoji, a table, code and a local image,
#       through the vendored cmarker with raw-typst off) must render to a
#       PDF/UA-1 PDF, and to PNG pages, which land in $OUT_DIR when it is set
#       so a person can look at them; and an @preview import must fail with
#       "package downloads are disabled". The import is run once more under
#       strace, in a helper container (our alpine mirror with strace and
#       file, which needs network to build), and fails on any network system
#       call; `file` there must call the binary static. PLATFORM asks for, and
#       checks, one architecture.
#   scripts/check.sh --clamav-db <dir> <files-ref>
#       the same clamscan check with a real signature database: the
#       databases freshclam wrote to <dir> (the clamav-db workflow's), read
#       by the files image <files-ref> with no network. It fails unless the
#       EICAR file and its zip are found and every fixture is clean, so a
#       bundle that finds nothing, or flags our own fixtures, is never
#       published.
#
# Needs bash, awk, shellcheck, and python3 with PyYAML; --unsafe-image,
# --files-image and --clamav-db need a container runtime instead (--files-image one that takes
# docker's run flags for the decode container's hardening).
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
	shellcheck scripts/*.sh build/agentry-files/tika-app build/typst/fetch.sh || bad=1
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

# filesArgv <decoder> <fixture> sets argv to the decoder's command line exactly
# as the runner's decode role builds it (agentry-cli runnerimage/decode:
# absolute paths, fixed flags, the document's path the only variable), with
# the text written under /out. It fails for a decoder the image does not hold.
filesArgv() {
	case "$1" in
	pandoc) argv=(/usr/bin/pandoc --sandbox --to=plain --wrap=none --output=/out/text.txt "/in/$2") ;;
	pdftotext) argv=(/usr/bin/pdftotext -layout -enc UTF-8 -q "/in/$2" /out/text.txt) ;;
	tika-text) argv=(/usr/bin/tika-app --text "/in/$2") ;;
	tika-xml) argv=(/usr/bin/tika-app --xml "/in/$2") ;;
	tika-detect) argv=(/usr/bin/tika-app --detect "/in/$2") ;;
	tesseract) argv=(/usr/bin/tesseract "/in/$2" /out/text -l eng) ;;
	*) return 1 ;;
	esac
}

# checkFiles holds the files image's fixture list to the fixtures: each row
# names a fixture that exists, a decoder the image holds and a phrase, and
# each fixture has a row.
checkFiles() {
	local bad=0 f name tool phrase argv
	while IFS=$'\t' read -r name tool phrase; do
		case "$name" in '' | \#*) continue ;; esac
		if [ ! -f "$FILES_CTX/fixtures/$name" ]; then
			echo "$FILES_CTX/fixtures/expect.tsv: no fixture $name"
			bad=1
		fi
		if ! filesArgv "$tool" "$name"; then
			echo "$FILES_CTX/fixtures/expect.tsv: $name: unknown decoder ${tool:-(none)}"
			bad=1
		fi
		if [ -z "$phrase" ]; then
			echo "$FILES_CTX/fixtures/expect.tsv: $name: no phrase, so any text would pass"
			bad=1
		fi
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

# filesImage decodes every fixture inside the image the way the CLI's decode
# container runs a decoder (agentry-cli pkg/runner/decode Run and
# runnerimage/decode): the invoking user's uid, no network, every capability
# dropped, no new privileges, a read-only root, a 512 MiB /tmp, the fixtures
# read-only, its environment, and the decoder run directly, not under a
# shell. One difference: the binds are not relabelled for SELinux (the CLI
# relabels directories it made; these are the checkout's own), so the check
# turns labelling off for its container instead. It also fails on any
# setuid or setgid file in the image.
filesImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" name tool phrase argv out want arch bad=0 n=0 archive listing
	checkFiles || return 1
	# Local callers set TMPDIR under ~/scratch (CLAUDE.md).
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--user "$(id -u):$(id -g)" --tmpfs /tmp:size=512m --pids-limit 256 --memory 2g
		--env PATH=/usr/bin:/bin --env HOME=/tmp --env OMP_THREAD_LIMIT=1 --env LC_ALL=C.UTF-8
		-v "$PWD/$FILES_CTX/fixtures:/in:ro" -v "$out:/out")
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	if [ -n "${PLATFORM:-}" ]; then
		want="${PLATFORM##*/}"
		arch=$("${run[@]}" --entrypoint /bin/uname "$ref" -m)
		case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi
	for archive in zip tar 7z rar; do
		if listing=$("${run[@]}" -v "$PWD/$FILES_CTX/archives:/archives:ro" --entrypoint /usr/bin/bsdtar "$ref" -tf "/archives/sample.$archive") && [ -n "$listing" ]; then
			echo "ok   bsdtar lists $archive"
		else
			echo "FAIL bsdtar could not list $archive"
			bad=1
		fi
	done
	echo "packages:"
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/files/packages | sed 's/^/  /'
	mkdir "$out/clamav"
	clamCheckDB "$out/clamav"
	clamScan "$ref" "$out/clamav" || bad=1
	# The scan runs as root (the image's owner, still with no capability) so
	# no directory is unreadable to it, and a scan that could not finish fails.
	local suid f
	if ! suid=$("${run[@]}" --user 0:0 --entrypoint /usr/bin/find "$ref" / -xdev -type f -perm /6000); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi
	while IFS=$'\t' read -r name tool phrase; do
		case "$name" in '' | \#*) continue ;; esac
		n=$((n + 1))
		filesArgv "$tool" "$name" || return 1
		rm -f "$out"/text.txt "$out"/err
		if "${run[@]}" --entrypoint "${argv[0]}" "$ref" "${argv[@]:1}" >"$out/stdout" 2>"$out/err"; then
			case "$tool" in tika-*) cp "$out/stdout" "$out/text.txt" ;; esac
			if grep -qF -- "$phrase" "$out/text.txt" 2>/dev/null; then
				echo "ok   $name ($tool)"
			else
				echo "FAIL $name ($tool): decoded, but \"$phrase\" is not in the text"
				bad=1
			fi
		else
			echo "FAIL $name ($tool): the decoder failed:"
			sed 's/^/     /' "$out/err" | tail -5
			bad=1
		fi
	done <"$FILES_CTX/fixtures/expect.tsv"
	[ "$n" -gt 0 ] || {
		echo "FAIL no fixtures"
		bad=1
	}
	return "$bad"
}

# eicar writes the EICAR anti-virus test file, assembled from two halves so
# this script is not itself the test file to a scanner.
eicar() {
	# shellcheck disable=SC2016 # the test file's own $ characters
	printf '%s%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STAN' 'DARD-ANTIVIRUS-TEST-FILE!$H+H*' >"$1"
}

# clamScan runs clamscan inside the files image over the EICAR file, a zip of
# it and every fixture, with the argv agentry-cli's decode role uses
# (runnerimage/decode, clamscanArgv: both bounds 256M, half the decode's
# 512 MiB /tmp, since clamscan inflates what it extracts there up to the file
# bound) and the decode container's hardening,
# against the signature database in $2. It fails unless both EICAR files are
# found, every fixture is clean, and clamscan exits 1 (something found).
clamScan() {
	local ref="$1" db="$2" runtime="${CONTAINER:-docker}" scan f name line code bad=0
	scan=$(mktemp -d)
	eicar "$scan/eicar.com"
	python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").write(sys.argv[2], "eicar.com")' "$scan/eicar.zip" "$scan/eicar.com"
	cp "$FILES_CTX"/fixtures/* "$scan/"
	rm -f "$scan/expect.tsv"
	chmod -R a+rX "$scan"
	for f in "$scan"/*; do echo "/scan/${f##*/}"; done >"$scan.list"
	mv "$scan.list" "$scan/list"
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--user "$(id -u):$(id -g)" --tmpfs /tmp:size=512m --pids-limit 256 --memory 2g
		--env PATH=/usr/bin:/bin --env HOME=/tmp --env LC_ALL=C.UTF-8
		-v "$db:/clamav:ro" -v "$scan:/scan:ro")
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	echo "clamscan: $("${run[@]}" --entrypoint /usr/bin/clamscan "$ref" --version --database=/clamav)"
	code=0
	"${run[@]}" --entrypoint /usr/bin/clamscan "$ref" --database=/clamav --tempdir=/tmp \
		--no-summary --stdout --detect-pua=no --alert-exceeds-max=yes \
		--max-filesize=256M --max-scansize=256M --file-list=/scan/list >"$scan.out" 2>"$scan.err" || code=$?
	for f in "$scan"/*; do
		name="${f##*/}"
		[ "$name" = list ] && continue
		line=$({ grep -F -- "/scan/$name: " "$scan.out" || true; } | head -1)
		case "$name:${line##*: }" in
		eicar.com:*" FOUND" | eicar.zip:*" FOUND") echo "ok   clamscan finds $name (${line##*: })" ;;
		eicar.*) echo "FAIL clamscan did not find $name: ${line:-no line}" && bad=1 ;;
		*:OK) echo "ok   clamscan passes $name" ;;
		*) echo "FAIL clamscan on fixture $name: ${line:-no line}" && bad=1 ;;
		esac
	done
	if [ "$code" -ne 1 ]; then
		echo "FAIL clamscan exited $code, not 1 (found):"
		sed 's/^/     /' "$scan.err" | tail -5
		bad=1
	fi
	rm -rf "$scan" "$scan.out" "$scan.err"
	return "$bad"
}

# clamCheckDB is the files image's own ClamAV check: a database of one
# signature, the EICAR file's MD5 and size (ClamAV's .hdb format), so the
# scanner is proven with no download.
clamCheckDB() {
	local db="$1" sum
	eicar "$db/eicar"
	sum=$(md5sum "$db/eicar" | cut -d' ' -f1)
	printf '%s:%s:Agentry.Check.EICAR\n' "$sum" "$(wc -c <"$db/eicar" | tr -d ' ')" >"$db/check.hdb"
	rm -f "$db/eicar"
	chmod -R a+rX "$db"
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

TYPST_CTX=build/typst

# checkTypst holds the Typst image's inputs to their rules: every fetched file
# pinned to a commit and a SHA-256 with a licence, the downloader patch
# present and named in source.env, and a font list to check the image by.
checkTypst() {
	local bad=0 n=0 dest url sha licence extra
	while IFS=$'\t' read -r dest url sha licence extra; do
		case "$dest" in '' | \#*) continue ;; esac
		n=$((n + 1))
		if [ -z "$licence" ] || [ -n "${extra:-}" ]; then
			echo "$TYPST_CTX/fetch.tsv: $dest: want 4 tab-separated fields (path, url, sha256, licence)"
			bad=1
			continue
		fi
		case "$dest" in
		fonts/* | licenses/fonts/* | typst-packages/*) ;;
		*)
			echo "$TYPST_CTX/fetch.tsv: $dest: not under fonts/, licenses/fonts/ or typst-packages/"
			bad=1
			;;
		esac
		if ! [[ "$url" =~ ^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/ ]]; then
			echo "$TYPST_CTX/fetch.tsv: $dest: the URL names no pinned commit: $url"
			bad=1
		fi
		if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
			echo "$TYPST_CTX/fetch.tsv: $dest: no SHA-256: $sha"
			bad=1
		fi
		case "$licence" in
		OFL-1.1 | MIT | Apache-2.0) ;;
		*)
			echo "$TYPST_CTX/fetch.tsv: $dest: unknown licence $licence"
			bad=1
			;;
		esac
	done <"$TYPST_CTX/fetch.tsv"
	[ "$n" -gt 0 ] || {
		echo "$TYPST_CTX/fetch.tsv: no rows"
		bad=1
	}
	dest=$(awk -F'\t' '!/^#/ && NF { print $1 }' "$TYPST_CTX/fetch.tsv" | sort | uniq -d)
	if [ -n "$dest" ]; then
		echo "$TYPST_CTX/fetch.tsv: a path twice: $dest"
		bad=1
	fi
	if [ ! -s "$TYPST_CTX/disable-package-downloads.patch" ]; then
		echo "$TYPST_CTX/disable-package-downloads.patch: missing or empty"
		bad=1
	elif ! grep -q 'disable-package-downloads\.patch' "$TYPST_CTX/source.env"; then
		echo "$TYPST_CTX/source.env: does not name disable-package-downloads.patch"
		bad=1
	fi
	if ! grep -qv '^#' "$TYPST_CTX/fixtures/fonts.txt"; then
		echo "$TYPST_CTX/fixtures/fonts.txt: no font family"
		bad=1
	fi
	return "$bad"
}

# typstImage runs a built agentry-typst the way the runner's export_pdf will
# (plan scratch-and-pdf-reports §5: no network, the invoking uid, every
# capability dropped, a read-only root, a fixed argv with only the bundled
# fonts and packages), over build/typst/fixtures/.
typstImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out fam got bad=0 rc helper want
	checkTypst || return 1
	# Local callers set TMPDIR under ~/scratch (CLAUDE.md).
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	chmod 777 "$out"
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--user "$(id -u):$(id -g)" --tmpfs /tmp:size=256m --pids-limit 256 --memory 1g
		-v "$PWD/$TYPST_CTX/fixtures:/in:ro" -v "$out:/out")
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	local typst=(--ignore-system-fonts --font-path /fonts --package-path /typst-packages)

	echo "version: $("${run[@]}" "$ref" --version)"
	got=$("${run[@]}" "$ref" fonts "${typst[@]:0:3}")
	while IFS= read -r fam; do
		case "$fam" in '' | \#*) continue ;; esac
		if grep -qxF -- "$fam" <<<"$got"; then
			echo "ok   font family $fam"
		else
			echo "FAIL font family $fam is not in /fonts"
			bad=1
		fi
	done <"$TYPST_CTX/fixtures/fonts.txt"

	if "${run[@]}" "$ref" compile --root /in "${typst[@]}" --pdf-standard ua-1 \
		/in/report.typ /out/report.pdf 2>"$out/err"; then
		if [ "$(head -c 5 "$out/report.pdf")" = "%PDF-" ] && python3 - "$out/report.pdf" <<'EOF'; then
import re, sys, zlib
data = open(sys.argv[1], "rb").read()
# Look in every stream too: the catalog and the XMP may be compressed.
text = [data]
for m in re.finditer(rb"stream\r?\n", data):
    try:
        text.append(zlib.decompressobj().decompress(data[m.end():m.end() + 4000000]))
    except zlib.error:
        pass
blob = b"\n".join(text)
need = {b"/StructTreeRoot": "a structure tree", b"/MarkInfo": "MarkInfo",
        b"pdfuaid:part": "the PDF/UA identification"}
missing = [v for k, v in need.items() if k not in blob]
if missing:
    print("     the PDF has no " + ", no ".join(missing))
    sys.exit(1)
EOF
			echo "ok   the sample renders to a tagged PDF/UA-1 PDF ($(wc -c <"$out/report.pdf" | tr -d ' ') bytes)"
		else
			echo "FAIL the sample's PDF is not a tagged PDF/UA-1 PDF"
			bad=1
		fi
	else
		echo "FAIL the sample did not render:"
		sed 's/^/     /' "$out/err" | tail -15
		bad=1
	fi
	if "${run[@]}" "$ref" compile --root /in "${typst[@]}" --format png --ppi 96 \
		/in/report.typ '/out/report-{0p}.png' 2>"$out/err" && ls "$out"/report-*.png >/dev/null 2>&1; then
		echo "ok   the sample renders to $(find "$out" -name 'report-*.png' | wc -l | tr -d ' ') PNG pages"
	else
		echo "FAIL the sample did not render to PNG:"
		sed 's/^/     /' "$out/err" | tail -15
		bad=1
	fi

	rc=0
	"${run[@]}" "$ref" compile --root /in "${typst[@]}" /in/import.typ /out/import.pdf >"$out/import.err" 2>&1 || rc=$?
	if [ "$rc" -ne 0 ] && grep -qF "package downloads are disabled" "$out/import.err"; then
		echo "ok   an @preview import fails: $(grep -m1 -F 'package downloads are disabled' "$out/import.err")"
	else
		echo "FAIL an @preview import did not fail with \"package downloads are disabled\" (exit $rc):"
		sed 's/^/     /' "$out/import.err" | tail -8
		bad=1
	fi

	# The same import under strace: not one network system call, so the
	# refusal is the binary's own and no network block is needed for it.
	local alpine
	alpine=$(awk -F'\t' '$1 == "agentry-alpine" && $2 == "alpine:3.22" { print "ghcr.io/blaktron/agentry-alpine:3.22@" $3 }' "$MANIFEST")
	helper="local/agentry-typst-check:$$"
	# shellcheck disable=SC2016 # ${TYPST} and ${ALPINE} are the Dockerfile's
	if printf 'ARG TYPST\nARG ALPINE\nFROM ${TYPST} AS typst\nFROM ${ALPINE}\nRUN apk add --no-cache strace file\nCOPY --from=typst /typst /typst\n' |
		"$runtime" build -q ${PLATFORM:+--platform "$PLATFORM"} --build-arg TYPST="$ref" --build-arg ALPINE="$alpine" -t "$helper" - >/dev/null; then
		want=""
		case "${PLATFORM:-}" in
		*/amd64) want="x86-64" ;;
		*/arm64) want="aarch64" ;;
		esac
		got=$("$runtime" run --rm --network none "$helper" file -b /typst)
		echo "     file: $got"
		if [[ "$got" == *"static"* ]] && [[ "$got" != *"dynamically"* ]] && [[ -z "$want" || "$got" == *"$want"* ]]; then
			echo "ok   /typst is a static ${want:-binary}"
		else
			echo "FAIL /typst is not a static ${want:-binary}"
			bad=1
		fi
		"$runtime" run --rm --network none --cap-add SYS_PTRACE --security-opt label=disable \
			-v "$PWD/$TYPST_CTX/fixtures:/in:ro" "$helper" sh -c \
			'strace -f -qq -e trace=%network,execve -o /tmp/trace /typst compile --root /in --ignore-system-fonts /in/import.typ /tmp/x.pdf >/dev/null 2>&1; cat /tmp/trace' >"$out/trace" || true
		# execve is traced too, so an empty trace (strace not running) cannot
		# pass for a clean one.
		if ! grep -q 'execve("/typst"' "$out/trace"; then
			echo "FAIL strace did not trace the import:"
			sed 's/^/     /' "$out/trace" | head -8
			bad=1
		elif grep -v 'execve(' "$out/trace" | grep -q .; then
			echo "FAIL the @preview import made network system calls:"
			grep -v 'execve(' "$out/trace" | sed 's/^/     /' | head -8
			bad=1
		else
			echo "ok   the @preview import made no network system call (strace -e trace=%network)"
		fi
		"$runtime" rmi -f "$helper" >/dev/null 2>&1 || true
	else
		echo "FAIL could not build the strace helper from $alpine"
		bad=1
	fi

	if [ -n "${OUT_DIR:-}" ]; then
		mkdir -p "$OUT_DIR"
		cp "$out"/report.pdf "$out"/report-*.png "$OUT_DIR"/ 2>/dev/null || true
		echo "     the PDF and the PNG pages are in $OUT_DIR"
	fi
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkScripts checkWorkflows checkBases checkUnsafe checkFiles checkTypst; do
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
decoder checkFiles
unlisted checkFiles
phrase checkFiles
fetchsha checkTypst
fetchpin checkTypst
patch checkTypst
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
	decoder) sed -i 's/^policy.docx\tpandoc\t/policy.docx\tlibreoffice\t/' build/agentry-files/fixtures/expect.tsv ;;
	unlisted) cp build/agentry-files/fixtures/memo.rtf build/agentry-files/fixtures/unlisted.rtf ;;
	phrase) sed -i 's/^memo.rtf\tpandoc\t.*/memo.rtf\tpandoc\t/' build/agentry-files/fixtures/expect.tsv ;;
	fetchsha) sed -i '0,/\t[0-9a-f]\{64\}\t/s//\tlatest\t/' build/typst/fetch.tsv ;;
	fetchpin) sed -i '0,/\/[0-9a-f]\{40\}\//s//\/main\//' build/typst/fetch.tsv ;;
	patch) rm build/typst/disable-package-downloads.patch ;;
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
--typst-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --typst-image <ref>" >&2
		exit 2
	}
	typstImage "$2"
	;;
--clamav-db)
	if [ $# -ne 3 ] || [ ! -d "$2" ]; then
		echo "usage: scripts/check.sh --clamav-db <dir> <files-ref>" >&2
		exit 2
	fi
	clamScan "$3" "$(cd "$2" && pwd)"
	;;
'') runAll ;;
*)
	echo "usage: scripts/check.sh [--self-test | --unsafe-image <ref> | --files-image <ref> | --typst-image <ref> | --clamav-db <dir> <files-ref>]" >&2
	exit 2
	;;
esac
