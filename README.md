# agentry-dockerimages

The container images of the **BriefAgent runtime** — the tool plane, the agent
harness, and the bases the runner's own images are built from — kept under our
own control instead of pulled from public registries at run time.

This repository is the manifest, the build contexts and the scripts. The images
themselves live in the container registry under the `blaktron` namespace on
GHCR.

## Why this exists

The runner already builds its own enforcement plane. `agentry-cli/runnerimage/`
is a self-contained, stdlib-only Go build context embedded in the CLI binary,
materialised on first use and built locally, tagged by content hash — recorded
as DR-2, whose reason is that *"first use needs no access to our repos or
registries"*.

Everything else in a run was fetched from Docker Hub by **mutable tag**:

| What | Ref the runner used | Why it matters |
|---|---|---|
| the tool plane | `docker/mcp-gateway:v0.43.3` | started once per run with `--block-network`; it is the whole tool surface |
| the harness | `docker/docker-agent:1.128.0` | the program that talks to the model, and the container that **holds the model API key** |
| the runner image's builder | `golang:1.27-alpine` | the `GO_IMAGE` build-arg |
| the runner image's base | `alpine:3.22` | the `FROM` of its runtime stage |
| declared npm MCP servers | `node:22-alpine` | installs and runs a BriefAgent's declared servers |
| declared PyPI MCP servers | `python:3.12-alpine` | likewise |

So the asymmetry DR-2 was written to avoid had grown back: the trust-critical
plane we build ourselves, and the component holding the model key fetched by a
tag anyone who can push to that repository can move. The runner's own policy
comment concedes the gap — *"Tags, not digests: the CLI cannot know digest
values ahead of time"* (`pkg/runner/policy/policy.go:33`) — and the generated
policy file tells the operator, loudly, to pin digests. Nothing enforced it.

There is a second reason, specific to the harness. `docker/docker-agent` is
Docker Agent, Apache-2.0, source at `github.com/docker/docker-agent`, and its
image carries `org.opencontainers.image.revision` naming the exact commit — so
image and source are cryptographically tied. But the **container image is not a
distribution channel its publisher documents**: the vendor's installation docs
list Docker Desktop, Homebrew, release binaries and build-from-source, and the
only mention of the image in its `docs/` uses `docker/docker-agent:edge` as a
*source of the binary*. Cadence is roughly four releases a week with no LTS, no
support window and no deprecation policy, and the product has already been
renamed once. Owning the bytes we run is the answer to that, and owning the
Dockerfile is how we get to open-source them.

Tracked as [agentry-cli#224](https://github.com/blaktron/agentry-cli/issues/224).

## The inventory

`images.tsv` is the single source of truth. Tab-separated on purpose: this is a
supply-chain manifest and the script that reads it should be auditable without a
parser.

```
<our name>  <upstream ref>  <upstream digest>  <kind>  <role>
```

`kind` is `mirror` — the upstream bytes are copied into our registry unchanged —
or `build` — we build the image ourselves from pinned upstream source, under
`build/<name>/`.

| Ours | Upstream | Kind | Role in a run |
|---|---|---|---|
| `agentry-mcp-gateway` | `docker/mcp-gateway:v0.43.3` | mirror | the tool plane |
| `agentry-docker-agent` | `docker/docker-agent:1.128.0` | mirror | the default harness |
| `agentry-golang-alpine` | `golang:1.27-alpine` | mirror | builds the runner image |
| `agentry-alpine` | `alpine:3.22` | mirror | the runner image's runtime base |
| `agentry-node-alpine` | `node:22-alpine` | mirror | declared npm MCP servers |
| `agentry-python-alpine` | `python:3.12-alpine` | mirror | declared PyPI MCP servers |

**Not here:** the SecureAgentry application's images — postgres, minio, redis,
the nginx edge, authentik, opensearch, `secureagentryd`. Those belong to the
application's compose stack and helm chart, not to the runtime that runs a
BriefAgent.

**Also not here, and deliberately:** `agentry-runner:<hash>`, the per-release
exec images, and the per-release MCP-server install images. The runner builds
all three locally on the machine that runs them, from the context embedded in
the CLI binary. What this repository changes for them is where their *bases*
come from.

## Digests survive the copy

`scripts/mirror.sh` uses `docker buildx imagetools create`, which copies a
manifest registry-to-registry. Layers never come to the machine running it, a
multi-platform manifest list survives intact, and — because the manifest bytes
are copied unchanged — **the digest is the same on both sides**:

```
alpine:3.22@sha256:5291449c…  →  ghcr.io/blaktron/agentry-alpine:3.22@sha256:5291449c…
```

The script verifies that after every copy and fails if the destination digest
differs. This is what makes the mirror a real control rather than a cache: a
consumer that pins our digest gets exactly the bytes that were reviewed, and
cannot be moved by anyone pushing to the upstream tag.

## Using it

The runner's operator policy already takes any ref, so nothing in the CLI has to
change to consume these — `~/.agentry/runner/policy.yaml`:

```yaml
images:
  gateway: ghcr.io/blaktron/agentry-mcp-gateway:v0.43.3
  harnessDockerAgent: ghcr.io/blaktron/agentry-docker-agent:1.128.0
  goBuilder: ghcr.io/blaktron/agentry-golang-alpine:1.27-alpine
  nodeRuntime: ghcr.io/blaktron/agentry-node-alpine:22-alpine
  pythonRuntime: ghcr.io/blaktron/agentry-python-alpine:3.12-alpine
```

`alpine:3.22` is the one ref that is not a policy field: it is the `FROM` of
`agentry-cli/runnerimage/Dockerfile`'s runtime stage, so pointing the runner
image's base at ours is a change in that repository, not a setting.

### The defaults have not moved, and why

`policy.Default*Image` in the CLI still names the public refs. Moving them is a
product decision with two preconditions, and it is **not** done here:

1. **The packages must be public.** They are private now, because this
   repository is. A CLI whose defaults point at a private registry cannot be run
   by anyone without a token, which is incompatible with an open core whose
   first run is meant to need no access to our infrastructure (DR-2's own
   reason). Open-sourcing this repository and making its packages public is the
   point of the exercise, but it is a separate step and it is the operator's
   call.
2. **It reverses part of DR-2 and owes a register entry.** DR-2 says first use
   needs no access to our registries. Pointing the defaults at GHCR trades that
   property for provenance we control. That is a defensible trade — a digest-
   pinned image from a registry we publish is arguably a stronger guarantee than
   a tag from one we do not — but it is a departure and must be recorded.

Until both are settled, the estate's own machines can point at these by policy
(the dev server, the CI runners, the hosted-run worker's platform policy) while
the shipped defaults stay on the public refs.

## Scripts

| | |
|---|---|
| `scripts/pin.sh` | re-resolve every upstream ref and report which tags have moved. **Never edits the manifest** — a moved tag is a decision, because the pinned digest is the one that was reviewed. |
| `scripts/mirror.sh [name …]` | copy the `mirror` rows into `$REGISTRY` by digest, then verify each destination digest. |
| `scripts/build.sh [name …]` | build the `build` rows from their pinned upstream source and push. |

`REGISTRY` overrides the destination namespace (default `ghcr.io/blaktron`).
None of the scripts reads a credential; they expect `docker login ghcr.io` to
have been done, so no token appears in a command line or a log.

## Building from source

`build/` holds the images we build rather than mirror. A build context pins the
upstream **commit**, not a tag, and records the licence of what it builds.

`build/docker-agent/` is the first: Docker Agent at the commit our `1.128.0` pin
names, with the hardening we cannot apply to a vendor image — a non-root runtime
user, `DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1` baked in, and the floating
`docker/mcp-gateway:v2` in upstream's own Dockerfile replaced by our
digest-pinned gateway.

Its row in `images.tsv` still reads `mirror`. Flip it to `build` only when the
built image passes the runner's own acceptances — `scripts/acceptance/runner-r2.sh`
and `runner-r4.sh` in `agentry-cli` — because the harness is the component that
holds the model key and the conformance goldens are recorded against the vendor
image's exact event stream.

## State of play (2026-09-23)

**Mirrored and verified.** Every row of `images.tsv` is in `ghcr.io/blaktron`,
each destination digest equal to its upstream digest:

| Ours | Digest (verified equal on both sides) |
|---|---|
| `agentry-mcp-gateway:v0.43.3` | `sha256:e3ee1381…` |
| `agentry-docker-agent:1.128.0` | `sha256:50bef17d…` |
| `agentry-golang-alpine:1.27-alpine` | `sha256:8a5910f3…` |
| `agentry-alpine:3.22` | `sha256:5291449c…` |
| `agentry-node-alpine:22-alpine` | `sha256:b6f26b36…` |
| `agentry-python-alpine:3.12-alpine` | `sha256:4c47124a…` |
| `agentry-mcp-gateway-v2:v2` | `sha256:54dd518e…` |

**Docker Hub rate-limited us while doing it.** Resolving the two bases the
harness build needs — `alpine:3.23` and `golang:1.27.0-alpine3.23` — returned
`429 Too Many Requests` from `registry-1.docker.io/v2/library/…`, and still did
on a retry afterwards. That is the anonymous per-IP limit on `library/*`,
exhausted by a single mirror run on a single workstation. It is worth sitting
with: a first run of the CLI pulls five `library/*` images anonymously from
whatever IP the user happens to be on, and the estate's CI runners share one IP
each. This is not a hypothetical failure mode — it happened here, mid-task,
before anything had been published.

**Not done.**

- The harness is **not built from source yet**. `build/docker-agent/` is written
  and `scripts/build.sh` refuses to run it, correctly, naming the two bases that
  are not mirrored. Unblock it by pinning `alpine:3.23` and
  `golang:1.27.0-alpine3.23` in `images.tsv`, which needs a Hub pull that is not
  rate-limited or an authenticated one.
- **Nothing consumes these yet.** The CLI's `policy.Default*Image` constants
  still name the public refs — see "The defaults have not moved" above. The
  estate's own machines can point at these by policy today.
- **No self-hosted runner** is registered for this repository, so the workflow
  runs on `ubuntu-latest` like the estate's release workflows. The fleet has a
  runner per repository and none here.
- **The packages are private**, because this repository is. They must be public
  before any shipped default points at them.
- **No build attestations** (provenance, SBOM). `opencode`'s official image
  carries both; that is the bar to meet.
- The images are **not reduced**. The harness still carries `docker-cli` and the
  `docker-mcp` CLI plugin, neither of which a run can use — the agent container
  has no docker socket and every tool comes from our gateway. Dropping them is a
  behaviour change that needs a live run to prove, and no model key was
  available to make one.
- `scripts/build.sh` has **never completed a build**, so it is unproven beyond
  its refusal path. Its exit code and its base-resolution were verified; the
  clone-and-build path was not reached.

## Licence and attribution

The scripts, build contexts and manifest in this repository are ours, under the
licence in `LICENSE`. What we mirror and what we build from source keeps its own
licence: `NOTICE` names each component, its upstream, its licence and what we
changed. Apache-2.0 §4 asks for the licence text, retained notices and a
statement of changes; §3 grants no trademark licence, so nothing built here may
be presented as a Docker product.

Mirroring does not redistribute a modified work — the bytes are unchanged and
the digest proves it — but the terms under which a registry permits redistributing
pulled image bytes are a separate question from the licence of the software in
them, and for the components we *build* from source that question does not arise
at all. That is one more reason to move components from `mirror` to `build`.
