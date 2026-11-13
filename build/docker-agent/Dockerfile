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
#      without relying on that.
#   4. Linux only: upstream's cross-compilation stages (tonistiigi/xx,
#      crazymax/osxcross, zig, the darwin and windows paths) are dropped. The
#      binary is still CGO with external linking, checked to be static, and
#      built with -tags no_audio and the same version ldflags.
#   5. otel's otlptracegrpc exporter is raised before the build from v1.40.0
#      to v1.47.0, the version of the rest of upstream's otel modules and the
#      release that fixes the advisory govulncheck reports against upstream's
#      pin. `go get` raises only what that module requires; the build records
#      the result, and `go version -m /docker-agent` shows it.
#   6. cold-cache-clear.patch, applied with no fuzz before the build, adds the
#      agent setting `cold_cache_clear: {after, keep_turns, keep_browser,
#      browser_tools}`. On the first model request of a turn that starts more
#      than `after` since the previous model response ended, when the
#      provider's prompt cache has expired and the history is re-sent uncached
#      anyway, every tool result older than the newest `keep_turns` turns, and
#      every result of a tool in `browser_tools` but the newest `keep_browser`,
#      is sent as a placeholder that names the call and says to call it again.
#      The stored session keeps the originals and records which results are
#      cleared, so later requests, a reload and a compaction send the same
#      bytes. Nothing is cleared inside a turn, and an agent without the
#      setting is unchanged. The patch's own tests run in the build.
#   7. long-runs.patch, applied with no fuzz after it, keeps a long run on a
#      model server of the person's own going:
#      - LM Studio's refusal of an over-long prompt ("... is greater than the
#        context length") is a context overflow, as llama.cpp's and vLLM's
#        already are;
#      - an overflow on a model whose window is unknown compacts against a
#        window estimated from the refusal (the window it states, or half the
#        refused request's estimated size, halved again up to three times if
#        the summary call overflows it too) instead of emitting the error that
#        ends a `run --exec`;
#      - provider_opts.stream_idle_timeout (a duration, or seconds) replaces
#        the 5-minute stream idle limit for that model;
#      - the agent setting `compaction_notes: <path>` ends every compaction
#        summary with one sentence pointing the agent at that notes file.
#      Its tests run in the build.
#   8. loop-nudge.patch, applied with no fuzz after both, stops the loop
#      detector from ending a run. When the model makes the same tool call with
#      the same arguments max_consecutive_tool_calls times in a row (default
#      5), an implicit user message is added after the call's results. It
#      names the tool and the count, never the arguments, and tells the agent
#      to reach the goal another way, or to say why it cannot and move on or
#      end the run; the detector resets, and every later streak gets the
#      message again with the count of earlier ones. Each nudge is a Warning
#      event starting "Loop nudge". The run's own limits still apply. Its
#      tests run in the build.
#   9. length-recovery.patch, applied with no fuzz after the three, adds the
#      agent setting `length_recovery: true`. An answer the output limit cut
#      off no longer ends the run: the cut text, its reasoning and any tool
#      call streamed into it leave the conversation, a one-line stub takes
#      their place, and an implicit user message after it says what was cut
#      and asks for one concrete step or a short final answer, or for the cut
#      call again with complete arguments. A cut call is never run. At most two
#      a run; the third cut answer ends the run as upstream. Each recovery is a
#      Warning event starting "Length recovery". Without the setting, a cut
#      answer ends the run as upstream. Its tests run in the build.
#  10. compaction-reason.patch, applied with no fuzz after the four, adds
#      `reason` ("threshold", "overflow" or "manual") to the "completed"
#      session_compaction event of a compaction the runtime attempted, so a
#      caller of `run --exec --json` can tell a compaction the window's
#      threshold started from one a refused request forced. The event is
#      otherwise unchanged. Its tests run in the build.
#  11. acp-usage.patch, applied with no fuzz after the five, sends a prompt's
#      ACP usage_update whatever the model's window: `size` is 0 when it is
#      unknown and `used` is the session's tokens either way, so an ACP client
#      counts a session's tokens on any model. The /usage command is
#      unchanged. Its tests run in the build.
#  12. acp-context-events.patch, applied with no fuzz after the six, reports
#      two changes to a session's history over ACP as extension
#      notifications, apart from the agent's words: an applied compaction
#      (`_agentry/session_compaction`, with its reason), in a prompt and from
#      /compact, and a cold-cache clear (`_agentry/results_cleared`), which
#      the runtime now emits as a `results_cleared` event (also printed by
#      `run --exec --json`). A client that does not know the methods ignores
#      them. Its tests run in the build.
#
# The patches' files carry a note that Agentry's build adds or changes them, and
# the image keeps the seven patches at /usr/share/doc/docker-agent/.
#
# Everything else matches upstream (packages, non-root user, /data and /work,
# ENTRYPOINT), so the runner's conformance tests, recorded against the vendor
# image, still apply. A run needs neither docker-cli nor the docker-mcp plugin;
# removing them changes behaviour and needs a live run to confirm.

ARG GO_IMAGE=golang:1.27.4-alpine3.24
ARG ALPINE_IMAGE=alpine:3.24
ARG GATEWAY_IMAGE=docker/mcp-gateway:v2

# Named stages so the bases resolve once and COPY --from can refer to them.
FROM ${GATEWAY_IMAGE} AS gateway

FROM ${GO_IMAGE} AS builder
# CGO needs a C compiler and the Go alpine images ship none. Upstream uses zig
# from its xx toolchain; without xx, gcc with musl-dev is the usual Alpine pair
# for static linking. The ldd check after the build confirms the result.
RUN apk add --no-cache gcc musl-dev patch git jq
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . ./
COPY --from=agentry cold-cache-clear.patch long-runs.patch loop-nudge.patch length-recovery.patch compaction-reason.patch acp-usage.patch acp-context-events.patch /agentry/
# --fuzz=0: a hunk that no longer matches exactly fails the build rather than
# landing somewhere near.
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/cold-cache-clear.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/long-runs.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/loop-nudge.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/length-recovery.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/compaction-reason.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/acp-usage.patch
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/acp-context-events.patch
RUN --mount=type=cache,target=/go/pkg/mod \
	go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@v1.47.0 && \
	go mod verify
ARG GIT_TAG
ARG GIT_COMMIT
ENV CGO_ENABLED=1
# The patch's tests, on the pinned commit: the clear fires only on a turn's
# first request after a cold gap, never inside a turn, keeps the newest turns
# and browser results, never quotes a result, and sends the same bytes again.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'ColdC|LastResponseAt' \
	./pkg/session ./pkg/runtime ./pkg/config/latest
# long-runs.patch's tests: LM Studio's refusal is an overflow, a stated window
# is read, an overflow with no known window compacts with no error event, an
# estimate the summary overflows is halved, a manual compaction still needs a
# window, the idle limit is read from provider_opts, and the notes reminder is
# added once, only when a single-line notes file is named.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'LongRun' \
	./pkg/modelerrors ./pkg/runtime ./pkg/config/latest
# loop-nudge.patch's tests: a streak nudges the agent and the run goes on, the
# next request ends with the nudge after the call's result, every streak is
# nudged again with the count, the agent can still end the run, a run that
# never repeats is unchanged, polling tools stay exempt, the nudge names the
# tool and the count but never the arguments, and the upstream tests that
# expected a streak to end the run now expect the nudge.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'LoopNudge|RepeatedDatetimeReads|FailedRandomDrawsTriggerLoopDetection' \
	./pkg/runtime
# length-recovery.patch's tests: a cut answer, a cut call and reasoning until
# the limit leave the conversation and the run goes on, the next request ends
# with the instruction after the stub and carries none of the cut text, a cut
# call is never run, the third cut ends the run as upstream, a run with no cut
# is unchanged, and the setting off is upstream.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'LengthRecovery' \
	./pkg/runtime ./pkg/config/latest
# compaction-reason.patch's tests: a threshold, an overflow and a manual
# compaction each complete with their reason, a skipped one too, the started
# event carries none, and a background compaction completes as a threshold one.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'CompactionReason' \
	./pkg/runtime
# acp-usage.patch's tests: a prompt's usage goes out with size 0 and the
# session's tokens when the window is unknown, as before when it is known, and
# the upstream usage tests (the one it changes, and /usage's) still pass.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'TurnUsage|TestUsage' \
	./pkg/acp
# acp-context-events.patch's tests: a cold-cache clear emits one
# results_cleared event and a warm turn none, a prompt sends one notification
# per applied compaction (with its reason) and per clear, none for a skipped
# or failed compaction and none as message text, /compact sends one only when
# applied, and the event registry knows the new event.
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 -run 'ColdCacheClearIsReported|ReportsAppliedCompactions|ReportsAnAppliedCompaction|TestEventTypes' \
	./pkg/runtime ./pkg/acp
# The whole suites of every package the patches touch, so an upstream test a
# patch breaks fails the build too, not only the patches' own tests above.
# git and jq (above) are for the worktree and hook tests. Left out: the tests
# that read files upstream's .dockerignore keeps out of the build context,
# examples/*.yaml (TestLoadExamples, TestLoadLayaEvaluatorExample,
# TestRoutingExample_*, TestRoutingCommandExample) and pkg/teamloader/testdata
# (TestAutoModelFallbackError, TestInstructionExpansion, TestOverrideModel,
# TestToolsetInstructions, TestWithPromptFiles).
RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg/mod \
	go test -tags no_audio -count=1 \
	-skip '^(TestLoadExamples|TestLoadLayaEvaluatorExample|TestRoutingExample_.*|TestRoutingCommandExample|TestAutoModelFallbackError|TestInstructionExpansion|TestOverrideModel|TestToolsetInstructions|TestWithPromptFiles)$' \
	./pkg/acp ./pkg/agent ./pkg/config/latest ./pkg/modelerrors \
	./pkg/runtime ./pkg/session ./pkg/teamloader
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
COPY --from=agentry cold-cache-clear.patch long-runs.patch loop-nudge.patch length-recovery.patch compaction-reason.patch acp-usage.patch acp-context-events.patch /usr/share/doc/docker-agent/
USER docker-agent
WORKDIR /work
ENTRYPOINT ["/docker-agent"]

LABEL org.opencontainers.image.title="docker-agent (built by Agentry)" \
	org.opencontainers.image.source="https://github.com/docker/docker-agent" \
	org.opencontainers.image.licenses="Apache-2.0" \
	org.opencontainers.image.description="Docker Agent built by Agentry from a pinned upstream commit with its cold-cache clear, long-runs, loop-nudge, length-recovery, compaction-reason, acp-usage and acp-context-events patches, for the QuickAgent runtime's default harness"
