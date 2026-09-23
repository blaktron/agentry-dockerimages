# syntax=docker/dockerfile:1
#
# Docker Agent, built from pinned upstream source.
#
#   upstream   github.com/docker/docker-agent
#   commit     source.env beside this file
#   licence    Apache-2.0
#   reference  upstream.Dockerfile beside this file is the vendor's Dockerfile at
#              that commit
#
# Changes from upstream:
#
#   1. Every base is an ARG, and scripts/build.sh passes our digest-pinned
#      mirror for each, so no mutable tag is resolved at build time.
#   2. Upstream copies the docker-mcp plugin from the floating
#      docker/mcp-gateway:v2 tag, so two builds of one commit can differ. Ours
#      copies it from a digest.
#   3. DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1 is set. v1.127.0 added a Docker
#      Desktop PAC transport that attaches to the unguarded transport the model
#      clients use, bypassing the Docker-host allowlist. A run container lacks
#      the socket it detects (/run/host-services/backend.sock), so it is inert
#      there; the variable keeps the run's only route out through the proxy
#      without relying on that (agentry-cli#223).
#   4. Linux only: upstream's cross-compilation stages (tonistiigi/xx,
#      crazymax/osxcross, zig, the darwin and windows paths) are dropped. The
#      binary is still CGO with external linking, checked to be static, and
#      built with -tags no_audio and the same version ldflags.
#
# Everything else matches upstream (packages, non-root user, /data and /work,
# ENTRYPOINT), so the runner's conformance tests, recorded against the vendor
# image, still apply. A run needs neither docker-cli nor the docker-mcp plugin;
# removing them changes behaviour and needs a live run to confirm.

ARG GO_IMAGE=golang:1.27.0-alpine3.23
ARG ALPINE_IMAGE=alpine:3.23
ARG GATEWAY_IMAGE=docker/mcp-gateway:v2

# Named stages so the bases resolve once and COPY --from can refer to them.
FROM ${GATEWAY_IMAGE} AS gateway

FROM ${GO_IMAGE} AS builder
# CGO needs a C compiler and the Go alpine images ship none. Upstream uses zig
# from its xx toolchain; without xx, gcc with musl-dev is the usual Alpine pair
# for static linking. The ldd check after the build confirms the result.
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
# Upstream runs `xx-verify --static`; this is the same check without xx. A
# dynamically linked harness would depend on the runtime base's musl.
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
