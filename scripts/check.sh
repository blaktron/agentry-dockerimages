#!/usr/bin/env bash
# Check the repository without a registry: the manifest, the scripts, the
# workflows and the build contexts' base refs. The `ci` workflow runs it on
# every pull request.
#
# It fails when:
#   - a row of images.tsv does not have five tab-separated fields, its digest
#     is not sha256:<64 hex>, its kind is not mirror or build, or it has no role;
#   - a row of images.tsv has no section in NOTICE: a heading naming the image,
#     an "Our image:" line, or a row of the mirror table;
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
#   - the ripgrep image's source.env does not pin a 40-hex commit and a
#     version tag, its Dockerfile builds other than the default features or
#     no longer refuses PCRE2 in the dependency tree, or its fixture tree is
#     missing (build/ripgrep).
#   - the browser image's source.env does not pin the server, its Playwright,
#     a Debian chromium version, a snapshot.debian.org timestamp and a
#     package SHA-256 for each architecture; package.json and
#     package-lock.json do not pin that same server and Playwright with
#     sha512 integrity; the policy does not turn ECH, QUIC and DNS-over-HTTPS
#     off; the Dockerfile does not install with --ignore-scripts, install
#     Chromium with install.sh, point the server at it, install the policy
#     where Chromium reads it, or run as uid 10001 in /out-browser; install.sh
#     does not use the snapshot or check the SHA-256 and browsers.json; or the
#     context names Google's Chrome for Testing, its download, Playwright's
#     browser download or a Widevine CDM (build/agentry-browser).
#   - the Coding agent's toolchain image's source.env does not pin Go, Node's
#     major version, a snapshot.debian.org timestamp and its three indexes'
#     SHA-256; its PACKAGES lacks a tool the image promises or names sudo, an
#     SSH client or server, or another way to a privilege; its Dockerfile does
#     not copy Go and Node from the bases, install with install.sh, strip
#     setuid and setgid bits, keep GOTOOLCHAIN local, or run as uid 10001; or
#     install.sh does not use the snapshot, hold its indexes to their SHA-256
#     and Go and Node to source.env, or holds a source to anything but
#     Debian's archive key; or source.env does not pin a version and each
#     architecture's SHA-256 for gh, glab, tea, osv-scanner and gitleaks, or
#     install.sh does not fetch them over https only and hold each to its
#     SHA-256 and its version (build/agentry-coder).
#   - the gog image's source.env does not pin a 40-hex commit and a version
#     tag; its Dockerfile does not build with CGO off, GOTOOLCHAIN local and
#     the module sums verified, refuse a dynamically linked binary, strip
#     setuid and setgid bits and run as gog; or the MCP probe is missing
#     (build/gog).
#   - the ms365 image's source.env does not pin a 40-hex commit and a
#     version tag; its Dockerfile does not pin Graph's OpenAPI documents by
#     commit and sha256, install every package with its scripts off, take the
#     code generator from its own lockfile, leave the account tools out of
#     stdio mode, keep the token cache under the cache keeper, log to /tmp at
#     level error with the audit log off, strip setuid and setgid bits and
#     run as ms365; or the keeper, the generator's lockfile, the allow-lists
#     or the MCP probe is missing (build/ms365).
#   - the docker-agent build's patch is missing, empty, not applied with no
#     fuzz by its Dockerfile, its tests not run there, or the patch not named
#     in source.env (build/docker-agent).
#
# It pulls nothing and reads no credential, except in --unsafe-image,
# --files-image, --typst-image, --codex-image, --hostlink-image,
# --ripgrep-image, --browser-image, --coder-image, --gog-image and --ms365-image mode, which
# run the image they name.
#
# Usage:
#   scripts/check.sh              # check this checkout
#   scripts/check.sh --self-test  # break each rule in a copy and expect a failure
#   scripts/check.sh --unsafe-image <ref>
#       read the command index and the extras list out of a built
#       agentry-unsafe-kali and assert that every command in
#       build/agentry-unsafe-kali/fixture-commands.txt resolves through one of
#       them, list the commands the index left out as ambiguous, and fail
#       when a program on the image's own PATH has no row in the index, the
#       ambiguous list or base-unowned.txt. This one pulls and runs the
#       image: CONTAINER names the runtime (default docker; Apple's
#       `container` on macOS), and PLATFORM (e.g. linux/arm64) asks for, and
#       checks, one architecture. It runs under macOS's bash 3.2.
#   scripts/check.sh --files-image <ref>
#       decode each fixture in build/agentry-files/fixtures/ inside a built
#       agentry-files, with the argv the runner's decode role uses
#       (agentry-cli runnerimage/decode), with no network, every capability
#       dropped and a read-only root, and assert the phrase expect.tsv names,
#       as the invoking uid with the decode container's environment and limits. It prints the
#       package record and fails on any setuid or setgid file. PLATFORM
#       (e.g. linux/arm64) asks for, and checks, one architecture. It also
#       runs clamscan, with the argv the decode role uses, against a one-line
#       signature database made here (the EICAR test file's MD5), and fails
#       unless the EICAR file and a zip of it are found and every fixture is
#       clean.
#   scripts/check.sh --typst-image <ref>
#       run a built agentry-typst with no network, every capability dropped,
#       a read-only root and the invoking uid: `typst fonts` must list
#       every family in build/typst/fixtures/fonts.txt; the fixture report
#       (CJK, Arabic, Hindi and more, emoji, a table, code and a local image,
#       through the vendored cmarker with raw-typst off) must render to a
#       PDF/UA-1 PDF, and to PNG pages; families.typ, a block in each report
#       design's family (every family of fonts.txt not named Noto) with
#       Chinese, Arabic and Hindi behind it, must render to a PDF/UA-1 PDF with no unknown-family
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
#       root, the image's own user, CODEX_HOME on a tmpfs), and fail unless
#       the user is not root,
#       `codex --version` prints source.env's version, Codex writes to
#       CODEX_HOME, LICENSE, NOTICE, the release record and the signature
#       bundle are present, no file is setuid or setgid, the binary is static,
#       its SHA-256 is the release record's, and it verifies again against
#       OpenAI's signature with build/agentry-codex/verify.sh. PLATFORM asks
#       for, and checks, one architecture.
#   scripts/check.sh --docker-agent-image <ref>
#       run a built agentry-docker-agent-src hardened, as the runner runs a
#       harness (no network, every capability dropped, no new privileges, a
#       read-only root, the image's own user), and fail unless the user is not
#       root, `docker-agent version` names source.env's tag and commit,
#       DOCKER_AGENT_DISABLE_DESKTOP_PROXY is 1, no file is setuid or setgid,
#       the binary is static, it carries the cold-cache clear and the image
#       keeps the patch, and it links golang.org/x/net v0.60.0 or later.
#       PLATFORM asks for, and checks, one architecture.
#   scripts/check.sh --hostlink-image <ref>
#       run a built agentry-hostlink hardened, as the runner runs a host link
#       (every capability dropped, no new privileges, a read-only root, the
#       image's own user, the credentials bound read-only), against
#       a throwaway OpenSSH server (our alpine mirror with openssh-server, which needs
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
#   scripts/check.sh --ripgrep-image <ref>
#       run a built agentry-ripgrep the way the runner's tools server will:
#       no network, every capability dropped, no new privileges, a read-only
#       root, the invoking uid, no environment of its own, 512 MiB and every
#       flag the runner fixes, over build/ripgrep/fixtures/tree. It fails unless
#       rg is source.env's version without PCRE2, a case-blind search finds
#       exactly the three files that hold "invoice" (one a .gitignore names, one
#       hidden), a pattern past the size limit is refused, --files lists every
#       fixture, the binary is static, the licences are there, and the search
#       under strace (a helper on our alpine mirror, which needs network to
#       build) makes no network system call and starts no other program.
#       PLATFORM asks for, and checks, one architecture.
#   scripts/check.sh --browser-image <ref>
#       run a built agentry-browser hardened, as the runner runs its browser
#       server: no network, every capability dropped, no new privileges, a
#       read-only root, uid 10001, a tmpfs home and /tmp, an output folder bound
#       read-write. It fails unless the working directory is /out-browser,
#       the record names source.env's server, Playwright and this
#       architecture's Chromium package, SHA-256 and snapshot, the browser
#       says it is that Chromium, no Widevine CDM, Chrome for Testing build
#       or Google Chrome file is anywhere in the image, no file is setuid or
#       setgid, and
#       build/agentry-browser/check/probe.mjs, driving the image's
#       @playwright/mcp over stdio, renders the fixture page, writes a
#       screenshot and a PDF to the output folder and refuses a name outside
#       it, types a secret by name with its value masked, and sees a
#       ClientHello with no ECH; then the probe's control, with the policy
#       folder hidden, must see ECH offered. PLATFORM asks for, and checks,
#       one architecture.
#   scripts/check.sh --coder-image <ref>
#       run a built agentry-coder hardened, as the runner runs an exec
#       container: no network, every capability dropped, no new privileges, a
#       read-only root, the image's own user, a tmpfs home and /tmp, a working
#       folder bound read-write. It fails unless the user is uid 10001, the
#       record names source.env's Go, Node's major version, the snapshot and
#       the version of each release binary,
#       every package of PACKAGES is in the package record, no file is setuid
#       or setgid, no sudo, ssh or sshd is on the PATH, the licences are
#       there, and build/agentry-coder/check/probe.sh, in the working folder,
#       hears every tool answer, builds and runs a C program with cmake and
#       make, a Go module, a Python virtual environment and a Node script,
#       commits with git, sees gitleaks find a planted token and nothing in a
#       clean folder, and sees osv-scanner refuse an offline scan with no
#       database. PLATFORM asks for, and checks, one architecture.
#   scripts/check.sh --gog-image <ref>
#       run a built agentry-gog hardened, as the runner runs its MCP server:
#       no network, every capability dropped, no new privileges, a read-only
#       root, uid 10001, GOG_HOME on a tmpfs and the file keyring. It fails
#       unless `gog --version` names source.env's tag and commit, no file is
#       setuid or setgid, no sudo or SSH program is on the PATH, the binary
#       is static, the licence is there, and `gog mcp`, driven over stdio by
#       build/gog/check/mcp.py, lists only tools annotated read-only with no
#       flag, more with --allow-write and none of them a send, exactly
#       Gmail's send tools more with --allow-gmail-send too (which it refuses
#       alone), and answers a tool call with nobody signed in that there is
#       no account. Needs
#       python3, file and timeout. PLATFORM asks for, and checks, one
#       architecture.
#   scripts/check.sh --ms365-image <ref>
#       run a built agentry-ms365 hardened, as the runner runs its MCP
#       server: no network, every capability dropped, no new privileges, a
#       read-only root, uid 10001, its state and /tmp on tmpfs mounts, a
#       cache key. It fails unless --version names source.env's version, no
#       file is setuid or setgid, no sudo or SSH program is on the PATH, the
#       licence is there, the server lists exactly the tools of each switch
#       combination's allow-list in build/ms365/check/ (read only, with
#       changes, with sending), no account or download tool among them, asks
#       for Mail.Send with sending alone and for no write scope read only,
#       answers a tool call with nobody signed in that no one is, does not
#       start with no cache key, and a cache entry saved through the keeper
#       reads back and leaves no plaintext on the volume. Needs python3 and
#       timeout. PLATFORM asks for, and checks, one architecture.
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

# checkNotice wants every image in the manifest to have a place in NOTICE: a
# heading (## or ###) that names it, an "Our image:" line, or the first cell of
# a row of the mirror table.
checkNotice() {
	local bad=0 name
	while IFS=$'\t' read -r name _; do
		if [[ "$name" =~ ^[[:space:]]*(#|$) ]]; then continue; fi
		if ! grep -Eq "^##+ (.* )?$name( |\$)|^ +Our image: +$name\$|^\| \`$name\` \|" NOTICE; then
			echo "NOTICE: no section for $name (images.tsv)"
			bad=1
		fi
	done < <(cut -f1 "$MANIFEST" | sort -u)
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
	shellcheck scripts/*.sh build/agentry-files/tika-app build/typst/fetch.sh build/agentry-codex/fetch.sh build/agentry-codex/verify.sh build/agentry-browser/install.sh build/agentry-coder/install.sh build/agentry-coder/check/probe.sh || bad=1
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
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
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
	# The ambiguities, as command(packages), wrapped: check.sh reports what
	# the index leaves out rather than guessing.
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
	# Every program on the base's own PATH has a row:
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
# of fixtures/fonts.txt whose name does not start with "Noto".
designFamilies() {
	grep -vE '^(#|[[:space:]]*$|Noto )' "$TYPST_CTX/fixtures/fonts.txt" || true
}

# typstImage runs a built agentry-typst the way the runner's export_pdf will
# (no network, the invoking uid, every capability dropped, a read-only root, a fixed argv with only the bundled
# fonts and packages), over build/typst/fixtures/. Then it runs the import
# probe and the report again under strace, in a helper holding the image's
# files, so "no network call" is observed rather than only blocked.
typstImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out fam got bad=0 rc want alpine
	local helper="local/agentry-typst-check:$$"
	checkTypst || return 1
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
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
	# Hindi. A family the image lacks is only a warning to Typst, which then sets the text in the next family, so the
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
	alpine=$(awk -F'\t' '$1 == "agentry-alpine" && $2 == "alpine:3.24" { print $3 }' "$MANIFEST")
	alpine="${REGISTRY:-ghcr.io/blaktron}/agentry-alpine:3.24@$alpine"
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

RIPGREP_CTX=build/ripgrep

# checkRipgrep holds the ripgrep image's context to its pins: source.env names
# a 40-hex upstream commit and a version tag; the Dockerfile builds the rg
# binary with no --features and refuses a dependency tree naming PCRE2; the image is built per architecture; the fixture tree is
# there.
checkRipgrep() {
	local bad=0
	(
		# shellcheck source=/dev/null
		. "$RIPGREP_CTX/source.env"
		[[ "${UPSTREAM_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
			echo "$RIPGREP_CTX/source.env: UPSTREAM_COMMIT is not a 40-hex commit: ${UPSTREAM_COMMIT:-}"
			exit 1
		}
		[[ "${UPSTREAM_TAG:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$RIPGREP_CTX/source.env: UPSTREAM_TAG is not a version: ${UPSTREAM_TAG:-}"
			exit 1
		}
		[ "${IMAGE_NAME:-}" = agentry-ripgrep ] && [ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$RIPGREP_CTX/source.env: want IMAGE_NAME=agentry-ripgrep and PLATFORMS=linux/amd64,linux/arm64"
			exit 1
		}
	) || bad=1
	if ! grep -q '^	cargo build --locked --release --bin rg;' "$RIPGREP_CTX/Dockerfile"; then
		echo "$RIPGREP_CTX/Dockerfile: does not build rg with the default features (cargo build --locked --release --bin rg)"
		bad=1
	elif grep -q -- '--features' "$RIPGREP_CTX/Dockerfile"; then
		echo "$RIPGREP_CTX/Dockerfile: names --features; only the default features may be built"
		bad=1
	fi
	if ! grep -q 'for c in pcre2 pcre2-sys grep-pcre2 ' "$RIPGREP_CTX/Dockerfile"; then
		echo "$RIPGREP_CTX/Dockerfile: no longer refuses a dependency tree naming PCRE2"
		bad=1
	fi
	# main.go is named by the tree's own .gitignore, so git tracks it only
	# because it was added with -f; a fresh copy of the tree that lost it
	# would no longer prove ignore files are not read.
	if [ ! -s "$RIPGREP_CTX/fixtures/tree/wiki/concepts/billing.md" ] || [ ! -s "$RIPGREP_CTX/fixtures/tree/main.go" ]; then
		echo "$RIPGREP_CTX/fixtures/tree: the fixture tree is missing a file (main.go is added with git add -f)"
		bad=1
	fi
	return "$bad"
}

# ripgrepImage runs a built agentry-ripgrep with the flags the runner's tools
# server will pass: no network, every capability dropped, no new privileges, a
# read-only root, the invoking uid, an empty environment of its own (only
# Docker's), 512 MiB, over build/ripgrep/fixtures/tree read-only. (The tools
# server's own holding, its uid and Landlock, is the CLI's to test.) It fails
# unless rg reports source.env's version without PCRE2, a case-blind search
# finds the three files that hold "invoice" (one a .gitignore names, one hidden)
# as JSON match events and no other, a pattern past the size limit is refused,
# --files lists every fixture file, the binary is static, the licences are
# there, and a search under strace makes no network system call. PLATFORM asks
# for, and checks, one architecture.
ripgrepImage() {
	local ref="$1" bad=0 runtime="${CONTAINER:-docker}" out got want tag rc alpine
	local helper="local/agentry-ripgrep-check:$$"
	checkRipgrep || return 1
	tag=$(
		# shellcheck source=/dev/null
		. "$RIPGREP_CTX/source.env"
		echo "$UPSTREAM_TAG"
	)
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: the locals are gone at exit
	trap "rm -rf '$out'; '$runtime' rmi -f '$helper' >/dev/null 2>&1 || true" EXIT
	local run=("$runtime" run --rm --network none --cap-drop ALL --security-opt no-new-privileges
		--security-opt label=disable --read-only --user "$(id -u):$(id -g)" --env-file /dev/null
		--memory 512m ${PLATFORM:+--platform "$PLATFORM"}
		-v "$PWD/$RIPGREP_CTX/fixtures/tree:/in:ro")
	# The runner's fixed flags, every one: the two size limits bound what a
	# model's pattern may compile to.
	# --json is the search's; the listing (--files) takes the rest.
	local flags=(--no-config --no-ignore --hidden --glob '!.git' --max-filesize 8M
		--max-columns 400 --max-columns-preview --threads 2 --regex-size-limit 16M --dfa-size-limit 64M)

	# stdout alone: the first run of an image not yet local has the runtime's
	# pull progress on stderr, which is not rg's to answer for.
	got=$("${run[@]}" "$ref" --version 2>"$out/err") || got=""
	if grep -qx "ripgrep $tag" <<<"$(head -1 <<<"$got")" && grep -qF 'PCRE2 is not available' <<<"$got"; then
		echo "ok   rg --version: ripgrep $tag, no PCRE2"
	else
		echo "FAIL rg --version is not ripgrep $tag without PCRE2:"
		cat - "$out/err" <<<"$got" | head -8 | sed 's/^/     /'
		bad=1
	fi

	if "${run[@]}" "$ref" --json "${flags[@]}" --ignore-case -e invoice -- /in >"$out/json" 2>"$out/err"; then
		got=$(python3 - "$out/json" <<'EOF'
import json, sys
paths = set()
for line in open(sys.argv[1]):
    event = json.loads(line)
    if event.get("type") == "match":
        # A path that is not UTF-8 comes as "bytes", never in a fixture.
        paths.add(event["data"]["path"].get("text", "<bytes>"))
print(" ".join(sorted(paths)))
EOF
)
		want="/in/.hidden/note.txt /in/main.go /in/wiki/concepts/billing.md"
		if [ "$got" = "$want" ]; then
			echo "ok   a case-blind search found exactly: $got"
		else
			echo "FAIL a case-blind search found \"$got\", want \"$want\""
			bad=1
		fi
	else
		echo "FAIL the search did not run:"
		sed 's/^/     /' "$out/err" | head -6
		bad=1
	fi

	rc=0
	"${run[@]}" "$ref" "${flags[@]}" -e 'a{1000}{1000}' -- /in >/dev/null 2>"$out/err" || rc=$?
	if [ "$rc" -eq 2 ] && grep -qF 'exceeds size limit' "$out/err"; then
		echo "ok   a pattern past the size limit is refused: $(head -1 "$out/err")"
	else
		echo "FAIL a pattern past --regex-size-limit was not refused (exit $rc):"
		sed 's/^/     /' "$out/err" | head -4
		bad=1
	fi

	got=$("${run[@]}" "$ref" "${flags[@]}" --files -- /in 2>&1 | sort | tr '\n' ' ')
	want=$(cd "$RIPGREP_CTX/fixtures/tree" && find . -type f | sed 's|^\.|/in|' | sort | tr '\n' ' ')
	if [ "$got" = "$want" ]; then
		echo "ok   --files lists every fixture file"
	else
		echo "FAIL --files listed \"$got\", want \"$want\""
		bad=1
	fi

	# The image's files in a helper from our alpine mirror with strace and
	# file. Building it needs network; the traced run has none.
	alpine=$(awk -F'\t' '$1 == "agentry-alpine" && $2 == "alpine:3.24" { print $3 }' "$MANIFEST")
	alpine="${REGISTRY:-ghcr.io/blaktron}/agentry-alpine:3.24@$alpine"
	# shellcheck disable=SC2016 # ${RG} and ${ALPINE} are the Dockerfile's
	if ! printf 'ARG RG\nARG ALPINE\nFROM ${RG} AS rg\nFROM ${ALPINE}\nRUN apk add --no-cache strace file\nCOPY --from=rg /rg /rg\nCOPY --from=rg /licenses /licenses\n' |
		"$runtime" build -q ${PLATFORM:+--platform "$PLATFORM"} --build-arg RG="$ref" --build-arg ALPINE="$alpine" -t "$helper" - >/dev/null; then
		echo "FAIL could not build the strace helper from $alpine"
		return 1
	fi
	want=""
	case "${PLATFORM:-}" in
	*/amd64) want="x86-64" ;;
	*/arm64) want="aarch64" ;;
	esac
	got=$("$runtime" run --rm --network none "$helper" file -b /rg) || got=""
	echo "     file: $got"
	if [[ "$got" == *"static"* ]] && [[ "$got" != *"dynamically"* ]] && [[ -z "$want" || "$got" == *"$want"* ]]; then
		echo "ok   /rg is a static ${want:-binary}"
	else
		echo "FAIL /rg is not a static ${want:-binary}"
		bad=1
	fi
	if "$runtime" run --rm --network none "$helper" sh -c 'test -s /licenses/ripgrep/LICENSE-MIT && test -s /licenses/ripgrep/UNLICENSE && test -s /licenses/crates/crates.tsv'; then
		echo "ok   the licences are in /licenses"
	else
		echo "FAIL /licenses lacks ripgrep's licence files or the crate list"
		bad=1
	fi
	"$runtime" run --rm --network none --cap-add SYS_PTRACE --security-opt label=disable \
		-v "$PWD/$RIPGREP_CTX/fixtures/tree:/in:ro" "$helper" sh -c \
		'strace -f -qq -e trace=%network,execve -o /tmp/trace /rg "$@" >/tmp/log 2>&1; echo "exit $?" >>/tmp/log; cat /tmp/trace; echo "--- rg"; cat /tmp/log' \
		sh --json "${flags[@]}" --ignore-case -e invoice -- /in >"$out/trace" 2>&1 || true
	got=$(sed '/^--- rg$/,$d' "$out/trace")
	if ! grep -q 'execve("/rg"' <<<"$got"; then
		echo "FAIL strace did not trace the search:"
		sed 's/^/     /' "$out/trace" | head -8
		bad=1
	elif grep -v 'execve(' <<<"$got" | grep -q .; then
		echo "FAIL the search made network system calls:"
		grep -v 'execve(' <<<"$got" | sed 's/^/     /' | head -8
		bad=1
	elif [ "$(grep -c 'execve(' <<<"$got")" -ne 1 ]; then
		echo "FAIL the search started another program:"
		head -8 <<<"$got" | sed 's/^/     /'
		bad=1
	elif ! grep -qx 'exit 0' "$out/trace"; then
		echo "FAIL the traced search did not find its matches:"
		sed -n '/^--- rg$/,$p' "$out/trace" | sed 's/^/     /' | tail -6
		bad=1
	else
		echo "ok   the traced search made no network system call and started no other program"
	fi
	return "$bad"
}

CODEX_CTX=build/agentry-codex

# checkCodex holds the Codex image's context to its pins: source.env names a
# version, its tag, a commit and a SHA-256 for each architecture's tarball and
# for LICENSE and NOTICE; verify.sh pins OpenAI's release workflow and GitHub's
# issuer; fetch.sh verifies the binary and runs the three negative controls; and the
# Dockerfile runs fetch.sh. The greps match the scripts' own text, `$` and all.
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
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
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

DOCKER_AGENT_CTX=build/docker-agent

# checkDockerAgent holds the docker-agent build to its patch: present, applied
# with no fuzz before the build, its tests run in the build, and named in
# source.env, so a commit bump cannot drop it unseen.
checkDockerAgent() {
	local bad=0
	if [ ! -s "$DOCKER_AGENT_CTX/cold-cache-clear.patch" ]; then
		echo "$DOCKER_AGENT_CTX/cold-cache-clear.patch: missing or empty"
		bad=1
	elif ! grep -q '^RUN patch -p1 --forward --fuzz=0 .*cold-cache-clear\.patch' "$DOCKER_AGENT_CTX/Dockerfile"; then
		echo "$DOCKER_AGENT_CTX/Dockerfile: does not apply cold-cache-clear.patch with no fuzz"
		bad=1
	elif ! grep -q "go test .*-run 'ColdC|LastResponseAt'" "$DOCKER_AGENT_CTX/Dockerfile"; then
		echo "$DOCKER_AGENT_CTX/Dockerfile: does not run the patch's tests"
		bad=1
	elif ! grep -q 'cold-cache-clear\.patch' "$DOCKER_AGENT_CTX/source.env"; then
		echo "$DOCKER_AGENT_CTX/source.env: does not name cold-cache-clear.patch"
		bad=1
	fi
	return "$bad"
}

# dockerAgentImage runs a built agentry-docker-agent-src hardened (no network,
# every capability dropped, no new privileges, a read-only root, the image's own
# user) and fails unless the user is not root, `docker-agent version` names
# source.env's tag and commit, DOCKER_AGENT_DISABLE_DESKTOP_PROXY is 1, no file
# is setuid or setgid, the binary is static, it carries the cold-cache clear
# (its config key) and the image keeps the patch, and the binary links
# golang.org/x/net v0.60.0 or later. PLATFORM asks for, and checks, one
# architecture.
dockerAgentImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out got want arch id bad=0
	# shellcheck source=/dev/null
	. "$DOCKER_AGENT_CTX/source.env"
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	local run=("$runtime" run --rm --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /tmp:mode=1777 --tmpfs /data:mode=1777 --tmpfs /work:mode=1777
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
	got=$("${run[@]}" "$ref" version 2>&1) || got="(failed) $got"
	if grep -qF "$UPSTREAM_TAG" <<<"$got" && grep -qF "$UPSTREAM_COMMIT" <<<"$got"; then
		echo "ok   docker-agent version names $UPSTREAM_TAG and $UPSTREAM_COMMIT, with no network and a read-only root"
	else
		echo "FAIL docker-agent version: $got (want $UPSTREAM_TAG and $UPSTREAM_COMMIT)"
		bad=1
	fi
	if [ "$("$runtime" image inspect "$ref" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^DOCKER_AGENT_DISABLE_DESKTOP_PROXY=//p')" = 1 ]; then
		echo "ok   DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1"
	else
		echo "FAIL DOCKER_AGENT_DISABLE_DESKTOP_PROXY is not 1"
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
	"${run[@]}" --entrypoint /bin/cat "$ref" /docker-agent >"$out/docker-agent"
	if file "$out/docker-agent" | grep -q 'static'; then
		echo "ok   the binary is static"
	else
		echo "FAIL the binary is not static: $(file -b "$out/docker-agent")"
		bad=1
	fi
	# The module versions the binary records; go is on the runner, else our
	# golang mirror reads them.
	if command -v go >/dev/null; then
		go version -m "$out/docker-agent" >"$out/mods"
	else
		"$runtime" run --rm --network none -v "$out:/b:ro" "${REGISTRY:-ghcr.io/blaktron}/agentry-golang-alpine:$(golangTag)" go version -m /b/docker-agent >"$out/mods"
	fi
	if grep -aq 'cold_cache_clear' "$out/docker-agent"; then
		echo "ok   the binary carries the cold-cache clear"
	else
		echo "FAIL the binary does not carry the cold-cache clear (cold-cache-clear.patch)"
		bad=1
	fi
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'test -s /usr/share/doc/docker-agent/cold-cache-clear.patch'; then
		echo "ok   the image keeps the patch at /usr/share/doc/docker-agent/"
	else
		echo "FAIL /usr/share/doc/docker-agent/cold-cache-clear.patch is missing"
		bad=1
	fi
	local xnet
	xnet=$(awk '$1 == "dep" && $2 == "golang.org/x/net" {print $3}' "$out/mods")
	if [ -n "$xnet" ] && [ "$(printf '%s\nv0.60.0\n' "$xnet" | sort -V | head -1)" = v0.60.0 ]; then
		echo "ok   golang.org/x/net $xnet"
	else
		echo "FAIL golang.org/x/net is ${xnet:-absent}, want v0.60.0 or later"
		bad=1
	fi
	return "$bad"
}

# golangTag is the tag images.tsv mirrors agentry-golang-alpine under.
golangTag() {
	awk -F'\t' '$1 == "agentry-golang-alpine" {sub(/^[^:]*:/, "", $2); print $2; exit}' images.tsv
}

HOSTLINK_CTX=build/agentry-hostlink

# hostlinkPackages prints the Dockerfile's PACKAGES, one a line.
hostlinkPackages() {
	sed -n 's/^ARG PACKAGES="\(.*\)"$/\1/p' "$HOSTLINK_CTX/Dockerfile" | tr -s ' ' '\n' | sed '/^$/d'
}

# checkHostlink holds the host link image's context to its contract: the
# OpenSSH client's three packages and nothing else (never the setuid
# openssh-keysign, never a server), and a non-root user.
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
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
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

BROWSER_CTX=build/agentry-browser

# checkBrowser holds the browser image's context to its contract: source.env
# pins the server, the Playwright it brings, Debian's chromium package
# (version, snapshot.debian.org timestamp and a SHA-256 for each
# architecture's chromium and chromium-common, and of the snapshot's three
# signed indexes); package.json and package-lock.json pin that same
# server and Playwright, with integrity hashes, and are installed with
# --ignore-scripts; install.sh installs from the snapshot, holds its
# indexes and both packages to their SHA-256 and browsers.json to
# source.env; the Dockerfile
# points the server at that Chromium and puts the policy where it reads it;
# the policy turns ECH and QUIC off; the image runs as uid 10001 in
# /out-browser; and nothing in the context names Google's Chrome for Testing,
# its storage, Playwright's own browser download or a Widevine CDM, the
# proprietary builds this image must never carry.
checkBrowser() {
	local bad=0 f
	(
		# shellcheck source=/dev/null
		. "$BROWSER_CTX/source.env"
		b=0
		[[ "${MCP_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$BROWSER_CTX/source.env: MCP_VERSION is not a release version: ${MCP_VERSION:-}"
			b=1
		}
		[[ "${PLAYWRIGHT_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
			echo "$BROWSER_CTX/source.env: PLAYWRIGHT_VERSION is not a version: ${PLAYWRIGHT_VERSION:-}"
			b=1
		}
		[[ "${CHROMIUM_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$BROWSER_CTX/source.env: CHROMIUM_VERSION is not a Chromium version: ${CHROMIUM_VERSION:-}"
			b=1
		}
		[[ "${CHROMIUM_DEB_VERSION:-}" =~ ^[0-9.]+-[0-9A-Za-z.+~]+$ && "${CHROMIUM_DEB_VERSION%%-*}" = "${CHROMIUM_VERSION:-}" ]] || {
			echo "$BROWSER_CTX/source.env: CHROMIUM_DEB_VERSION is not a Debian package of Chromium ${CHROMIUM_VERSION:-}: ${CHROMIUM_DEB_VERSION:-}"
			b=1
		}
		[[ "${DEBIAN_SNAPSHOT:-}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
			echo "$BROWSER_CTX/source.env: DEBIAN_SNAPSHOT is not a snapshot.debian.org timestamp: ${DEBIAN_SNAPSHOT:-}"
			b=1
		}
		for key in CHROMIUM_SHA256_AMD64 CHROMIUM_SHA256_ARM64 CHROMIUM_COMMON_SHA256_AMD64 CHROMIUM_COMMON_SHA256_ARM64 DEBIAN_INDEX_SHA256_TRIXIE DEBIAN_INDEX_SHA256_TRIXIE_UPDATES DEBIAN_INDEX_SHA256_TRIXIE_SECURITY; do
			val="${!key:-}"
			[[ "$val" =~ ^[0-9a-f]{64}$ ]] || {
				echo "$BROWSER_CTX/source.env: $key is not a SHA-256: $val"
				b=1
			}
		done
		[ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$BROWSER_CTX/source.env: PLATFORMS is not linux/amd64,linux/arm64: ${PLATFORMS:-}"
			b=1
		}
		[ "${IMAGE_NAME:-}" = agentry-browser ] || {
			echo "$BROWSER_CTX/source.env: IMAGE_NAME is not agentry-browser"
			b=1
		}
		python3 - "$BROWSER_CTX" "${MCP_VERSION:-}" "${PLAYWRIGHT_VERSION:-}" <<'PY' || b=1
import json, sys
ctx, mcp, pw = sys.argv[1:4]
bad = False
def say(msg):
    global bad
    print(f"{ctx}/{msg}")
    bad = True
pkg = json.load(open(f"{ctx}/package.json"))
if pkg.get("dependencies") != {"@playwright/mcp": mcp}:
    say(f"package.json: dependencies are not exactly @playwright/mcp {mcp}: {pkg.get('dependencies')}")
lock = json.load(open(f"{ctx}/package-lock.json"))
pk = lock.get("packages", {})
for name, want in (("@playwright/mcp", mcp), ("playwright-core", pw), ("playwright", pw)):
    got = pk.get(f"node_modules/{name}", {})
    if got.get("version") != want:
        say(f"package-lock.json: {name} is {got.get('version')}, not {want}")
    if not str(got.get("integrity", "")).startswith("sha512-"):
        say(f"package-lock.json: {name} has no sha512 integrity")
for path, p in pk.items():
    if path and not p.get("integrity", "").startswith("sha512-"):
        say(f"package-lock.json: {path} has no sha512 integrity")
policy = json.load(open(f"{ctx}/policy.json"))
for key in ("EncryptedClientHelloEnabled", "QuicAllowed"):
    if policy.get(key) is not False:
        say(f"policy.json: {key} is not false")
if policy.get("DnsOverHttpsMode") != "off":
    say("policy.json: DnsOverHttpsMode is not off")
sys.exit(1 if bad else 0)
PY
		exit "$b"
	) || bad=1
	if ! grep -q '^RUN npm ci --ignore-scripts ' "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/Dockerfile: does not install the lockfile with npm ci --ignore-scripts"
		bad=1
	fi
	# shellcheck disable=SC2016 # the Dockerfile's own $TARGETARCH, matched literally
	if ! grep -q '^RUN TARGETARCH="\$TARGETARCH" sh /agentry/install.sh ' "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/Dockerfile: does not install the browser with install.sh"
		bad=1
	fi
	if ! grep -q '^ENV PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/lib/chromium/chromium ' "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/Dockerfile: does not point the server at /usr/lib/chromium/chromium"
		bad=1
	fi
	if ! grep -qx 'COPY policy.json /etc/chromium/policies/managed/agentry.json' "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/Dockerfile: does not install policy.json where Chromium reads it"
		bad=1
	fi
	if ! grep -qx 'USER 10001:10001' "$BROWSER_CTX/Dockerfile" || ! grep -qx 'WORKDIR /out-browser' "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/Dockerfile: does not run as uid 10001 in /out-browser"
		bad=1
	fi
	# shellcheck disable=SC2016 # install.sh's own variables, matched literally
	if ! grep -qF 'echo "$sum  $deb" | sha256sum -c - || refuse ' "$BROWSER_CTX/install.sh" ||
		! grep -qF 'echo "$commonSum  $common" | sha256sum -c - || refuse ' "$BROWSER_CTX/install.sh" ||
		! grep -qF 'refuse "Playwright $PLAYWRIGHT_VERSION was made for' "$BROWSER_CTX/install.sh" ||
		! grep -qF 'sha256sum -c - || refuse "$f is not the index source.env pins"' "$BROWSER_CTX/install.sh" ||
		! grep -qF 'URIs: http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT' "$BROWSER_CTX/install.sh"; then
		echo "$BROWSER_CTX/install.sh: does not install from the snapshot, hold its indexes and both packages to their SHA-256 and browsers.json to source.env"
		bad=1
	fi
	# Every apt source is held to Debian's archive key, and nothing turns
	# signature checking off.
	if [ "$(grep -c '^Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg$' "$BROWSER_CTX/install.sh")" != 2 ] ||
		grep -Ein 'trusted[=:] *yes|allow-?unauthenticated|allow-?insecure|AllowDowngradeToInsecure' "$BROWSER_CTX/install.sh" "$BROWSER_CTX/Dockerfile"; then
		echo "$BROWSER_CTX/install.sh: an apt source is not held to Debian's archive key, or signature checking is turned off"
		bad=1
	fi
	for f in Dockerfile install.sh source.env bases.env package.json package-lock.json policy.json; do
		if grep -En 'chrome-for-testing|chrome_for_testing|storage\.googleapis\.com|dl\.google\.com|cdn\.playwright\.dev|playwright\.download|PLAYWRIGHT_DOWNLOAD_HOST|WidevineCdm|widevinecdm|libwidevine|ms-playwright|PLAYWRIGHT_BROWSERS_PATH|google-chrome|cli\.js install|playwright install' "$BROWSER_CTX/$f"; then
			echo "$BROWSER_CTX/$f: names a proprietary browser build or Playwright's browser download (above)"
			bad=1
		fi
	done
	return "$bad"
}

# browserImage runs a built agentry-browser hardened, as the runner runs its
# browser server (no network, every capability dropped, no new privileges, a
# read-only root, the image's own user, a tmpfs home and /tmp, an output
# folder bound read-write).
# It fails unless the user is uid 10001 and the working directory
# /out-browser, the record names source.env's server, Playwright and this
# architecture's Chromium package, SHA-256 and snapshot, the browser the
# server is pointed at says it is that Chromium, no Widevine CDM, Chrome for
# Testing build or Google Chrome file is anywhere in the image, no file is
# setuid or setgid, and check/probe.mjs, driving the image's @playwright/mcp over stdio,
# renders the fixture page, writes a screenshot and a PDF there and nowhere
# else, types a secret by name with its value masked, and sends a ClientHello
# with no ECH; then the probe's control, with the policy folder hidden, must
# see ECH offered. PLATFORM asks for, and checks, one architecture.
browserImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" bad=0 want arch uid out dir
	checkBrowser || return 1
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
	dir=$(mktemp -d)
	chmod 0777 "$dir"
	# shellcheck disable=SC2064 # expand now: it is local
	trap "rm -rf '$dir'" EXIT
	local plat=()
	[ -n "${PLATFORM:-}" ] && plat=(--platform "$PLATFORM")
	# shellcheck disable=SC2054 # the commas are the tmpfs mounts' options
	local run=("$runtime" run --rm "${plat[@]}" --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /tmp:size=512m --tmpfs /home/browser:size=64m,uid=10001,gid=10001,mode=0700
		--pids-limit 512 --memory 2g)
	# shellcheck source=/dev/null
	. "$BROWSER_CTX/source.env"

	arch=$("${run[@]}" --entrypoint /usr/bin/uname "$ref" -m)
	case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
	if [ -n "${PLATFORM:-}" ]; then
		want="${PLATFORM##*/}"
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi

	uid=$("${run[@]}" --entrypoint /usr/bin/id "$ref" -u)
	if [ "$uid" = 10001 ]; then
		echo "ok   runs as uid 10001, not root"
	else
		echo "FAIL runs as uid $uid, not 10001"
		bad=1
	fi
	out=$("$runtime" image inspect "$ref" --format '{{.Config.WorkingDir}} {{json .Config.Entrypoint}}')
	if [ "$out" = '/out-browser ["/usr/local/bin/node","/app/node_modules/@playwright/mcp/cli.js"]' ]; then
		echo "ok   works in /out-browser and starts @playwright/mcp"
	else
		echo "FAIL working directory and entrypoint: $out"
		bad=1
	fi

	local sum
	case "$arch" in
	amd64) sum="$CHROMIUM_SHA256_AMD64" ;;
	arm64) sum="$CHROMIUM_SHA256_ARM64" ;;
	*)
		echo "FAIL no browser build for $arch"
		return 1
		;;
	esac
	echo "record:"
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/browser/record | tee "$dir/record" | sed 's/^/  /'
	if grep -qx "mcp $MCP_VERSION" "$dir/record" && grep -qx "playwright $PLAYWRIGHT_VERSION" "$dir/record" &&
		grep -qxF "chromium $CHROMIUM_VERSION $CHROMIUM_DEB_VERSION $arch $sum $DEBIAN_SNAPSHOT" "$dir/record" &&
		grep -Eqx 'node v(2[0-9]|[3-9][0-9])\.[0-9]+\.[0-9]+' "$dir/record"; then
		echo "ok   the record names source.env's server, Playwright and this architecture's Chromium package, SHA-256 and snapshot"
	else
		echo "FAIL the record does not match source.env"
		bad=1
	fi
	echo "  $("${run[@]}" --entrypoint /usr/bin/wc "$ref" -l /etc/agentry/browser/packages | cut -d' ' -f1) Debian packages recorded"

	# The executable the server is pointed at, and what it says it is: an
	# open-source Chromium build, not Google Chrome or Chrome for Testing.
	out=$("$runtime" image inspect "$ref" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^PLAYWRIGHT_MCP_EXECUTABLE_PATH=' || true)
	if [ "$out" = PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/lib/chromium/chromium ] &&
		out=$("${run[@]}" --entrypoint /usr/lib/chromium/chromium "$ref" --version) &&
		[[ "$out" =~ ^Chromium\ ${CHROMIUM_VERSION//./\\.}( |$) ]]; then
		echo "ok   the server is pointed at /usr/lib/chromium/chromium, which says $out"
	else
		echo "FAIL the browser the server is pointed at: $out"
		bad=1
	fi

	local lic
	lic="node/LICENSE @playwright/mcp/LICENSE playwright/LICENSE playwright-core/LICENSE playwright-core/NOTICE playwright-core/ThirdPartyNotices.txt chromium/copyright"
	# shellcheck disable=SC2016 # $f expands in the container's shell
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'cd /usr/share/licenses/agentry-browser && for f in '"$lic"'; do test -s "$f" || { echo "missing $f"; exit 1; }; done'; then
		echo "ok   the licences are in /usr/share/licenses/agentry-browser"
	else
		echo "FAIL a licence is missing from /usr/share/licenses/agentry-browser"
		bad=1
	fi

	# The two scans below read the image as built: root with DAC_READ_SEARCH
	# alone, so no directory is unreadable to them (a base may keep 0700
	# ones, which root without a capability cannot list), and no tmpfs over
	# /tmp or the home hiding what the image holds there. A scan that could
	# not finish fails.
	local scan=("$runtime" run --rm "${plat[@]}" --network none --cap-drop ALL --cap-add DAC_READ_SEARCH
		--security-opt no-new-privileges --security-opt label=disable --user 0:0 --entrypoint /usr/bin/find)

	# Nothing proprietary anywhere in the image: no Widevine CDM, no Chrome
	# for Testing build or archive, no Google Chrome or executable named as
	# Chrome's, no Playwright browser folder.
	local found f
	if ! found=$("${scan[@]}" "$ref" / -xdev \
		\( -iname '*widevine*' -o -iname '*chrome_for_testing*' -o -iname '*chrome-for-testing*' \
		-o -iname 'google-chrome*' -o -name 'chrome-linux*' -o -name chrome -o -iname '*chrom*.zip' \
		-o -path /opt/google -o -path /ms-playwright \) -print); then
		echo "FAIL the scan for proprietary browser files did not finish"
		bad=1
	elif [ -n "$found" ]; then
		echo "FAIL a proprietary browser file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$found"
		bad=1
	else
		echo "ok   no Widevine CDM, Chrome for Testing build or Google Chrome file"
	fi

	local suid
	if ! suid=$("${scan[@]}" "$ref" / -xdev -type f -perm /6000); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi

	local probe=("${run[@]}" -v "$dir:/out-browser:rw" -v "$PWD/$BROWSER_CTX/check:/check:ro" --entrypoint /usr/local/bin/node)
	if ! "${probe[@]}" "$ref" /check/probe.mjs; then
		echo "FAIL the probe"
		bad=1
	fi
	if ! "${probe[@]}" --tmpfs /etc/chromium/policies/managed:size=1m "$ref" /check/probe.mjs control; then
		echo "FAIL the probe's control"
		bad=1
	fi
	return "$bad"
}

CODER_CTX=build/agentry-coder

# CODER_TOOLS are the packages the image promises, which PACKAGES must hold;
# CODER_REFUSED the ones it must never install: a way to root (sudo, doas,
# polkit's pkexec), or an SSH client or server, since a dev server is reached
# through the runner's host link, which holds the sign-in.
CODER_TOOLS="ca-certificates curl git build-essential make cmake pkg-config python3 python3-dev python3-pip python3-venv"
CODER_REFUSED="sudo doas opendoas pkexec polkitd openssh-client openssh-server dropbear dropbear-bin ssh"
# CODER_BINARIES are the release binaries source.env pins, by the prefix of
# their keys there; CODER_COMMANDS the commands they install, in that order.
CODER_BINARIES="GH GLAB TEA OSV_SCANNER GITLEAKS"
CODER_COMMANDS="gh glab tea osv-scanner gitleaks"

# checkCoder holds the Coding agent's toolchain image's context to its
# contract: source.env pins Go, Node's major version, the snapshot and its
# three signed indexes, and a PACKAGES that holds every promised tool and no
# refused one; the Dockerfile copies Go and Node from the bases, installs
# with install.sh, strips setuid and setgid bits, keeps GOTOOLCHAIN local
# and runs as uid 10001; install.sh installs from the snapshot, holds the
# indexes to their SHA-256 and Go and Node to source.env, and every source
# to Debian's archive key.
checkCoder() {
	local bad=0
	(
		# shellcheck source=/dev/null
		. "$CODER_CTX/source.env"
		b=0
		[[ "${GO_VERSION:-}" =~ ^1\.[0-9]+\.[0-9]+$ ]] || {
			echo "$CODER_CTX/source.env: GO_VERSION is not a Go release: ${GO_VERSION:-}"
			b=1
		}
		[[ "${NODE_MAJOR:-}" =~ ^[0-9]+$ ]] && [ $((NODE_MAJOR % 2)) = 0 ] || {
			echo "$CODER_CTX/source.env: NODE_MAJOR is not an even (LTS) Node major version: ${NODE_MAJOR:-}"
			b=1
		}
		[[ "${DEBIAN_SNAPSHOT:-}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
			echo "$CODER_CTX/source.env: DEBIAN_SNAPSHOT is not a snapshot.debian.org timestamp: ${DEBIAN_SNAPSHOT:-}"
			b=1
		}
		for key in DEBIAN_INDEX_SHA256_TRIXIE DEBIAN_INDEX_SHA256_TRIXIE_UPDATES DEBIAN_INDEX_SHA256_TRIXIE_SECURITY; do
			val="${!key:-}"
			[[ "$val" =~ ^[0-9a-f]{64}$ ]] || {
				echo "$CODER_CTX/source.env: $key is not a SHA-256: $val"
				b=1
			}
		done
		for p in $CODER_TOOLS; do
			[[ " ${PACKAGES:-} " == *" $p "* ]] || {
				echo "$CODER_CTX/source.env: PACKAGES does not install $p"
				b=1
			}
		done
		for p in ${PACKAGES:-}; do
			[[ "$p" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || {
				echo "$CODER_CTX/source.env: PACKAGES names $p, which is not a bare package name (no version, no release)"
				b=1
			}
			[[ " $CODER_REFUSED " == *" $p "* ]] && {
				echo "$CODER_CTX/source.env: PACKAGES names $p, which the image must never hold"
				b=1
			}
		done
		for t in $CODER_BINARIES; do
			v="${t}_VERSION"
			[[ "${!v:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
				echo "$CODER_CTX/source.env: $v is not a release version: ${!v:-}"
				b=1
			}
			for a in AMD64 ARM64; do
				v="${t}_SHA256_$a"
				[[ "${!v:-}" =~ ^[0-9a-f]{64}$ ]] || {
					echo "$CODER_CTX/source.env: $v is not a SHA-256: ${!v:-}"
					b=1
				}
			done
		done
		for v in TEA_LICENSE_SHA256 OSV_SCANNER_LICENSE_SHA256; do
			[[ "${!v:-}" =~ ^[0-9a-f]{64}$ ]] || {
				echo "$CODER_CTX/source.env: $v is not a SHA-256: ${!v:-}"
				b=1
			}
		done
		[ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$CODER_CTX/source.env: PLATFORMS is not linux/amd64,linux/arm64: ${PLATFORMS:-}"
			b=1
		}
		[ "${IMAGE_NAME:-}" = agentry-coder ] || {
			echo "$CODER_CTX/source.env: IMAGE_NAME is not agentry-coder"
			b=1
		}
		grep -qx "GO_IMAGE=golang:${GO_VERSION:-}-trixie" "$CODER_CTX/bases.env" || {
			echo "$CODER_CTX/bases.env: GO_IMAGE is not golang:${GO_VERSION:-}-trixie, the Go source.env pins"
			b=1
		}
		grep -qx "NODE_IMAGE=node:${NODE_MAJOR:-}-bookworm-slim" "$CODER_CTX/bases.env" || {
			echo "$CODER_CTX/bases.env: NODE_IMAGE is not node:${NODE_MAJOR:-}-bookworm-slim, the Node source.env pins"
			b=1
		}
		exit "$b"
	) || bad=1
	if ! grep -qx 'COPY --from=go /usr/local/go /usr/local/go' "$CODER_CTX/Dockerfile" ||
		! grep -qx 'COPY --from=node /usr/local/bin/node /usr/local/bin/node' "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/Dockerfile: does not copy Go and Node from the bases"
		bad=1
	fi
	if ! grep -qx 'RUN sh /agentry/install.sh /agentry/source.env /agentry/out' "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/Dockerfile: does not install the toolchain with install.sh"
		bad=1
	fi
	if ! grep -q '^RUN find / -xdev -type f -perm /6000 -exec chmod ug-s {} + ' "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/Dockerfile: does not strip setuid and setgid bits"
		bad=1
	fi
	if ! grep -q '^[[:space:]]*GOTOOLCHAIN=local' "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/Dockerfile: does not keep GOTOOLCHAIN local"
		bad=1
	fi
	if ! grep -qx 'USER 10001:10001' "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/Dockerfile: does not run as uid 10001"
		bad=1
	fi
	# shellcheck disable=SC2016 # install.sh's own variables, matched literally
	if ! grep -qF 'sha256sum -c - || refuse "$f is not the index source.env pins"' "$CODER_CTX/install.sh" ||
		! grep -qF 'URIs: http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT' "$CODER_CTX/install.sh" ||
		! grep -qF 'URIs: http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT' "$CODER_CTX/install.sh" ||
		! grep -qF 'refuse "/usr/local/go is' "$CODER_CTX/install.sh" ||
		! grep -qF 'refuse "node is $node, not Node $NODE_MAJOR"' "$CODER_CTX/install.sh"; then
		echo "$CODER_CTX/install.sh: does not install from the snapshot, hold its indexes to their SHA-256 and Go and Node to source.env"
		bad=1
	fi
	# shellcheck disable=SC2016 # install.sh's own variables, matched literally
	if ! grep -qF 'curl -fsSL --proto '"'"'=https'"'"' --proto-redir '"'"'=https'"'"' --tlsv1.2' "$CODER_CTX/install.sh" ||
		! grep -qF 'sha256sum -c - || refuse "$1 is not the download source.env pins"' "$CODER_CTX/install.sh" ||
		! grep -qF 'refuse "${pair% *} is not ${pair#* }, the version source.env pins"' "$CODER_CTX/install.sh"; then
		echo "$CODER_CTX/install.sh: does not fetch the release binaries over https only, hold each to its SHA-256, or hold their versions to source.env"
		bad=1
	fi
	if [ "$(grep -c '^Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg$' "$CODER_CTX/install.sh")" != 2 ] ||
		grep -Ein 'trusted[=:] *yes|allow-?unauthenticated|allow-?insecure|AllowDowngradeToInsecure' "$CODER_CTX/install.sh" "$CODER_CTX/Dockerfile"; then
		echo "$CODER_CTX/install.sh: an apt source is not held to Debian's archive key, or signature checking is turned off"
		bad=1
	fi
	return "$bad"
}

# coderImage runs a built agentry-coder hardened, as the runner runs an exec
# container (no network, every capability dropped, no new privileges, a
# read-only root, the image's own user, a tmpfs home and /tmp, a working
# folder bound read-write). It fails unless the user is uid 10001, the
# record names source.env's Go, Node's major version and the snapshot,
# every package of PACKAGES is in the package record, no file is setuid or
# setgid, no sudo, ssh or sshd is on the PATH, the licences are there,
# and check/probe.sh builds and runs a project with each toolchain.
# PLATFORM asks for, and checks, one architecture.
coderImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" bad=0 want arch uid out dir p
	checkCoder || return 1
	# mktemp honours TMPDIR, so a caller can keep this work directory off a small /tmp.
	dir=$(mktemp -d)
	chmod 0777 "$dir"
	# shellcheck disable=SC2064 # expand now: it is local
	trap "rm -rf '$dir'" EXIT
	local plat=()
	[ -n "${PLATFORM:-}" ] && plat=(--platform "$PLATFORM")
	# The tmpfs mounts allow exec: a build runs what it compiles there.
	# shellcheck disable=SC2054 # the commas are the tmpfs mounts' options
	local run=("$runtime" run --rm "${plat[@]}" --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /tmp:size=1g,exec --tmpfs /home/coder:size=1g,exec,uid=10001,gid=10001,mode=0700
		--pids-limit 1024 --memory 4g)
	# shellcheck source=/dev/null
	. "$CODER_CTX/source.env"

	arch=$("${run[@]}" --entrypoint /usr/bin/uname "$ref" -m)
	case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
	if [ -n "${PLATFORM:-}" ]; then
		want="${PLATFORM##*/}"
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi

	uid=$("${run[@]}" --entrypoint /usr/bin/id "$ref" -u)
	if [ "$uid" = 10001 ]; then
		echo "ok   runs as uid 10001, not root"
	else
		echo "FAIL runs as uid $uid, not 10001"
		bad=1
	fi
	out=$("$runtime" image inspect "$ref" --format '{{.Config.User}} {{.Config.WorkingDir}}')
	if [ "$out" = '10001:10001 /home/coder' ]; then
		echo "ok   user 10001:10001 in /home/coder"
	else
		echo "FAIL user and working directory: $out"
		bad=1
	fi

	echo "record:"
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/coder/record | tee "$dir/record" | sed 's/^/  /'
	if grep -qx "go $GO_VERSION" "$dir/record" && grep -Eqx "node $NODE_MAJOR\.[0-9]+\.[0-9]+" "$dir/record" &&
		grep -qx "snapshot $DEBIAN_SNAPSHOT" "$dir/record" &&
		grep -qx "gh $GH_VERSION" "$dir/record" && grep -qx "glab $GLAB_VERSION" "$dir/record" &&
		grep -qx "tea $TEA_VERSION" "$dir/record" && grep -qx "osv-scanner $OSV_SCANNER_VERSION" "$dir/record" &&
		grep -qx "gitleaks $GITLEAKS_VERSION" "$dir/record"; then
		echo "ok   the record names source.env's Go, Node $NODE_MAJOR, the snapshot and each release binary's version"
	else
		echo "FAIL the record does not match source.env"
		bad=1
	fi
	"${run[@]}" --entrypoint /bin/cat "$ref" /etc/agentry/coder/packages >"$dir/packages"
	echo "  $(wc -l <"$dir/packages") Debian packages recorded"
	for p in $PACKAGES; do
		if ! grep -q "^$p " "$dir/packages"; then
			echo "FAIL $p is not in the package record"
			bad=1
		fi
	done
	for p in $CODER_REFUSED; do
		if grep -q "^$p " "$dir/packages"; then
			echo "FAIL $p is installed"
			bad=1
		fi
	done

	# shellcheck disable=SC2016 # expands in the container's shell
	if out=$("${run[@]}" --entrypoint /bin/sh "$ref" -c 'for c in sudo doas pkexec ssh sshd scp sftp dropbear; do command -v "$c"; done; true') && [ -z "$out" ]; then
		echo "ok   no sudo, ssh or sshd on the PATH"
	else
		echo "FAIL on the PATH: $out"
		bad=1
	fi

	local lic="go/LICENSE node/LICENSE npm/LICENSE" c
	for c in $CODER_COMMANDS; do lic="$lic $c/LICENSE"; done
	# shellcheck disable=SC2016 # $f expands in the container's shell
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'cd /usr/share/licenses/agentry-coder && for f in '"$lic"'; do test -s "$f" || { echo "missing $f"; exit 1; }; done'; then
		echo "ok   the licences are in /usr/share/licenses/agentry-coder"
	else
		echo "FAIL a licence is missing from /usr/share/licenses/agentry-coder"
		bad=1
	fi

	# The scan reads the image as built: root with DAC_READ_SEARCH alone, and
	# no tmpfs hiding what the image holds. A scan that could not finish
	# fails.
	local suid f
	if ! suid=$("$runtime" run --rm "${plat[@]}" --network none --cap-drop ALL --cap-add DAC_READ_SEARCH \
		--security-opt no-new-privileges --security-opt label=disable --user 0:0 --entrypoint /usr/bin/find \
		"$ref" / -xdev -type f -perm /6000); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi

	if ! "${run[@]}" -v "$dir:/work:rw" -v "$PWD/$CODER_CTX/check:/check:ro" --entrypoint /bin/bash "$ref" /check/probe.sh; then
		echo "FAIL the probe"
		bad=1
	fi
	return "$bad"
}

GOG_CTX=build/gog

# checkGog holds the gog image's context to its pins: source.env names a
# 40-hex upstream commit, a v-prefixed version tag and the image built per
# architecture; the Dockerfile builds with CGO off, GOTOOLCHAIN local and the
# module sums verified, refuses a dynamically linked binary, strips setuid
# and setgid bits and runs as gog; the MCP probe is there.
checkGog() {
	local bad=0
	(
		# shellcheck source=/dev/null
		. "$GOG_CTX/source.env"
		[[ "${UPSTREAM_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
			echo "$GOG_CTX/source.env: UPSTREAM_COMMIT is not a 40-hex commit: ${UPSTREAM_COMMIT:-}"
			exit 1
		}
		[[ "${UPSTREAM_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$GOG_CTX/source.env: UPSTREAM_TAG is not a version tag: ${UPSTREAM_TAG:-}"
			exit 1
		}
		[ "${IMAGE_NAME:-}" = agentry-gog ] && [ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$GOG_CTX/source.env: want IMAGE_NAME=agentry-gog and PLATFORMS=linux/amd64,linux/arm64"
			exit 1
		}
	) || bad=1
	local want
	# shellcheck disable=SC1003 # each trailing backslash is the Dockerfile's line continuation, matched literally
	for want in 'ENV CGO_ENABLED=0 \' '	GOTOOLCHAIN=local \' 'RUN go mod download && go mod verify' 'USER gog' 'RUN if ldd /out/gog >/dev/null 2>&1; then \'; do
		if ! grep -qxF -- "$want" "$GOG_CTX/Dockerfile"; then
			echo "$GOG_CTX/Dockerfile: lacks the line: $want"
			bad=1
		fi
	done
	if ! grep -qF 'find / -xdev -type f -perm /6000 -exec chmod ug-s {} +' "$GOG_CTX/Dockerfile"; then
		echo "$GOG_CTX/Dockerfile: does not strip setuid and setgid bits"
		bad=1
	fi
	if [ ! -s "$GOG_CTX/check/mcp.py" ]; then
		echo "$GOG_CTX: check/mcp.py is missing"
		bad=1
	fi
	return "$bad"
}

# gogImage runs a built agentry-gog hardened, as the runner will run its MCP
# server: no network, every capability dropped, no new privileges, a
# read-only root, the image's own user, GOG_HOME on a tmpfs and the file
# keyring. It fails unless the user is uid 10001, `gog --version` names
# source.env's tag and commit, no file is setuid or setgid, no sudo or SSH
# program is on the PATH, the binary is static, the licence is there, and
# `gog mcp` answers initialize and tools/list over stdio (check/mcp.py): with
# no flag, every tool annotated read-only; --allow-write adds tools, none a
# send; --allow-gmail-send with it adds exactly Gmail's send tools, and
# without it is refused; and a tool called with nobody signed in answers
# that there is no account. PLATFORM asks for, and checks, one architecture.
gogImage() {
	local ref="$1" runtime="${CONTAINER:-docker}" out got want arch id bad=0
	checkGog || return 1
	# shellcheck source=/dev/null
	. "$GOG_CTX/source.env"
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	# shellcheck disable=SC2054 # the commas are the tmpfs mount's options
	local run=("$runtime" run --rm -i --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /persist/gogcli:uid=10001,gid=10001,mode=0700 --tmpfs /tmp:mode=1777
		-e GOG_HOME=/persist/gogcli -e GOG_KEYRING_BACKEND=file -e GOG_KEYRING_PASSWORD=check-only
		--pids-limit 256 --memory 512m)
	if [ -n "${PLATFORM:-}" ]; then
		run+=(--platform "$PLATFORM")
		want="${PLATFORM##*/}"
		arch=$("${run[@]}" --entrypoint /bin/uname "$ref" -m </dev/null)
		case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi
	id=$("${run[@]}" --entrypoint /usr/bin/id "$ref" -u </dev/null)
	if [ "$id" = 10001 ]; then
		echo "ok   runs as uid 10001, not root"
	else
		echo "FAIL runs as uid '$id', not 10001"
		bad=1
	fi
	got=$("${run[@]}" "$ref" --version </dev/null 2>&1) || got="(failed) $got"
	if grep -qF "$UPSTREAM_TAG ($UPSTREAM_COMMIT)" <<<"$got"; then
		echo "ok   gog --version names $UPSTREAM_TAG and $UPSTREAM_COMMIT, with no network and a read-only root"
	else
		echo "FAIL gog --version: $got (want $UPSTREAM_TAG ($UPSTREAM_COMMIT))"
		bad=1
	fi
	local suid f
	if ! suid=$("${run[@]}" --user 0:0 --entrypoint /usr/bin/find "$ref" / -xdev -type f -perm /6000 </dev/null); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi
	# shellcheck disable=SC2016 # expands in the container's shell
	if got=$("${run[@]}" --entrypoint /bin/sh "$ref" -c 'for c in sudo doas su-exec ssh sshd scp sftp dropbear; do command -v "$c"; done; true' </dev/null) && [ -z "$got" ]; then
		echo "ok   no sudo or SSH program on the PATH"
	else
		echo "FAIL on the PATH: $got"
		bad=1
	fi
	"${run[@]}" --entrypoint /bin/cat "$ref" /usr/local/bin/gog </dev/null >"$out/gog"
	if file "$out/gog" | grep -q 'static'; then
		echo "ok   the binary is static"
	else
		echo "FAIL the binary is not static: $(file -b "$out/gog")"
		bad=1
	fi
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'test -s /usr/share/licenses/gog/LICENSE' </dev/null; then
		echo "ok   the licence is in /usr/share/licenses/gog"
	else
		echo "FAIL /usr/share/licenses/gog/LICENSE is missing"
		bad=1
	fi

	# Each mode's tools, sorted bytewise for comm, as `<name> read|change`.
	local mode mcpbad=0
	for mode in read write send; do
		local flags=()
		case "$mode" in
		write) flags=(--allow-write) ;;
		send) flags=(--allow-write --allow-gmail-send) ;;
		esac
		if ! timeout 120 python3 -I "$GOG_CTX/check/mcp.py" "${run[@]}" "$ref" mcp "${flags[@]}" >"$out/$mode" 2>"$out/$mode.err"; then
			echo "FAIL gog mcp ${flags[*]} did not answer over stdio:"
			sed 's/^/  /' "$out/$mode.err"
			mcpbad=1
			continue
		fi
		sed -n 's/^tool //p' "$out/$mode" | LC_ALL=C sort >"$out/$mode.tools"
		cut -d' ' -f1 "$out/$mode.tools" >"$out/$mode.names"
	done
	if [ "$mcpbad" = 0 ]; then
		if grep -qx 'capability tools' "$out/read" && [ -s "$out/read.tools" ]; then
			echo "ok   gog mcp answers initialize ($(sed -n 's/^protocol //p' "$out/read")) and lists $(wc -l <"$out/read.tools") tools, with no network"
		else
			echo "FAIL gog mcp offers no tools"
			mcpbad=1
		fi
		if grep -q ' change$' "$out/read.tools"; then
			echo "FAIL with no flag, gog mcp lists tools not annotated read-only: $(sed -n 's/ change$//p' "$out/read.tools" | tr '\n' ' ')"
			mcpbad=1
		else
			echo "ok   with no flag, every tool is annotated read-only"
		fi
		local added
		added=$(LC_ALL=C comm -13 "$out/read.names" "$out/write.names")
		if [ -n "$(LC_ALL=C comm -23 "$out/read.names" "$out/write.names")" ] || [ -z "$added" ] || grep -q send <<<"$added"; then
			echo "FAIL --allow-write does not add tools to the read-only set, or adds a send tool"
			mcpbad=1
		else
			echo "ok   --allow-write adds $(wc -l <<<"$added") tools, none a send"
		fi
		added=$(LC_ALL=C comm -13 "$out/write.names" "$out/send.names")
		if [ -n "$(LC_ALL=C comm -23 "$out/write.names" "$out/send.names")" ] || [ -z "$added" ] || grep -qv '^gmail_send_' <<<"$added"; then
			echo "FAIL --allow-gmail-send does not add exactly Gmail's send tools"
			mcpbad=1
		else
			echo "ok   --allow-gmail-send adds $(tr '\n' ' ' <<<"$added")"
		fi
		if grep -q '^call-error .*account' "$out/read"; then
			echo "ok   a tool called with nobody signed in answers that there is no account"
		else
			echo "FAIL a tool called with nobody signed in did not answer that there is no account: $(grep '^call-' "$out/read")"
			mcpbad=1
		fi
	fi
	if timeout 120 python3 -I "$GOG_CTX/check/mcp.py" "${run[@]}" "$ref" mcp --allow-gmail-send >/dev/null 2>&1; then
		echo "FAIL gog mcp --allow-gmail-send starts without --allow-write"
		mcpbad=1
	else
		echo "ok   gog mcp refuses --allow-gmail-send without --allow-write"
	fi
	[ "$mcpbad" = 0 ] || bad=1
	return "$bad"
}

MS365_CTX=build/ms365

# checkMs365 holds the ms365 image's context to its pins: source.env names a
# 40-hex upstream commit, a v-prefixed version tag and the image built per
# architecture; the Dockerfile pins Graph's two OpenAPI documents by commit
# and sha256, installs every package with its scripts off, takes the code
# generator from tools/'s lockfile, leaves the account tools out of stdio
# mode, keeps the token cache under the cache keeper, logs to /tmp at level
# error with the audit log off, strips setuid and setgid bits and runs as
# ms365; the keeper, the generator's lockfile, the three allow-lists and the
# MCP probe are there.
checkMs365() {
	local bad=0
	(
		# shellcheck source=/dev/null
		. "$MS365_CTX/source.env"
		[[ "${UPSTREAM_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
			echo "$MS365_CTX/source.env: UPSTREAM_COMMIT is not a 40-hex commit: ${UPSTREAM_COMMIT:-}"
			exit 1
		}
		[[ "${UPSTREAM_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$MS365_CTX/source.env: UPSTREAM_TAG is not a version tag: ${UPSTREAM_TAG:-}"
			exit 1
		}
		[ "${IMAGE_NAME:-}" = agentry-ms365 ] && [ "${PLATFORMS:-}" = linux/amd64,linux/arm64 ] || {
			echo "$MS365_CTX/source.env: want IMAGE_NAME=agentry-ms365 and PLATFORMS=linux/amd64,linux/arm64"
			exit 1
		}
	) || bad=1
	local want
	# shellcheck disable=SC1003,SC2016 # each trailing backslash is the Dockerfile's line continuation and each $ its own, matched literally
	for want in '	&& printf '"'"'%s  openapi.yaml\n%s  openapi-beta.yaml\n'"'"' "$GRAPH_V1_SHA256" "$GRAPH_BETA_SHA256" | sha256sum -c -' \
		'RUN npm ci --ignore-scripts --no-audit --no-fund' \
		'	&& grep -qF '"'"'const shouldRegisterAuthTools = Boolean(this.options.enableAuthTools);'"'"' src/server.ts \' \
		'	&& ! grep -qF '"'"'npx -y openapi-zod-client'"'"' bin/modules/generate-mcp-tools.mjs \' \
		'	MS365_MCP_AUTH_CACHE_COMMAND=/opt/agentry/cache-wrap \' \
		'	MS365_MCP_USE_KEYTAR=0 \' \
		'	MS365_MCP_LOG_DIR=/tmp/ms365-logs \' \
		'	LOG_LEVEL=error \' \
		'	MS365_MCP_AUDIT_LOG=false' \
		'USER ms365'; do
		if ! grep -qxF -- "$want" "$MS365_CTX/Dockerfile"; then
			echo "$MS365_CTX/Dockerfile: lacks the line: $want"
			bad=1
		fi
	done
	if ! grep -qE '^ARG GRAPH_METADATA_COMMIT=[0-9a-f]{40}$' "$MS365_CTX/Dockerfile" ||
		[ "$(grep -cE '^ARG GRAPH_(V1|BETA)_SHA256=[0-9a-f]{64}$' "$MS365_CTX/Dockerfile")" != 2 ]; then
		echo "$MS365_CTX/Dockerfile: Graph's OpenAPI documents are not pinned by a 40-hex commit and two sha256s"
		bad=1
	fi
	if ! grep -qF 'find / -xdev -type f -perm /6000 -exec chmod ug-s {} +' "$MS365_CTX/Dockerfile"; then
		echo "$MS365_CTX/Dockerfile: does not strip setuid and setgid bits"
		bad=1
	fi
	local f
	for f in cache-wrap.mjs tools/package.json tools/package-lock.json check/mcp.py check/read.re check/chg.re check/snd.re; do
		if [ ! -s "$MS365_CTX/$f" ]; then
			echo "$MS365_CTX: $f is missing"
			bad=1
		fi
	done
	return "$bad"
}

# ms365Image runs a built agentry-ms365 hardened, as the runner will run its
# MCP server: no network, every capability dropped, no new privileges, a
# read-only root, the image's own user, its state on a tmpfs, /tmp a tmpfs,
# and a cache key. It fails unless the user is uid 10001, --version names
# source.env's version, no file is setuid or setgid, no sudo or SSH program is
# on the PATH and the licence is there; the server answers initialize and
# tools/list over stdio (check/mcp.py) for each switch combination with its
# allow-list (read only, with changes, with sending) and lists exactly the
# tools the list names, no account tool among them and no download tool;
# --list-permissions asks for Mail.Send with sending alone and for no write
# scope read-only; a tool called with nobody signed in answers that no one
# is; with no key the server does not start; and a cache entry saved through
# the keeper reads back and leaves no plaintext on the volume.
# PLATFORM asks for, and checks, one architecture.
ms365Image() {
	local ref="$1" runtime="${CONTAINER:-docker}" out got want arch id key bad=0
	checkMs365 || return 1
	# shellcheck source=/dev/null
	. "$MS365_CTX/source.env"
	out=$(mktemp -d)
	# shellcheck disable=SC2064 # expand now: out is local
	trap "rm -rf '$out'" EXIT
	key=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
	# shellcheck disable=SC2054 # the commas are the tmpfs mount's options
	local run=("$runtime" run --rm -i --network none --cap-drop ALL
		--security-opt no-new-privileges --security-opt label=disable --read-only
		--tmpfs /persist/ms365:uid=10001,gid=10001,mode=0700 --tmpfs /tmp:mode=1777
		--pids-limit 256 --memory 512m)
	local keyed=("${run[@]}" -e "MS365_CACHE_KEY=$key")
	if [ -n "${PLATFORM:-}" ]; then
		run+=(--platform "$PLATFORM")
		keyed+=(--platform "$PLATFORM")
		want="${PLATFORM##*/}"
		arch=$("${run[@]}" --entrypoint /bin/uname "$ref" -m </dev/null)
		case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
		if [ "$arch" != "$want" ]; then
			echo "FAIL $ref runs as $arch, not $want"
			return 1
		fi
		echo "ok   architecture $arch"
	fi
	id=$("${run[@]}" --entrypoint /usr/bin/id "$ref" -u </dev/null)
	if [ "$id" = 10001 ]; then
		echo "ok   runs as uid 10001, not root"
	else
		echo "FAIL runs as uid '$id', not 10001"
		bad=1
	fi
	got=$("${keyed[@]}" "$ref" --version </dev/null 2>&1) || got="(failed) $got"
	if [ "$(tail -n 1 <<<"$got")" = "${UPSTREAM_TAG#v}" ]; then
		echo "ok   --version names ${UPSTREAM_TAG#v}, with no network and a read-only root"
	else
		echo "FAIL --version: $got (want ${UPSTREAM_TAG#v})"
		bad=1
	fi
	local suid
	if ! suid=$("${run[@]}" --user 0:0 --entrypoint /usr/bin/find "$ref" / -xdev -type f -perm /6000 </dev/null); then
		echo "FAIL the setuid and setgid scan did not finish"
		bad=1
	elif [ -n "$suid" ]; then
		echo "FAIL a setuid or setgid file in the image:"
		while IFS= read -r f; do echo "  $f"; done <<<"$suid"
		bad=1
	else
		echo "ok   no setuid or setgid file"
	fi
	# shellcheck disable=SC2016 # expands in the container's shell
	if got=$("${run[@]}" --entrypoint /bin/sh "$ref" -c 'for c in sudo doas su-exec ssh sshd scp sftp dropbear; do command -v "$c"; done; true' </dev/null) && [ -z "$got" ]; then
		echo "ok   no sudo or SSH program on the PATH"
	else
		echo "FAIL on the PATH: $got"
		bad=1
	fi
	if "${run[@]}" --entrypoint /bin/sh "$ref" -c 'test -s /usr/share/licenses/ms-365-mcp-server/LICENSE' </dev/null; then
		echo "ok   the licence is in /usr/share/licenses/ms-365-mcp-server"
	else
		echo "FAIL /usr/share/licenses/ms-365-mcp-server/LICENSE is missing"
		bad=1
	fi

	# Each switch combination's allow-list, as the CLI gives it.
	local read chg snd mode
	read=$(tr -d '\n' <"$MS365_CTX/check/read.re")
	chg=$(tr -d '\n' <"$MS365_CTX/check/chg.re")
	snd=$(tr -d '\n' <"$MS365_CTX/check/snd.re")
	for mode in read chg snd; do
		local flags=() list
		case "$mode" in
		read) flags=(--read-only --enabled-tools "^($read)\$") list="$read" ;;
		chg) flags=(--enabled-tools "^($read|$chg)\$") list="$read|$chg" ;;
		snd) flags=(--enabled-tools "^($read|$chg|$snd)\$") list="$read|$chg|$snd" ;;
		esac
		tr '|' '\n' <<<"$list" | LC_ALL=C sort >"$out/$mode.want"
		if ! timeout 120 python3 -I "$MS365_CTX/check/mcp.py" "${keyed[@]}" "$ref" "${flags[@]}" >"$out/$mode" 2>"$out/$mode.err"; then
			echo "FAIL the server (${mode}) did not answer over stdio:"
			sed 's/^/  /' "$out/$mode.err"
			bad=1
			continue
		fi
		sed -n 's/^tool \([^ ]*\) .*/\1/p' "$out/$mode" | LC_ALL=C sort >"$out/$mode.names"
		if cmp -s "$out/$mode.want" "$out/$mode.names"; then
			echo "ok   ${mode}: lists exactly the $(wc -l <"$out/$mode.names") tools of its allow-list"
		else
			echo "FAIL ${mode}: the tools listed are not the allow-list's:"
			diff "$out/$mode.want" "$out/$mode.names" | sed 's/^/  /'
			bad=1
		fi
		if grep -qxE 'login|logout|verify-login|list-accounts|select-account|remove-account|download-bytes|download-bytes-to-file|get-download-url' "$out/$mode.names"; then
			echo "FAIL ${mode}: an account or download tool is listed"
			bad=1
		fi
		if ! "${keyed[@]}" "$ref" "${flags[@]}" --list-permissions </dev/null >"$out/$mode.perm" 2>"$out/$mode.perm.err" ||
			! python3 -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]))' "$out/$mode.perm" >"$out/$mode.scopes" 2>/dev/null; then
			echo "FAIL ${mode}: --list-permissions did not answer"
			bad=1
			continue
		fi
		case "$mode" in
		read)
			if grep -q 'Write\|Send' "$out/$mode.scopes"; then
				echo "FAIL read only, it asks for: $(tr '\n' ' ' <"$out/$mode.scopes")"
				bad=1
			else
				echo "ok   read only, it asks for $(tr '\n' ' ' <"$out/$mode.scopes")"
			fi
			;;
		chg)
			if grep -qx 'Mail.Send' "$out/$mode.scopes" || ! grep -qx 'Mail.ReadWrite' "$out/$mode.scopes"; then
				echo "FAIL with changes, it asks for: $(tr '\n' ' ' <"$out/$mode.scopes")"
				bad=1
			else
				echo "ok   with changes, it asks for $(tr '\n' ' ' <"$out/$mode.scopes")"
			fi
			;;
		snd)
			if grep -qx 'Mail.Send' "$out/$mode.scopes"; then
				echo "ok   with sending, it asks for Mail.Send too"
			else
				echo "FAIL with sending, it does not ask for Mail.Send"
				bad=1
			fi
			;;
		esac
	done
	if grep -q '^call-error .*No accounts found' "$out/read" 2>/dev/null; then
		echo "ok   a tool called with nobody signed in answers that no one is"
	else
		echo "FAIL a tool called with nobody signed in: $(grep '^call' "$out/read" 2>/dev/null || echo 'no call')"
		bad=1
	fi
	if timeout 60 python3 -I "$MS365_CTX/check/mcp.py" "${run[@]}" "$ref" --read-only --enabled-tools "^($read)\$" >"$out/nokey" 2>&1 &&
		! grep -q '^call-error .*Auth cache command failed' "$out/nokey"; then
		echo "FAIL with no cache key, the server answered as if it could keep a sign-in"
		bad=1
	else
		echo "ok   with no cache key, the server cannot keep a sign-in"
	fi
	# shellcheck disable=SC2016 # expands in the container's shell
	got=$("${keyed[@]}" --entrypoint /bin/sh "$ref" -c '
		printf "{\"value\":\"cache-check-plaintext-0123456789\"}" | /opt/agentry/cache-wrap save token-cache || exit 1
		/opt/agentry/cache-wrap load token-cache || exit 1
		echo
		if grep -rqF cache-check-plaintext /persist/ms365; then echo plaintext; fi
		MS365_CACHE_KEY= /opt/agentry/cache-wrap load token-cache 2>/dev/null; echo "nokey $?"' </dev/null 2>&1)
	if grep -qF '"value":"cache-check-plaintext-0123456789"' <<<"$got" && ! grep -qx plaintext <<<"$got" && grep -qx 'nokey 3' <<<"$got"; then
		echo "ok   the cache keeper seals what it saves, reads it back, and refuses to run with no key"
	else
		echo "FAIL the cache keeper: $got"
		bad=1
	fi
	return "$bad"
}

runAll() {
	local bad=0 step
	for step in checkManifest checkNotice checkScripts checkWorkflows checkBases checkUnsafe checkFiles checkTypst checkDockerAgent checkCodex checkHostlink checkRipgrep checkBrowser checkCoder checkGog checkMs365; do
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
notice checkNotice
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
dockeragentpatch checkDockerAgent
dockeragentapply checkDockerAgent
dockeragenttests checkDockerAgent
codexsha checkCodex
codextag checkCodex
codexverify checkCodex
codexcontrol checkCodex
hostlinkkeysign checkHostlink
hostlinkextra checkHostlink
hostlinkuser checkHostlink
ripgrepcommit checkRipgrep
ripgrepfeatures checkRipgrep
ripgreppcre checkRipgrep
browsersha checkBrowser
browserlock checkBrowser
browserech checkBrowser
browseruser checkBrowser
browserscripts checkBrowser
browserinstall checkBrowser
browserindex checkBrowser
browsertrusted checkBrowser
browserexec checkBrowser
browserpolicy checkBrowser
browserproprietary checkBrowser
browserwidevine checkBrowser
codergo checkCoder
codertool checkCoder
codersudo checkCoder
coderssh checkCoder
coderuser checkCoder
codersetuid checkCoder
codertoolchain checkCoder
coderindex checkCoder
codertrusted checkCoder
coderbinsha checkCoder
coderfetch checkCoder
gogcommit checkGog
gogcgo checkGog
gogroot checkGog
ms365commit checkMs365
ms365scripts checkMs365
ms365authtools checkMs365
ms365openapi checkMs365
ms365root checkMs365
"

# The shellcheck case appends a literal unexpanded variable on purpose.
# shellcheck disable=SC2016
breakCase() {
	case "$1" in
	clean) ;;
	digest) sed -i '0,/\tsha256:[0-9a-f]*\t/s//\tlatest\t/' images.tsv ;;
	role) awk 'BEGIN { FS = OFS = "\t" } !done && !/^#/ && NF == 5 { NF = 4; done = 1 } 1' images.tsv >x && mv x images.tsv ;;
	notice) sed -i '/^## agentry-ripgrep$/,/^## agentry-browser$/{/^## agentry-browser$/!d}' NOTICE ;;
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
	dockeragentpatch) rm build/docker-agent/cold-cache-clear.patch ;;
	dockeragentapply) sed -i 's/--fuzz=0 //' build/docker-agent/Dockerfile ;;
	dockeragenttests) sed -i "s/-run 'ColdC|LastResponseAt'/-run 'Nothing'/" build/docker-agent/Dockerfile ;;
	codexsha) sed -i 's/^CODEX_SHA256_ARM64=.*/CODEX_SHA256_ARM64=latest/' build/agentry-codex/source.env ;;
	codextag) sed -i 's/^CODEX_TAG=.*/CODEX_TAG=latest/' build/agentry-codex/source.env ;;
	codexverify) sed -i '/--certificate-github-workflow-sha/d' build/agentry-codex/verify.sh ;;
	codexcontrol) sed -i '0,/^refuse "/s//: refuse "/' build/agentry-codex/fetch.sh ;;
	hostlinkkeysign) sed -i 's/^ARG PACKAGES="/&openssh-keysign /' build/agentry-hostlink/Dockerfile ;;
	hostlinkextra) sed -i 's/^ARG PACKAGES="/&sshpass /' build/agentry-hostlink/Dockerfile ;;
	hostlinkuser) sed -i '/^USER 10001:10001$/d' build/agentry-hostlink/Dockerfile ;;
	ripgrepcommit) sed -i 's/^UPSTREAM_COMMIT=.*/UPSTREAM_COMMIT=master/' build/ripgrep/source.env ;;
	ripgrepfeatures) sed -i 's/--bin rg;/--bin rg --features pcre2;/' build/ripgrep/Dockerfile ;;
	ripgreppcre) sed -i 's/for c in pcre2 pcre2-sys grep-pcre2 /for c in /' build/ripgrep/Dockerfile ;;
	browsersha) sed -i 's/^CHROMIUM_SHA256_ARM64=.*/CHROMIUM_SHA256_ARM64=latest/' build/agentry-browser/source.env ;;
	browserlock) sed -i 's/"@playwright\/mcp": "[^"]*"/"@playwright\/mcp": "latest"/' build/agentry-browser/package.json ;;
	browserech) sed -i 's/"EncryptedClientHelloEnabled": false/"EncryptedClientHelloEnabled": true/' build/agentry-browser/policy.json ;;
	browseruser) sed -i '/^USER 10001:10001$/d' build/agentry-browser/Dockerfile ;;
	browserscripts) sed -i 's/^RUN npm ci --ignore-scripts /RUN npm ci /' build/agentry-browser/Dockerfile ;;
	browserinstall) sed -i 's/echo "\$commonSum  \$common" | sha256sum -c - ||/true ||/' build/agentry-browser/install.sh ;;
	browserindex) sed -i 's/ | sha256sum -c - || refuse "\$f is not/ | true || refuse "$f is not/' build/agentry-browser/install.sh ;;
	browsertrusted) sed -i '0,/^Signed-By: .*/s//Trusted: yes/' build/agentry-browser/install.sh ;;
	browserexec) sed -i 's|^ENV PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/lib/chromium/chromium |ENV |' build/agentry-browser/Dockerfile ;;
	browserpolicy) sed -i 's|/etc/chromium/policies/managed/agentry.json|/etc/opt/chrome/policies/managed/agentry.json|' build/agentry-browser/Dockerfile ;;
	browserproprietary) printf 'CHROMIUM_URL=https://storage.googleapis.com/chrome-for-testing-public\n' >>build/agentry-browser/source.env ;;
	browserwidevine) printf 'COPY WidevineCdm /usr/lib/chromium/WidevineCdm\n' >>build/agentry-browser/Dockerfile ;;
	codergo) sed -i 's/^GO_VERSION=.*/GO_VERSION=latest/' build/agentry-coder/source.env ;;
	codertool) sed -i '/^PACKAGES=/s/ cmake / /' build/agentry-coder/source.env ;;
	codersudo) sed -i '/^PACKAGES=/s/ git / git sudo /' build/agentry-coder/source.env ;;
	coderssh) sed -i '/^PACKAGES=/s/ git / git openssh-client /' build/agentry-coder/source.env ;;
	coderuser) sed -i '/^USER 10001:10001$/d' build/agentry-coder/Dockerfile ;;
	codersetuid) sed -i 's|^RUN find / -xdev -type f -perm /6000 -exec chmod ug-s {} + \\$|RUN true \\|' build/agentry-coder/Dockerfile ;;
	codertoolchain) sed -i 's/GOTOOLCHAIN=local/GOTOOLCHAIN=auto/' build/agentry-coder/Dockerfile ;;
	coderindex) sed -i 's/ | sha256sum -c - || refuse "\$f is not/ | true || refuse "$f is not/' build/agentry-coder/install.sh ;;
	codertrusted) sed -i '0,/^Signed-By: .*/s//Trusted: yes/' build/agentry-coder/install.sh ;;
	coderbinsha) sed -i 's/^GLAB_SHA256_ARM64=.*/GLAB_SHA256_ARM64=latest/' build/agentry-coder/source.env ;;
	gogcommit) sed -i 's/^UPSTREAM_COMMIT=.*/UPSTREAM_COMMIT=main/' build/gog/source.env ;;
	gogcgo) sed -i 's/^ENV CGO_ENABLED=0 \\$/ENV CGO_ENABLED=1 \\/' build/gog/Dockerfile ;;
	gogroot) sed -i '/^USER gog$/d' build/gog/Dockerfile ;;
	ms365commit) sed -i 's/^UPSTREAM_COMMIT=.*/UPSTREAM_COMMIT=main/' build/ms365/source.env ;;
	ms365scripts) sed -i 's/^RUN npm ci --ignore-scripts --no-audit --no-fund$/RUN npm ci --no-audit --no-fund/' build/ms365/Dockerfile ;;
	ms365authtools) sed -i '/const shouldRegisterAuthTools = Boolean(this.options.enableAuthTools);. src\/server.ts \\$/d' build/ms365/Dockerfile ;;
	ms365openapi) sed -i 's/^ARG GRAPH_METADATA_COMMIT=.*/ARG GRAPH_METADATA_COMMIT=master/' build/ms365/Dockerfile ;;
	ms365root) sed -i '/^USER ms365$/d' build/ms365/Dockerfile ;;
	coderfetch) sed -i 's/ | sha256sum -c - || refuse "\$1 is not/ | true || refuse "$1 is not/' build/agentry-coder/install.sh ;;
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
--docker-agent-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --docker-agent-image <ref>" >&2
		exit 2
	}
	dockerAgentImage "$2"
	;;
--browser-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --browser-image <ref>" >&2
		exit 2
	}
	browserImage "$2"
	;;
--coder-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --coder-image <ref>" >&2
		exit 2
	}
	coderImage "$2"
	;;
--gog-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --gog-image <ref>" >&2
		exit 2
	}
	gogImage "$2"
	;;
--ms365-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --ms365-image <ref>" >&2
		exit 2
	}
	ms365Image "$2"
	;;
--ripgrep-image)
	[ $# -eq 2 ] || {
		echo "usage: scripts/check.sh --ripgrep-image <ref>" >&2
		exit 2
	}
	ripgrepImage "$2"
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
	echo "usage: scripts/check.sh [--self-test | --unsafe-image <ref> | --files-image <ref> | --typst-image <ref> | --codex-image <ref> | --hostlink-image <ref> | --docker-agent-image <ref> | --ripgrep-image <ref> | --browser-image <ref> | --coder-image <ref> | --gog-image <ref> | --clamav-db <dir> <files-ref>]" >&2
	exit 2
	;;
esac
