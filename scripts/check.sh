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
#   - the Typst image's fetch list has a row that is not four fields, lies
#     outside fonts/, licenses/fonts/ and typst-packages/, names no pinned
#     commit, has no SHA-256 or no known licence, or repeats a path; its
#     patch is missing, empty, not applied by its Dockerfile or not named in
#     source.env; its font list names no family, or no report design's
#     family (one not named Noto); or families.typ is missing (build/typst).
#   - the Codex image's source.env does not pin a release version, its tag,
#     a commit and a SHA-256 for each architecture's tarball and for LICENSE
#     and NOTICE; verify.sh does not pin OpenAI's release workflow, GitHub's
#     issuer and the commit; fetch.sh does not verify the binary and run the
#     three negative controls; or the Dockerfile does not run fetch.sh
#     (build/agentry-codex).
#   - the host link image's PACKAGES names anything but OpenSSH client
#     packages, or the setuid openssh-keysign, or its Dockerfile does not run
#     as uid 10001 (build/agentry-hostlink).
#
# It pulls nothing and reads no credential, except in --unsafe-image,
# --files-image, --typst-image, --codex-image and --hostlink-image mode,
# which run the image they name.
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
#       PDF/UA-1 PDF, and to PNG pages; families.typ, a block in each report
#       design's family (every family of fonts.txt not named Noto; plan
#       report-designs D13, agentry-dockerimages#58) with Chinese, Arabic and
#       Hindi behind it, must render to a PDF/UA-1 PDF with no unknown-family
#       warning that embeds every one of those families and the three Noto
#       fallbacks, and to PNG pages; the PDFs and PNG pages land in $OUT_DIR
#       when it is set so a person can look at them; and an @preview import
#       must fail with
#       "package downloads are disabled". The import is run once more under
#       strace, in a helper container (our alpine mirror with strace and
#       file, which needs network to build), and fails on any network system
#       call; `file` there must call the binary static. PLATFORM asks for, and
#       checks, one architecture.
#   scripts/check.sh --codex-image <ref>
#       run a built agentry-codex hardened, as the CLI runs a harness (no
#       network, every capability dropped, no new privileges, a read-only
#       root, the image's own user, CODEX_HOME on a tmpfs;
#       agentry-dockerimages#53), and fail unless the user is not root,
#       `codex --version` prints source.env's version, Codex writes to
#       CODEX_HOME, LICENSE, NOTICE, the release record and the signature
#       bundle are present, no file is setuid or setgid, the binary is static,
#       its SHA-256 is the release record's, and it verifies again against
#       OpenAI's signature with build/agentry-codex/verify.sh. PLATFORM asks
#       for, and checks, one architecture.
#   scripts/check.sh --hostlink-image <ref>
#       run a built agentry-hostlink hardened, as the runner runs a host link
#       (every capability dropped, no new privileges, a read-only root, the
#       image's own user, the credentials bound read-only; plan
#       runtime-hosts.md D5, agentry-dockerimages#71), against a throwaway
#       OpenSSH server (our alpine mirror with openssh-server, which needs
#       network to build) on an internal network with no route out. It fails
#       unless the user is uid 10001, the package record names each of
#       PACKAGES, apk's world is the base's plus PACKAGES, no file is setuid
#       or setgid, ssh-keyscan reads the server's key (on port 22 and 2222),
#       ssh logs in with a key, with a passphrase-protected key and with a
#       password through SSH_ASKPASS, runs a command, opens a remote
#       pseudo-terminal and drives a login shell over stdin, checks a key
#       under HostKeyAlias on port 2222, sftp copies a file there and back, a changed
#       and an unknown host key are each refused before any command runs,
#       and ssh runs as the invoking uid given a passwd line for it. PLATFORM
#       asks for, and checks, one architecture.
#   scripts/check.sh --clamav-db <dir> <files-ref>
#       the same clamscan check with a real signature database: the
#       databases freshclam wrote to <dir> (the clamav-db workflow's), read
#       by the files image <files-ref> with no network. It fails unless the
#       EICAR file and its zip are found and every fixture is clean, so a
#       bundle that finds nothing, or flags our own fixtures, is never
#       published.
#
# Needs bash, awk, shellcheck, and python3 with PyYAML; --unsafe-image,
# --files-image, --typst-image, --hostlink-image and --clamav-db need a
# container runtime instead (--files-image, --typst-image and
# --hostlink-image one that takes docker's run flags for the hardening),
# --typst-image also python3 and network to build its strace helper,
# --hostlink-image network to build its OpenSSH server, and --codex-image
# also file, cosign and network to reach Sigstore.
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
	shellcheck scripts/*.sh build/agentry-files/tika-app build/typst/fetch.sh build/agentry-codex/fetch.sh build/agentry-codex/verify.sh || bad=1
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
	elif ! grep -q '^RUN patch .*disable-package-downloads\.patch' "$TYPST_CTX/Dockerfile"; then
		echo "$TYPST_CTX/Dockerfile: does not apply disable-package-downloads.patch"
		bad=1
	elif ! grep -q 'disable-package-downloads\.patch' "$TYPST_CTX/source.env"; then
		echo "$TYPST_CTX/source.env: does not name disable-package-downloads.patch"
		bad=1
	fi
	if ! grep -qvE '^(#|[[:space:]]*$)' "$TYPST_CTX/fixtures/fonts.txt"; then
		echo "$TYPST_CTX/fixtures/fonts.txt: no font family"
		bad=1
	elif [ -z "$(designFamilies)" ]; then
		echo "$TYPST_CTX/fixtures/fonts.txt: no report design family (one not named Noto)"
		bad=1
	fi
	if [ ! -s "$TYPST_CTX/fixtures/families.typ" ]; then
		echo "$TYPST_CTX/fixtures/families.typ: missing or empty"
		bad=1
	fi
	return "$bad"
}

# designFamilies prints the report designs' families, one a line: every family
# of fixtures/fonts.txt whose name does not start with "Noto" (plan
# report-designs D13).
designFamilies() {
	grep -vE '^(#|[[:space:]]*$|Noto )' "$TYPST_CTX/fixtures/fonts.txt" || true
}

# typstImage runs a built agentry-typst the way the runner's export_pdf will
# (plan scratch-and-pdf-reports §5: no network, the invoking uid, every
# capability dropped, a read-only root, a fixed argv with only the bundled
# fonts and packages), over build/typst/fixtures/. Then it runs the import
# probe and the report again under strace, in a helper holding the image's
# files, so "no network call" is observed rather than only blocked.
typstImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out fam got bad=0 rc want alpine
	local helper="local/agentry-typst-check:$$"
	checkTypst || return 1
	# Local callers set TMPDIR under ~/scratch (CLAUDE.md).
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out and helper are local
	trap "rm -rf '$out'; '$runtime' rmi -f '$helper' >/dev/null 2>&1 || true" EXIT
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--user "$(id -u):$(id -g)" --tmpfs /tmp:size=256m --pids-limit 256 --memory 1g
		-v "$PWD/$TYPST_CTX/fixtures:/in:ro" -v "$out:/out")
	[ -n "${PLATFORM:-}" ] && run+=(--platform "$PLATFORM")
	local fonts=(--ignore-system-fonts --font-path /fonts)
	local typst=("${fonts[@]}" --package-path /typst-packages)

	echo "version: $("${run[@]}" "$ref" --version)"
	got=$("${run[@]}" "$ref" fonts "${fonts[@]}")
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

	# Each report design's family, with Noto behind it for Chinese, Arabic and
	# Hindi (plan report-designs D3, D13). A family the image lacks is only a
	# warning to Typst, which then sets the text in the next family, so the
	# warning fails the check, and so does a PDF that does not embed the family
	# (by its PostScript name, the family's name without spaces; a variable
	# font's is its default instance's, e.g. Montserrat-Thin, which is only
	# the name: Typst embeds the instanced outlines).
	local families
	families=$(designFamilies | paste -sd'|' -)
	if "${run[@]}" "$ref" compile --root /in "${typst[@]}" --pdf-standard ua-1 \
		--input "families=$families" /in/families.typ /out/families.pdf 2>"$out/err" &&
		! grep -qiF "unknown font family" "$out/err"; then
		if python3 - "$out/families.pdf" "$families" <<'EOF'; then
import re, sys, zlib
data = open(sys.argv[1], "rb").read()
text = [data]
for m in re.finditer(rb"stream\r?\n", data):
    try:
        text.append(zlib.decompressobj().decompress(data[m.end():m.end() + 4000000]))
    except zlib.error:
        pass
blob = b"\n".join(text)
embedded = {n.decode("latin-1") for n in re.findall(rb"/BaseFont\s*/(?:[A-Z]{6}\+)?([^\s/<>\[\]()]+)", blob)}
want = [f for f in sys.argv[2].split("|") if f] + ["Noto Sans SC", "Noto Sans Arabic", "Noto Sans Devanagari"]
missing = [f for f in want if not any(e.startswith(f.replace(" ", "")) for e in embedded)]
untagged = [k.decode() for k in (b"/StructTreeRoot", b"/MarkInfo", b"pdfuaid:part") if k not in blob]
if missing or untagged:
    if missing:
        print("     the families PDF embeds no " + ", no ".join(missing))
    if untagged:
        print("     the families PDF has no " + ", no ".join(untagged))
    sys.exit(1)
print("     embedded: %d families and the Noto fallbacks for Chinese, Arabic and Hindi" % (len(want) - 3))
EOF
			echo "ok   families.typ renders in every report design family, with Noto behind each, to a tagged PDF/UA-1 PDF"
		else
			echo "FAIL the families PDF does not embed every family, or is not tagged"
			bad=1
		fi
	else
		echo "FAIL families.typ did not render, or named a family the image lacks:"
		sed 's/^/     /' "$out/err" | tail -15
		bad=1
	fi
	if "${run[@]}" "$ref" compile --root /in "${typst[@]}" --format png --ppi 96 \
		--input "families=$families" /in/families.typ '/out/families-{0p}.png' 2>"$out/err" &&
		ls "$out"/families-*.png >/dev/null 2>&1; then
		echo "ok   families.typ renders to $(find "$out" -name 'families-*.png' | wc -l | tr -d ' ') PNG pages"
	else
		echo "FAIL families.typ did not render to PNG:"
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

	# Under strace: the image's files in a helper from our alpine mirror with
	# strace and file. Building it needs network; the traced runs have none.
	alpine=$(awk -F'\t' '$1 == "agentry-alpine" && $2 == "alpine:3.22" { print $3 }' "$MANIFEST")
	alpine="${REGISTRY:-ghcr.io/blaktron}/agentry-alpine:3.22@$alpine"
	# shellcheck disable=SC2016 # ${TYPST} and ${ALPINE} are the Dockerfile's
	if ! printf 'ARG TYPST\nARG ALPINE\nFROM ${TYPST} AS typst\nFROM ${ALPINE}\nRUN apk add --no-cache strace file\nCOPY --from=typst /typst /typst\nCOPY --from=typst /fonts /fonts\nCOPY --from=typst /typst-packages /typst-packages\n' |
		"$runtime" build -q ${PLATFORM:+--platform "$PLATFORM"} --build-arg TYPST="$ref" --build-arg ALPINE="$alpine" -t "$helper" - >/dev/null; then
		echo "FAIL could not build the strace helper from $alpine"
		return 1
	fi
	want=""
	case "${PLATFORM:-}" in
	*/amd64) want="x86-64" ;;
	*/arm64) want="aarch64" ;;
	esac
	got=$("$runtime" run --rm --network none "$helper" file -b /typst) || got=""
	echo "     file: $got"
	if [[ "$got" == *"static"* ]] && [[ "$got" != *"dynamically"* ]] && [[ -z "$want" || "$got" == *"$want"* ]]; then
		echo "ok   /typst is a static ${want:-binary}"
	else
		echo "FAIL /typst is not a static ${want:-binary}"
		bad=1
	fi
	# Each traced run writes the trace, then typst's exit code and output. The
	# trace holds execve too, so an empty trace (strace not running) cannot
	# pass for a clean one.
	local name doc trace
	for name in import report; do
		doc="/in/$name.typ"
		"$runtime" run --rm --network none --cap-add SYS_PTRACE --security-opt label=disable \
			-v "$PWD/$TYPST_CTX/fixtures:/in:ro" "$helper" sh -c \
			'strace -f -qq -e trace=%network,execve -o /tmp/trace /typst compile --root /in "$@" >/tmp/log 2>&1; echo "exit $?" >>/tmp/log; cat /tmp/trace; echo "--- typst"; cat /tmp/log' \
			sh "${typst[@]}" "$doc" /tmp/out.pdf >"$out/trace" 2>&1 || true
		trace=$(sed '/^--- typst$/,$d' "$out/trace")
		if ! grep -q 'execve("/typst"' <<<"$trace"; then
			echo "FAIL strace did not trace the $name run:"
			sed 's/^/     /' "$out/trace" | head -8
			bad=1
		elif grep -v 'execve(' <<<"$trace" | grep -q .; then
			echo "FAIL the $name run made network system calls:"
			grep -v 'execve(' <<<"$trace" | sed 's/^/     /' | head -8
			bad=1
		elif [ "$name" = import ] && ! grep -qF "package downloads are disabled" "$out/trace"; then
			echo "FAIL the traced import did not reach the refusing downloader:"
			sed -n '/^--- typst$/,$p' "$out/trace" | sed 's/^/     /' | tail -6
			bad=1
		elif [ "$name" = report ] && ! grep -qx 'exit 0' "$out/trace"; then
			echo "FAIL the traced report did not render:"
			sed -n '/^--- typst$/,$p' "$out/trace" | sed 's/^/     /' | tail -6
			bad=1
		else
			echo "ok   the traced $name run made no network system call (strace -e trace=%network)"
		fi
	done

	if [ -n "${OUT_DIR:-}" ]; then
		mkdir -p "$OUT_DIR"
		cp "$out"/report.pdf "$out"/report-*.png "$out"/families.pdf "$out"/families-*.png "$OUT_DIR"/ 2>/dev/null || true
		echo "     the PDF and the PNG pages are in $OUT_DIR"
	fi
	return "$bad"
}

CODEX_CTX=build/agentry-codex

# checkCodex holds the Codex image's context to its pins: source.env names a
# version, its tag, a commit and a SHA-256 for each architecture's tarball and
# for LICENSE and NOTICE; verify.sh pins OpenAI's release workflow and GitHub's
# issuer; fetch.sh verifies the binary and runs the three negative controls; and the
# Dockerfile runs fetch.sh (agentry-dockerimages#53). The greps match the
# scripts' own text, `$` and all.
# shellcheck disable=SC2016
checkCodex() {
	local bad=0 key val
	(
		# shellcheck source=/dev/null
		. "$CODEX_CTX/source.env"
		b=0
		[[ "${CODEX_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$CODEX_CTX/source.env: CODEX_VERSION is not a release version: ${CODEX_VERSION:-}"
			b=1
		}
		[ "${CODEX_TAG:-}" = "rust-v${CODEX_VERSION:-}" ] || {
			echo "$CODEX_CTX/source.env: CODEX_TAG ${CODEX_TAG:-} is not rust-v${CODEX_VERSION:-}"
			b=1
		}
		[[ "${CODEX_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
			echo "$CODEX_CTX/source.env: CODEX_COMMIT is not a commit: ${CODEX_COMMIT:-}"
			b=1
		}
		for key in CODEX_SHA256_AMD64 CODEX_SHA256_ARM64 CODEX_LICENSE_SHA256 CODEX_NOTICE_SHA256; do
			val="${!key:-}"
			[[ "$val" =~ ^[0-9a-f]{64}$ ]] || {
				echo "$CODEX_CTX/source.env: $key is not a SHA-256: $val"
				b=1
			}
		done
		[ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$CODEX_CTX/source.env: PLATFORMS is not linux/amd64,linux/arm64: ${PLATFORMS:-}"
			b=1
		}
		exit "$b"
	) || bad=1
	if ! grep -qF -- '--certificate-identity "https://github.com/openai/codex/.github/workflows/rust-release.yml@refs/tags/$tag"' "$CODEX_CTX/verify.sh" ||
		! grep -qF -- '--certificate-oidc-issuer https://token.actions.githubusercontent.com' "$CODEX_CTX/verify.sh" ||
		! grep -qF -- '--certificate-github-workflow-sha "$commit"' "$CODEX_CTX/verify.sh"; then
		echo "$CODEX_CTX/verify.sh: does not pin OpenAI's release workflow, GitHub's issuer and the commit"
		bad=1
	fi
	if [ "$(grep -c '^refuse "' "$CODEX_CTX/fetch.sh")" != 3 ] ||
		! grep -q '^sh "\$verify" "\$out/codex" "\$out/codex.sigstore" "\$CODEX_TAG" "\$CODEX_COMMIT"$' "$CODEX_CTX/fetch.sh"; then
		echo "$CODEX_CTX/fetch.sh: does not verify the binary and run the three negative controls"
		bad=1
	fi
	if ! grep -q '^RUN sh /agentry/fetch.sh ' "$CODEX_CTX/Dockerfile"; then
		echo "$CODEX_CTX/Dockerfile: does not run fetch.sh"
		bad=1
	fi
	return "$bad"
}

# codexImage runs a built agentry-codex the way the CLI's hardened agent
# container runs a harness (agentry-cli pkg/runner/engine hardening): no
# network, every capability dropped, no new privileges, a read-only root, the
# image's own user, a tmpfs on its home, which is CODEX_HOME. It fails unless that user is not
# root, `codex --version` prints source.env's version, Codex can write its
# CODEX_HOME there, LICENSE, NOTICE and the release record are in the image,
# no file is setuid or setgid, the binary is static, its SHA-256 is the
# release record's, and it verifies again, with cosign on this machine and
# the context's verify.sh, against the bundle the image carries. PLATFORM asks
# for, and checks, one architecture. Needs docker (or CONTAINER), file and
# cosign. The sh -c scripts expand inside the container.
# shellcheck disable=SC2016
codexImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out got want arch id sum bad=0
	command -v cosign >/dev/null || {
		echo "FAIL --codex-image needs cosign"
		return 1
	}
	# shellcheck source=/dev/null
	. "$CODEX_CTX/source.env"
	# Local callers set TMPDIR under ~/scratch (CLAUDE.md).
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /tmp:mode=1777 --tmpfs /home/codex:mode=1777
		--pids-limit 256 --memory 1g)
	if [ -n "${PLATFORM:-}" ]; then
		run+=(--platform "$PLATFORM")
		want="${PLATFORM##*/}"
		arch=$("${run[@]}" --entrypoint /bin/uname "$ref" -m)
		case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi
	id=$("${run[@]}" --entrypoint /usr/bin/id "$ref" -u)
	if [ "$id" = 0 ] || [ -z "$id" ]; then
		echo "FAIL the image runs as uid '${id}', not a user of its own"
		bad=1
	else
		echo "ok   runs as uid $id"
	fi
	got=$("${run[@]}" "$ref" --version 2>&1) || got="(failed) $got"
	if [ "$got" = "codex-cli $CODEX_VERSION" ]; then
		echo "ok   codex --version: $got, with no network and a read-only root"
	else
		echo "FAIL codex --version: $got (want codex-cli $CODEX_VERSION)"
		bad=1
	fi
	# Codex makes its helper links under CODEX_HOME at start (tmp/, absent
	# from a fresh tmpfs until it does) and reads its configuration there;
	# both must work on the tmpfs, with nothing needing the read-only root.
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'test "$CODEX_HOME" = /home/codex && codex features list >/dev/null && test -d "$CODEX_HOME/tmp"'; then
		echo "ok   CODEX_HOME is /home/codex, and Codex writes to it and reads its configuration on the tmpfs"
	else
		echo "FAIL Codex could not write to or read from CODEX_HOME on the tmpfs"
		bad=1
	fi
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'test -s /usr/share/licenses/codex/LICENSE && test -s /usr/share/licenses/codex/NOTICE && test -s /etc/agentry/codex/release && test -s /etc/agentry/codex/codex.sigstore'; then
		echo "ok   LICENSE, NOTICE, the release record and the signature bundle are in the image"
	else
		echo "FAIL LICENSE, NOTICE, the release record or the signature bundle is missing"
		bad=1
	fi
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
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/codex/release >"$out/release"
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/codex/codex.sigstore >"$out/codex.sigstore"
	"${run[@]}" --entrypoint /bin/cat "$ref" /usr/local/bin/codex >"$out/codex"
	echo "release:"
	sed 's/^/  /' "$out/release"
	if file "$out/codex" | grep -q 'static'; then
		echo "ok   the binary is static"
	else
		echo "FAIL the binary is not static: $(file -b "$out/codex")"
		bad=1
	fi
	sum=$(sha256sum "$out/codex" | cut -d' ' -f1)
	if grep -qx "binary_sha256=$sum" "$out/release" && grep -qx "version=$CODEX_VERSION" "$out/release"; then
		echo "ok   the binary's SHA-256 is the release record's ($sum)"
	else
		echo "FAIL the binary's SHA-256 $sum or the version is not the release record's"
		bad=1
	fi
	if sh "$CODEX_CTX/verify.sh" "$out/codex" "$out/codex.sigstore" "$CODEX_TAG" "$CODEX_COMMIT"; then
		echo "ok   the binary in the image verifies as openai/codex rust-release.yml at $CODEX_TAG ($CODEX_COMMIT)"
	else
		echo "FAIL the binary in the image does not verify against OpenAI's signature"
		bad=1
	fi
	return "$bad"
}

HOSTLINK_CTX=build/agentry-hostlink

# hostlinkPackages prints the Dockerfile's PACKAGES, one a line.
hostlinkPackages() {
	sed -n 's/^ARG PACKAGES="\(.*\)"$/\1/p' "$HOSTLINK_CTX/Dockerfile" | tr -s ' ' '\n' | sed '/^$/d'
}

# checkHostlink holds the host link image's context to its contract: the
# OpenSSH client's three packages and nothing else (never the setuid
# openssh-keysign, never a server), and a non-root user (plan runtime-hosts.md D5;
# agentry-dockerimages#71).
checkHostlink() {
	local bad=0 p n=0
	while IFS= read -r p; do
		n=$((n + 1))
		case "$p" in
		openssh-keysign)
			echo "$HOSTLINK_CTX/Dockerfile: PACKAGES installs openssh-keysign, the client's setuid helper"
			bad=1
			;;
		openssh-client-default | openssh-client-common | openssh-keygen) ;;
		*)
			echo "$HOSTLINK_CTX/Dockerfile: PACKAGES installs $p, which is not one of the OpenSSH client's three packages"
			bad=1
			;;
		esac
	done < <(hostlinkPackages)
	if [ "$n" -eq 0 ]; then
		echo "$HOSTLINK_CTX/Dockerfile: no ARG PACKAGES line"
		bad=1
	fi
	if ! grep -qx 'USER 10001:10001' "$HOSTLINK_CTX/Dockerfile"; then
		echo "$HOSTLINK_CTX/Dockerfile: does not run as uid 10001 (USER 10001:10001)"
		bad=1
	fi
	if ! grep -qx 'IMAGE_NAME=agentry-hostlink' "$HOSTLINK_CTX/source.env"; then
		echo "$HOSTLINK_CTX/source.env: IMAGE_NAME is not agentry-hostlink"
		bad=1
	fi
	return "$bad"
}

# hostlinkImage runs a built agentry-hostlink hardened, as the runner runs a
# host link (every capability dropped, no new privileges, a read-only root,
# the image's own user, the credentials bound read-only), against a
# throwaway OpenSSH server on an internal network with no route out. It
# fails unless the image holds PACKAGES and nothing more than the base and
# their dependencies, records their versions, has no setuid or setgid file,
# and its client does every thing the host link does: ssh-keyscan reads the
# server's key, ssh logs in with a key and with a password through
# SSH_ASKPASS, runs a command, opens a remote pseudo-terminal, sftp copies a
# file both ways, a changed or unknown host key is refused before any
# command runs, and ssh runs as another uid given a passwd line for it;
# with a passphrase-protected key, a login shell over stdin, and a second
# port whose key is checked under HostKeyAlias, as through the relay.
hostlinkImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" bad=0 want arch uid base p out
	checkHostlink || return 1
	local tag="$$-$RANDOM" dir net sshd helper
	net="agentry-check-hostlink-$tag"
	sshd="agentry-check-sshd-$tag"
	helper="agentry-check-sshd:$tag"
	# Local callers set TMPDIR under ~/scratch (CLAUDE.md).
	dir=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: these are local
	trap "$runtime rm -fv '$sshd' >/dev/null 2>&1; $runtime network rm '$net' >/dev/null 2>&1; $runtime image rm '$helper' >/dev/null 2>&1; rm -rf '$dir'" EXIT
	local plat=()
	[ -n "${PLATFORM:-}" ] && plat=(--platform "$PLATFORM")
	# shellcheck disable=SC2054 # the commas are the tmpfs mount's options
	local run=("$runtime" run --rm "${plat[@]}" --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /tmp:size=64m --tmpfs /home/hostlink:size=16m,uid=10001,gid=10001,mode=0700
		--pids-limit 64 --memory 256m)
	if [ -n "${PLATFORM:-}" ]; then
		want="${PLATFORM##*/}"
		arch=$("${run[@]}" --network none --entrypoint /bin/uname "$ref" -m)
		case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi

	uid=$("${run[@]}" --network none --entrypoint /usr/bin/id "$ref" -u)
	if [ "$uid" = 10001 ]; then
		echo "ok   runs as uid 10001, not root"
	else
		echo "FAIL runs as uid $uid, not 10001"
		bad=1
	fi

	# The record names each of PACKAGES at the version apk resolved, and
	# apk's world is the base's plus PACKAGES: everything else installed is
	# the base or one of their dependencies.
	echo "packages:"
	"${run[@]}" --network none --entrypoint /bin/cat "$ref" /etc/agentry/hostlink/packages >"$dir/packages"
	sed 's/^/  /' "$dir/packages"
	while IFS= read -r p; do
		if grep -Eq "^$p-[0-9][^ ]*-r[0-9]+\$" "$dir/packages"; then
			echo "ok   the record names $p"
		else
			echo "FAIL the record does not name $p at a version"
			bad=1
		fi
	done < <(hostlinkPackages)
	if [ "$(wc -l <"$dir/packages")" -ne "$(hostlinkPackages | wc -l)" ]; then
		echo "FAIL the record has $(wc -l <"$dir/packages") lines for $(hostlinkPackages | wc -l) packages"
		bad=1
	fi
	# The base as scripts/build.sh passes it (its ourRef): our mirror's tag
	# and the digest images.tsv pins.
	local upstream mirrored digest
	read -r upstream < <(awk -F'=' '$1 == "ALPINE_IMAGE" { print $2 }' "$HOSTLINK_CTX/bases.env") || {
		echo "FAIL $HOSTLINK_CTX/bases.env names no ALPINE_IMAGE"
		return 1
	}
	read -r mirrored digest < <(awk -F'\t' -v u="$upstream" '!/^[[:space:]]*#/ && $2 == u { print $1, $3; exit }' "$MANIFEST") || {
		echo "FAIL $MANIFEST has no row for $upstream"
		return 1
	}
	base="${REGISTRY:-ghcr.io/blaktron}/$mirrored:${upstream##*:}@$digest"
	{
		"$runtime" run --rm "${plat[@]}" --network none --entrypoint /bin/cat "$base" /etc/apk/world
		hostlinkPackages
	} | sort -u >"$dir/world.want"
	"${run[@]}" --network none --entrypoint /bin/cat "$ref" /etc/apk/world | sort -u >"$dir/world.got"
	if cmp -s "$dir/world.want" "$dir/world.got"; then
		echo "ok   apk's world is the base's ($base) and PACKAGES, nothing more"
	else
		echo "FAIL apk's world is not the base's and PACKAGES:"
		diff "$dir/world.want" "$dir/world.got" | sed 's/^/     /' || true
		bad=1
	fi

	# The scan runs as root (still with no capability) so no directory is
	# unreadable to it, and a scan that could not finish fails.
	local suid f
	if ! suid=$("${run[@]}" --network none --user 0:0 --entrypoint /usr/bin/find "$ref" / -xdev -type f -perm /6000); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi

	if out=$("${run[@]}" --network none --entrypoint /usr/bin/ssh "$ref" -V 2>&1) && [[ "$out" == OpenSSH_* ]]; then
		echo "ok   ssh -V: $out"
	else
		echo "FAIL ssh -V: $out"
		bad=1
	fi
	for p in sftp ssh-keyscan ssh-keygen; do
		if "${run[@]}" --network none --entrypoint /usr/bin/test "$ref" -x "/usr/bin/$p"; then
			echo "ok   /usr/bin/$p"
		else
			echo "FAIL no /usr/bin/$p"
			bad=1
		fi
	done

	# The server: our base mirror with OpenSSH's server, built here (it needs
	# network to build), on an internal network the host link alone joins.
	# Its keys and the client's are made fresh for this check.
	# The password is also the passphrase of the second client key.
	head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$dir/password"
	chmod 644 "$dir/password"
	printf 'FROM %s\nRUN apk add --no-cache openssh-server openssh-sftp-server openssh-keygen\n' "$base" |
		"$runtime" build -q "${plat[@]}" -t "$helper" - >/dev/null
	# shellcheck disable=SC2016 # expanded by the helper's shell
	"$runtime" run --rm "${plat[@]}" --network none --security-opt label=disable -v "$dir:/w" --entrypoint /bin/sh "$helper" -c '
		set -e
		ssh-keygen -q -t ed25519 -N "" -C check -f /w/id
		ssh-keygen -q -t ed25519 -N "" -C target -f /w/host_key
		ssh-keygen -q -t ed25519 -N "" -C other -f /w/other_key
		ssh-keygen -q -t ed25519 -N "$(cat /w/password)" -C locked -f /w/locked
		chown '"$(id -u):$(id -g)"' /w/id /w/id.pub /w/host_key /w/host_key.pub /w/other_key /w/other_key.pub /w/locked /w/locked.pub'
	# ssh holds a key file to 0600 only when the user running it owns it, so
	# the image's user reads a 0644 copy and the invoking uid its own 0600.
	# Everything here is made for this check and removed with it; the folder
	# is readable to the image's user, and so to others on this machine.
	cp "$dir/id" "$dir/id600"
	chmod 600 "$dir/id600"
	chmod 644 "$dir/id" "$dir/locked"
	chmod 755 "$dir"
	printf '#!/bin/sh\nexec cat /cfg/password\n' >"$dir/askpass"
	chmod 755 "$dir/askpass"
	printf 'target %s\n' "$(cut -d' ' -f1,2 "$dir/host_key.pub")" >"$dir/known_hosts"
	printf 'target %s\n' "$(cut -d' ' -f1,2 "$dir/other_key.pub")" >"$dir/changed_hosts"
	: >"$dir/empty_hosts"
	# The host link reaches a relay, not the host: the key is looked up under
	# the name the person gave (HostKeyAlias), whatever address and port ssh
	# dials.
	printf 'server.example %s\n' "$(cut -d' ' -f1,2 "$dir/host_key.pub")" >"$dir/alias_hosts"
	printf '[target]:2222 %s\n' "$(cut -d' ' -f1,2 "$dir/host_key.pub")" >"$dir/port_hosts"
	head -c 4096 /dev/urandom | od -An -tx1 >"$dir/payload"
	printf 'put /cfg/payload payload\nget payload /tmp/back\n' >"$dir/batch"
	printf 'check:x:%s:%s::/tmp:/sbin/nologin\n' "$(id -u)" "$(id -g)" >"$dir/passwd"
	chmod 644 "$dir/password" "$dir/payload" "$dir/batch" "$dir/passwd" "$dir"/*_hosts

	"$runtime" network create --internal "$net" >/dev/null
	# shellcheck disable=SC2016 # expanded by the server's shell
	"$runtime" run -d "${plat[@]}" --name "$sshd" --network "$net" --network-alias target \
		--security-opt label=disable -v "$dir:/w:ro" --entrypoint /bin/sh "$helper" -c '
		set -e
		adduser -D -s /bin/sh agent
		echo "agent:$(cat /w/password)" | chpasswd >/dev/null
		install -m 600 /w/host_key /etc/ssh/agentry_host_key
		install -d -o agent -m 700 /home/agent/.ssh
		cat /w/id.pub /w/locked.pub >/home/agent/.ssh/authorized_keys
		chown agent /home/agent/.ssh/authorized_keys
		chmod 600 /home/agent/.ssh/authorized_keys
		exec /usr/sbin/sshd -D -e -p 22 -p 2222 -h /etc/ssh/agentry_host_key -o PasswordAuthentication=yes -o KbdInteractiveAuthentication=no' >/dev/null

	# ssh keeps the first value it is given for an option, so each call
	# names its own key and its own known_hosts after these.
	local hl=("${run[@]}" --network "$net" -v "$dir:/cfg:ro")
	local opts=(-F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o GlobalKnownHostsFile=/dev/null
		-o StrictHostKeyChecking=yes -o ConnectTimeout=10)
	local key=(-i /cfg/id -o UserKnownHostsFile=/cfg/known_hosts)

	# ssh-keyscan reads the server's key: it must be the one made for it.
	local scanned="" _
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		scanned=$("${hl[@]}" --entrypoint /usr/bin/ssh-keyscan "$ref" -T 5 -t ed25519 target 2>/dev/null | grep -v '^#') && [ -n "$scanned" ] && break
		sleep 1
	done
	if [ "$scanned" = "$(cat "$dir/known_hosts")" ]; then
		echo "ok   ssh-keyscan reads the server's key ($(cut -d' ' -f2 <<<"$scanned"))"
	else
		echo "FAIL ssh-keyscan: got \"$scanned\""
		"$runtime" logs "$sshd" 2>&1 | tail -5 | sed 's/^/     /' || true
		bad=1
	fi

	if out=$("${hl[@]}" --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" "${key[@]}" agent@target 'echo hostlink-ok; id -un' 2>&1) &&
		[ "$out" = "$(printf 'hostlink-ok\nagent')" ]; then
		echo "ok   ssh logs in with a key and runs a command"
	else
		echo "FAIL ssh with a key: $out"
		bad=1
	fi

	# -tt's own "Connection to target closed." goes to stderr; the remote
	# terminal ends its lines with CR LF.
	if out=$("${hl[@]}" --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" "${key[@]}" -tt agent@target 'tty' 2>"$dir/tty.err") &&
		out="${out//$'\r'/}" && [[ "$out" == /dev/pts/* ]]; then
		echo "ok   ssh -tt opens a remote pseudo-terminal ($out)"
	else
		echo "FAIL ssh -tt: $out $(cat "$dir/tty.err")"
		bad=1
	fi

	if out=$("${hl[@]}" --entrypoint /bin/sh "$ref" -c \
		'sftp -q -b /cfg/batch "$@" agent@target >/dev/null && cmp /cfg/payload /tmp/back && echo copied' sh "${opts[@]}" "${key[@]}" 2>&1) &&
		[ "$out" = copied ]; then
		echo "ok   sftp copies a file to the host and back"
	else
		echo "FAIL sftp: $out"
		bad=1
	fi

	if out=$("${hl[@]}" --env SSH_ASKPASS=/cfg/askpass --env SSH_ASKPASS_REQUIRE=force --entrypoint /usr/bin/ssh "$ref" \
		-F /dev/null -o UserKnownHostsFile=/cfg/known_hosts -o GlobalKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no \
		-o NumberOfPasswordPrompts=1 -o ConnectTimeout=10 agent@target 'echo password-ok' 2>&1) &&
		[ "$out" = password-ok ]; then
		echo "ok   ssh logs in with a password through SSH_ASKPASS"
	else
		echo "FAIL ssh with a password: $out"
		bad=1
	fi

	# A login shell on a pseudo-terminal, driven over stdin, as a shell
	# session is; the remote shell does the arithmetic, so the echoed input
	# alone cannot pass.
	# shellcheck disable=SC2016 # expanded by the remote shell
	if out=$(printf 'echo shell-$((6 * 7))\nexit\n' | "${hl[@]}" -i --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" "${key[@]}" -tt agent@target 2>"$dir/tty.err") &&
		[[ "$out" == *shell-42* ]]; then
		echo "ok   a login shell on a pseudo-terminal runs what is sent over stdin"
	else
		echo "FAIL a login shell over stdin: ${out//$'\r'/} $(cat "$dir/tty.err")"
		bad=1
	fi

	if out=$("${hl[@]}" --env SSH_ASKPASS=/cfg/askpass --env SSH_ASKPASS_REQUIRE=force --entrypoint /usr/bin/ssh "$ref" \
		-F /dev/null -o IdentitiesOnly=yes -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes \
		-o ConnectTimeout=10 -i /cfg/locked -o UserKnownHostsFile=/cfg/known_hosts \
		-o PreferredAuthentications=publickey agent@target 'echo passphrase-ok' 2>&1) &&
		[ "$out" = passphrase-ok ]; then
		echo "ok   ssh unlocks a key's passphrase through SSH_ASKPASS"
	else
		echo "FAIL ssh with a passphrase-protected key: $out"
		bad=1
	fi

	if scanned=$("${hl[@]}" --entrypoint /usr/bin/ssh-keyscan "$ref" -T 5 -t ed25519 -p 2222 target 2>/dev/null | grep -v '^#') &&
		[ "$scanned" = "$(cat "$dir/port_hosts")" ]; then
		echo "ok   ssh-keyscan reads the key on port 2222 as [target]:2222"
	else
		echo "FAIL ssh-keyscan -p 2222: got \"$scanned\""
		bad=1
	fi

	if out=$("${hl[@]}" --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" -i /cfg/id -o UserKnownHostsFile=/cfg/alias_hosts \
		-o HostKeyAlias=server.example -p 2222 agent@target 'echo alias-ok' 2>&1) && [ "$out" = alias-ok ]; then
		echo "ok   ssh on port 2222 checks the key under HostKeyAlias, as through a relay"
	else
		echo "FAIL ssh with HostKeyAlias on port 2222: $out"
		bad=1
	fi

	if out=$("${hl[@]}" --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" -i /cfg/id -o UserKnownHostsFile=/cfg/changed_hosts agent@target 'echo hostlink-ran' 2>&1); then
		echo "FAIL ssh ran a command on a host whose key changed: $out"
		bad=1
	elif [[ "$out" == *"REMOTE HOST IDENTIFICATION HAS CHANGED"* ]] && [[ "$out" != *hostlink-ran* ]]; then
		echo "ok   a changed host key is refused before any command"
	else
		echo "FAIL a changed host key failed, but not for that reason: $out"
		bad=1
	fi

	if out=$("${hl[@]}" --entrypoint /usr/bin/ssh "$ref" "${opts[@]}" -i /cfg/id -o UserKnownHostsFile=/cfg/empty_hosts agent@target 'echo hostlink-ran' 2>&1); then
		echo "FAIL ssh ran a command on a host whose key is unknown: $out"
		bad=1
	elif [[ "$out" == *"No ED25519 host key is known for target"* ]] && [[ "$out" != *"HAS CHANGED"* ]] && [[ "$out" != *hostlink-ran* ]]; then
		echo "ok   an unknown host key is refused before any command"
	else
		echo "FAIL an unknown host key failed, but not for that reason: $out"
		bad=1
	fi

	if out=$("${hl[@]}" --user "$(id -u):$(id -g)" -v "$dir/passwd:/etc/passwd:ro" --entrypoint /usr/bin/ssh "$ref" \
		"${opts[@]}" -i /cfg/id600 -o UserKnownHostsFile=/cfg/known_hosts agent@target 'echo uid-ok' 2>&1) && [ "$out" = uid-ok ]; then
		echo "ok   ssh runs as uid $(id -u) given a passwd line for it, with that uid's 0600 key"
	else
		echo "FAIL ssh as uid $(id -u) with a passwd line: $out"
		bad=1
	fi
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkScripts checkWorkflows checkBases checkUnsafe checkFiles checkTypst checkCodex checkHostlink; do
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
fetchlicence checkTypst
fetchdup checkTypst
fonts checkTypst
designfonts checkTypst
codexsha checkCodex
codextag checkCodex
codexverify checkCodex
codexcontrol checkCodex
hostlinkkeysign checkHostlink
hostlinkextra checkHostlink
hostlinkuser checkHostlink
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
	fetchlicence) sed -i '0,/\tOFL-1\.1$/s//\tproprietary/' build/typst/fetch.tsv ;;
	fetchdup) grep -m1 '^fonts/' build/typst/fetch.tsv >x && cat x >>build/typst/fetch.tsv && rm x ;;
	fonts) printf '# none\n\n' >build/typst/fixtures/fonts.txt ;;
	designfonts) sed -i '/^Noto /!{/^#/!d}' build/typst/fixtures/fonts.txt ;;
	codexsha) sed -i 's/^CODEX_SHA256_ARM64=.*/CODEX_SHA256_ARM64=latest/' build/agentry-codex/source.env ;;
	codextag) sed -i 's/^CODEX_TAG=.*/CODEX_TAG=latest/' build/agentry-codex/source.env ;;
	codexverify) sed -i '/--certificate-github-workflow-sha/d' build/agentry-codex/verify.sh ;;
	codexcontrol) sed -i '0,/^refuse "/s//: refuse "/' build/agentry-codex/fetch.sh ;;
	hostlinkkeysign) sed -i 's/^ARG PACKAGES="/&openssh-keysign /' build/agentry-hostlink/Dockerfile ;;
	hostlinkextra) sed -i 's/^ARG PACKAGES="/&sshpass /' build/agentry-hostlink/Dockerfile ;;
	hostlinkuser) sed -i '/^USER 10001:10001$/d' build/agentry-hostlink/Dockerfile ;;
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
--codex-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --codex-image <ref>" >&2
		exit 2
	}
	codexImage "$2"
	;;
--hostlink-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --hostlink-image <ref>" >&2
		exit 2
	}
	hostlinkImage "$2"
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
	echo "usage: scripts/check.sh [--self-test | --unsafe-image <ref> | --files-image <ref> | --typst-image <ref> | --codex-image <ref> | --hostlink-image <ref> | --clamav-db <dir> <files-ref>]" >&2
	exit 2
	;;
esac
