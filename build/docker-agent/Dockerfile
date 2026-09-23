# syntax=docker/dockerfile:1
#
# Docker Agent, built by us from pinned upstream source.
#
#   upstream   github.com/docker/docker-agent
#   commit     see source.env beside this file
#   licence    Apache-2.0
#   reference  upstream.Dockerfile beside this file is the vendor's own at that
#              commit; read the diff against it
#
# What we change from upstream, and why:
#
#   1. Every base is an ARG, and scripts/build.sh passes our own digest-pinned
#      mirrors for each. Nothing here resolves a mutable tag at build time, and
#      the script refuses to build if a mirror is missing from images.tsv.
#   2. Upstream's `COPY --from=docker/mcp-gateway:v2` is a floating major tag:
#      two builds of the same commit can produce different images. Ours comes
#      from a digest.
#   3. DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1 is baked in. v1.127.0 added a
#      Docker Desktop PAC transport which in code attaches to the *unguarded*
#      transport the model clients use, skipping the Docker-host allowlist when
#      guarded=false. It is inert in a run container — detection stats
#      /run/host-services/backend.sock, which the agent container does not have
#      — but "one route out through the proxy" is an invariant worth not
#      leaving to circumstance (agentry-cli#223).
#   4. Linux only, so upstream's cross-compilation machinery (tonistiigi/xx,
#      crazymax/osxcross, zig, the builder-cross and darwin/windows paths) is
#      dropped. The binary is still CGO with external linking, still verified
#      static, still built with -tags no_audio and the same version ldflags.
#
# Everything else is at parity with upstream deliberately — same packages, same
# non-root user, same /data and /work, same ENTRYPOINT — so the runner's
# conformance goldens, recorded against the vendor image's exact event stream,
# still describe this one. Reducing the image further (it needs neither
# docker-cli nor the docker-mcp plugin in a run, where the container has no
# docker socket and every tool comes from our gateway) is a real follow-up, but
# it is a behaviour change and needs a live run to prove, not an argument.

ARG GO_IMAGE=golang:1.27.0-alpine3.23
ARG ALPINE_IMAGE=alpine:3.23
ARG GATEWAY_IMAGE=docker/mcp-gateway:v2

# Named stages so the bases resolve once and COPY --from can refer to them.
FROM ${GATEWAY_IMAGE} AS gateway

FROM ${GO_IMAGE} AS builder
# gcc, not just musl-dev: CGO_ENABLED=1 needs a C compiler and the Go alpine
# images ship none — the first build of this context died on
# `cgo: C compiler "gcc" not found`. Upstream gets one from its xx toolchain
# (`apk add clang zig`, then XX_GO_PREFER_C_COMPILER=zig); without xx, gcc
# against musl-dev is the standard Alpine static-linking pair. The ldd assertion
# after the build is what actually proves the result stayed static.
RUN apk add --no-cache gcc musl-dev
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . ./
ARG GIT_TAG
ARG GIT_COMMIT
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	set -ex; \
	go build -trimpath -tags no_audio \
	-ldflags "-s -w -linkmode=external -extldflags '-static' \
	  -X 'github.com/docker/docker-agent/pkg/version.Version=${GIT_TAG}' \
	  -X 'github.com/docker/docker-agent/pkg/version.Commit=${GIT_COMMIT}'" \
	-o /docker-agent .
# Upstream runs `xx-verify --static`; this is the same assertion without xx.
# A dynamically linked harness would silently depend on the base's musl.
RUN if ldd /docker-agent >/dev/null 2>&1; then \
	echo "docker-agent is dynamically linked; upstream verifies --static" >&2; \
	exit 1; \
	fi

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache ca-certificates docker-cli && \
	addgroup -S docker-agent && adduser -S -G docker-agent docker-agent && \
	mkdir /data /work && chmod 777 /data /work
ENV DOCKER_MCP_IN_CONTAINER=1
ENV TERM=xterm-256color
ENV DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1
COPY --from=gateway /docker-mcp /usr/local/lib/docker/cli-plugins/
COPY --from=builder /docker-agent /docker-agent
USER docker-agent
WORKDIR /work
ENTRYPOINT ["/docker-agent"]

LABEL org.opencontainers.image.title="docker-agent (built by Agentry)" \
	org.opencontainers.image.source="https://github.com/docker/docker-agent" \
	org.opencontainers.image.licenses="Apache-2.0" \
	org.opencontainers.image.description="Docker Agent built by Agentry from a pinned upstream commit, for the BriefAgent runtime's default harness"
