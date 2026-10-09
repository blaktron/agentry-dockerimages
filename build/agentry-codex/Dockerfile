# agentry-codex: the Codex harness image, OpenAI's Codex CLI release binary
# on our Alpine mirror (agentry-dockerimages#53; agentry-notes
# plans/model-sign-ins.md §4.3, D5, D11). The CLI's codex container adapter
# runs it for a ChatGPT model sign-in, and on an OpenAI key when a policy
# picks it (agentry-cli#739).
#
#   upstream   github.com/openai/codex, the release at CODEX_TAG (source.env)
#   licence    Apache-2.0; LICENSE and NOTICE at CODEX_COMMIT are in the image
#
# Nothing is compiled. The fetch stage downloads the musl release tarball for
# the build's architecture, holds it to its SHA-256 in source.env, and
# verifies the binary against OpenAI's keyless sigstore signature from
# rust-release.yml at CODEX_TAG and CODEX_COMMIT (fetch.sh, verify.sh). Any
# mismatch fails the build, and every build also proves that the verifier
# refuses a tampered copy and another tag's identity. The binary is copied
# unmodified.
#
# The image:
#
#   /usr/local/bin/codex           the binary, static (musl); the entrypoint
#   /etc/agentry/codex/release     what was fetched and verified, and its hashes
#   /etc/agentry/codex/codex.sigstore
#                                  OpenAI's signature bundle, so the binary in
#                                  the image can be verified again (README)
#   /usr/share/licenses/codex/     Codex's LICENSE and NOTICE
#
# It runs as uid 10001 (codex), never root. CODEX_HOME is the user's home,
# /home/codex, which the runner mounts as a tmpfs over a read-only root (the
# CLI's hardened agent container: no network but the run's, every capability
# dropped, no new privileges). It is the home itself, not a directory in it,
# because Codex does not create a missing CODEX_HOME, and a tmpfs mounted on
# the home would hide one made here. It is not under /tmp, where Codex
# refuses its helper links (codex-rs/arg0).
# No bwrap is installed. Codex's own sandbox code is in the binary, but it
# starts only for a shell or patch tool, which the adapter does not offer
# (plan §3 I1, the adapter's to keep), and its start-up check only warns
# (plan D5; research option-b-codex-image.md R4).
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG ALPINE_IMAGE=alpine:3.22
ARG COSIGN_IMAGE=ghcr.io/sigstore/cosign/cosign:v3.1.3

FROM ${COSIGN_IMAGE} AS cosign

FROM ${ALPINE_IMAGE} AS fetch
ARG TARGETARCH
COPY --from=cosign /ko-app/cosign /usr/local/bin/cosign
COPY source.env fetch.sh verify.sh /agentry/
RUN sh /agentry/fetch.sh /agentry/source.env /agentry/verify.sh /out

FROM ${ALPINE_IMAGE}
RUN addgroup -g 10001 codex \
	&& adduser -D -u 10001 -G codex -h /home/codex -s /sbin/nologin codex \
	&& mkdir -p /etc/agentry/codex
COPY --from=fetch /out/codex /usr/local/bin/codex
COPY --from=fetch /out/release /out/codex.sigstore /etc/agentry/codex/
COPY --from=fetch /out/licenses/ /usr/share/licenses/codex/
ENV CODEX_HOME=/home/codex
USER 10001:10001
WORKDIR /home/codex
ENTRYPOINT ["/usr/local/bin/codex"]
