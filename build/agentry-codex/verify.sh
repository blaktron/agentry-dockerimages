#!/bin/sh
# Verify a Codex release binary against OpenAI's keyless sigstore signature,
# and exit non-zero unless it verifies. The fetch stage of
# build/agentry-codex/Dockerfile runs it, so a binary that fails stops the
# build.
#
# The signature must come from OpenAI's release workflow, rust-release.yml in
# openai/codex, run by the push of <tag> at <commit>, as GitHub Actions'
# OIDC issuer certifies it, and be in Rekor. The workflow signs the extracted
# binary with `cosign sign-blob --bundle` (.github/actions/linux-code-sign in
# openai/codex), so the binary is what is verified, not the tarball.
#
# Usage: verify.sh <binary> <bundle> <tag> <commit>
set -eu

[ $# -eq 4 ] || {
	echo "usage: verify.sh <binary> <bundle> <tag> <commit>" >&2
	exit 2
}
binary="$1"
bundle="$2"
tag="$3"
commit="$4"

cosign verify-blob \
	--bundle "$bundle" \
	--certificate-identity "https://github.com/openai/codex/.github/workflows/rust-release.yml@refs/tags/$tag" \
	--certificate-oidc-issuer https://token.actions.githubusercontent.com \
	--certificate-github-workflow-repository openai/codex \
	--certificate-github-workflow-trigger push \
	--certificate-github-workflow-ref "refs/tags/$tag" \
	--certificate-github-workflow-sha "$commit" \
	"$binary"
