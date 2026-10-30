# syntax=docker/dockerfile:1
#
# gog, built from pinned upstream source.
#
#   upstream   github.com/openclaw/gogcli
#   commit     source.env beside this file
#   licence    MIT
#   reference  the project's Dockerfile at that commit,
#              https://github.com/openclaw/gogcli/blob/<commit>/Dockerfile
#
# Changes from upstream's Dockerfile:
#
#   1. Every base is an ARG, and scripts/build.sh passes our digest-pinned
#      mirror for each, so no mutable tag is resolved at build time. Upstream
#      pins its Go builder by digest but resolves alpine:3.24 by tag, and
#      pulls its Dockerfile frontend from a tag.
#   2. The build uses the project's release settings (its .goreleaser.yaml)
#      rather than its Dockerfile's: GOTOOLCHAIN=local, GOFLAGS and GOWORK
#      cleared, modules from proxy.golang.org checked against sum.golang.org,
#      and `go mod verify` before the build. The builder installs no
#      packages (upstream adds git and tzdata to it, which the build does not
#      need), and GOOS is the builder's own, linux.
#   3. The version ldflags carry the tag and the full commit; upstream's
#      build date is left out, so a rebuild of one commit makes the same
#      binary.
#   4. The binary is refused if it is dynamically linked (CGO is off, as
#      upstream's).
#   5. The runtime stage strips every setuid and setgid bit, and keeps gog's
#      licence at /usr/share/licenses/gog/LICENSE.
#   6. The image's labels name this build.
#   7. golang.org/x/net is raised from upstream's v0.61.0 to v0.62.0 before
#      the build, the release that fixes GO-2026-6860, which govulncheck
#      reports as reachable through html.Parse in the Gmail compose text
#      conversion (quadratic time on crafted HTML). `go get` raises only what
#      that module requires, from the same proxy and checksum database as the
#      rest of the build, and `go mod verify` follows; `go version -m
#      /usr/local/bin/gog` shows the result.
#   8. Upstream upgrades ca-certificates to a version it names, in the builder
#      and in the runtime stage; here the runtime stage installs the
#      current certificate package of its Alpine base's index.
#
# Everything else matches upstream: the runtime packages (ca-certificates,
# tzdata), the non-root user (uid 10001, gog), HOME, the /persist/gogcli
# folder its documentation names as GOG_HOME, and the entrypoint.

ARG GO_IMAGE=golang:1.27.3-alpine3.24
ARG ALPINE_IMAGE=alpine:3.24

FROM ${GO_IMAGE} AS build
ENV CGO_ENABLED=0 \
	GOTOOLCHAIN=local \
	GOFLAGS= \
	GOWORK=off \
	GOPROXY=https://proxy.golang.org \
	GOSUMDB=sum.golang.org \
	GONOSUMDB= \
	GOPRIVATE= \
	GOINSECURE=
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY . .
RUN go get golang.org/x/net@v0.62.0 && go mod verify
ARG GIT_TAG
ARG GIT_COMMIT
RUN go build -trimpath \
	-ldflags "-s -w -X github.com/openclaw/gogcli/internal/cmd.version=${GIT_TAG} -X github.com/openclaw/gogcli/internal/cmd.commit=${GIT_COMMIT}" \
	-o /out/gog ./cmd/gog
# CGO is off; this holds the result to it. A dynamically linked gog would
# depend on the runtime base's musl.
RUN if ldd /out/gog >/dev/null 2>&1; then \
	echo "gog is dynamically linked; it is built with CGO off" >&2; \
	exit 1; \
	fi

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache ca-certificates tzdata \
	&& adduser -D -u 10001 -h /home/gog gog \
	&& mkdir -p /persist/gogcli \
	&& chown gog:gog /persist/gogcli \
	&& find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
ENV HOME=/home/gog
WORKDIR /home/gog
COPY --from=build /out/gog /usr/local/bin/gog
COPY --from=build /src/LICENSE /usr/share/licenses/gog/LICENSE
USER gog
ENTRYPOINT ["gog"]
CMD ["--help"]

LABEL org.opencontainers.image.title="gog (built by Agentry)" \
	org.opencontainers.image.source="https://github.com/openclaw/gogcli" \
	org.opencontainers.image.licenses="MIT" \
	org.opencontainers.image.description="gog built by Agentry from a pinned upstream commit, for the Google Workspace MCP server"
