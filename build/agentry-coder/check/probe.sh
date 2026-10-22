#!/bin/bash
# The sh -c bodies below run in the container's shell, so they are
# single-quoted.
# shellcheck disable=SC2016

# Run inside agentry-coder by scripts/check.sh --coder-image, with no network
# and the working folder bound at /work: build and run a small project with
# each toolchain the image promises, the way the Coding agent would.
#
# Prints one ok or FAIL line per step and exits 1 on any FAIL.
set -uo pipefail

bad=0
step() {
	local what="$1"
	shift
	local out
	if out=$("$@" 2>&1 </dev/null); then
		echo "ok   $what"
	else
		echo "FAIL $what"
		printf '%s\n' "$out" | sed 's/^/     /'
		bad=1
	fi
}

cd /work || exit 1
rm -rf c go py node git leak osv

# Each tool answers --version.
for t in git curl gcc g++ cc make cmake pkg-config python3 node npm npx jq zip xz bzip2 patch file; do
	step "$t answers" "$t" --version
done
step "go answers" go version
step "unzip answers" unzip -v
for t in gh glab tea osv-scanner; do
	step "$t answers" "$t" --version
done
step "gitleaks answers" gitleaks version
step "gh and glab send no usage report and look for no update" sh -c '[ "$GH_TELEMETRY" = false ] && [ -n "$GH_NO_UPDATE_NOTIFIER" ] && [ -n "$GH_NO_EXTENSION_UPDATE_NOTIFIER" ] && [ "$GLAB_SEND_TELEMETRY" = false ] && [ "$GLAB_CHECK_UPDATE" = false ]'

# gitleaks finds a token planted in a folder and nothing in a clean one. The
# token is made here, so this file holds none.
mkdir -p leak/found leak/clean
tok="ghp_$(head -c 400 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)"
printf 'token = "%s"\n' "$tok" >leak/found/config.txt
echo 'nothing to see' >leak/clean/readme.txt
step "gitleaks finds a planted token" sh -c 'gitleaks dir leak/found --no-banner --exit-code 3 >/dev/null 2>&1; [ $? = 3 ]'
step "gitleaks finds nothing in a clean folder" gitleaks dir leak/clean --no-banner --exit-code 3

# osv-scanner offline with no database fails for want of the database, and
# never says it found no issues.
mkdir -p osv && printf 'module example.com/x\n\ngo 1.22\n\nrequire golang.org/x/net v0.0.1\n' >osv/go.mod
step "osv-scanner offline with no database refuses to answer" sh -c 'out=$(osv-scanner scan source --offline osv 2>&1); [ $? != 0 ] && printf "%s" "$out" | grep -q "no offline version of the OSV database" && ! printf "%s" "$out" | grep -qi "no issues found"'

# C with cmake and make.
mkdir -p c && cat >c/hello.c <<'C'
#include <stdio.h>
int main(void) { printf("hello from c\n"); return 0; }
C
cat >c/CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(hello C)
add_executable(hello hello.c)
CMAKE
step "cmake configures and make builds a C program" sh -c 'cmake -S c -B c/build >/dev/null && make -C c/build >/dev/null'
step "the C program runs" sh -c '[ "$(c/build/hello)" = "hello from c" ]'

# Go, a module with no dependency, built offline.
mkdir -p go && cat >go/main.go <<'GO'
package main

import "fmt"

func main() { fmt.Println("hello from go") }
GO
step "go builds a module" sh -c 'cd go && go mod init example.com/hello >/dev/null 2>&1 && go build -o hello . && go vet .'
step "the Go program runs" sh -c '[ "$(go/hello)" = "hello from go" ]'
step "go refuses to fetch a newer toolchain" sh -c '[ "$(go env GOTOOLCHAIN)" = local ]'

# Python, in a virtual environment with its own pip.
step "python3 makes a venv with pip" sh -c 'python3 -m venv py/venv && py/venv/bin/pip --version >/dev/null'
step "the venv's python runs" sh -c '[ "$(py/venv/bin/python -c "print(\"hello from python\")")" = "hello from python" ]'
step "python3 has its headers" sh -c 'test -f "$(python3 -c "import sysconfig; print(sysconfig.get_paths()[\"include\"])")/Python.h"'

# Node, with an npm project and a script.
mkdir -p node
step "npm makes a project" sh -c 'cd node && npm init -y >/dev/null'
step "node runs a script" sh -c '[ "$(node -e "console.log(\"hello from node\")")" = "hello from node" ]'

# git makes a repository and a commit.
step "git commits" sh -c 'git init -q git && cd git && echo x >x && git add x && git -c user.name=coder -c user.email=coder@example.invalid commit -qm x'

rm -rf c go py node git leak osv
exit "$bad"
