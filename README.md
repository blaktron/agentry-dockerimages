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
| `agentry-harness-alpine:3.23` | `sha256:85fe1e81…` |
| `agentry-harness-golang:1.27.0-alpine3.23` | `sha256:3747dcba…` |

**Built and verified.** `agentry-docker-agent-src:1.128.0`
(`sha256:8a0168668e6c…`) is the harness compiled by `build/docker-agent/` from
upstream commit `1a0e7ff…`, with all three of its bases resolved from our own
registry rather than from Docker Hub. Verified before pushing:

- the in-build `ldd` assertion passed, so the binary is static;
- `User=docker-agent` (non-root), `ENTRYPOINT [/docker-agent]`,
  `WORKDIR /work` — parity with the vendor image;
- `DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1` is baked in, which no vendor image
  carries;
- run offline under `--network none`, it prints `docker-agent version v1.128.0`
  and `Commit: 1a0e7ffbcbad4b2cbdd690f48689e87fb0c69599`, so the pinned commit
  is what was compiled, and the binary starts and links.

It is published under its **own** package name deliberately.
`agentry-docker-agent` holds the digest-verified mirror of the vendor's bytes —
the one artefact we can prove is identical to what upstream published. Pushing a
from-source build over the same tag would destroy that comparison and leave the
tag ambiguous about which of the two it named. This build is also
single-platform, the host's, where the mirror carries amd64 and arm64.

Running it confirmed two things the source reading had only suggested: it prints
*"We collect anonymous usage data to help improve docker agent. To disable:"*,
so the run plan's `TELEMETRY_ENABLED=false` is load-bearing rather than
precautionary; and it names a feedback endpoint at `docker.qualtrics.com`, one
more host the run's proxy allowlist has to be the answer to.

Two lessons from that first build, both now encoded rather than remembered. It
failed on `cgo: C compiler "gcc" not found` — the Go alpine images ship no
compiler, and upstream gets one from the `xx` toolchain this context drops, so
`gcc musl-dev` is installed explicitly. And it failed on `no space left on
device`: the volume genuinely filled, and `docker builder prune -f` reclaimed
about 12 GB. A from-source harness build needs several GB of headroom; check the
disk before starting one.

**Docker Hub rate-limited us while doing it.** Resolving the two bases the
harness build needs — `alpine:3.23` and `golang:1.27.0-alpine3.23` — returned
`429 Too Many Requests` from `registry-1.docker.io/v2/library/…`, and kept doing
so on retry. The response headers name the limit:

```
docker-ratelimit-source: <this machine's IP>
x-ratelimit-limit: 100;w=3600
```

**One hundred pulls per hour per IP, anonymously.** A single mirror run of nine
multi-arch images — each an index plus a manifest per platform — exhausts that,
which is what happened here. It cleared on its own later the same day.

Worth sitting with, because it is not only our problem: a first run of the CLI
pulls five `library/*` images anonymously from whatever IP the user happens to be
on — a shared NAT, a hotel, a university, an office behind one egress address —
and each CI runner host shares one IP across every job it runs. That is an
availability failure in the product with nothing to do with the agent, and
mirroring is what removes it: a public GHCR package has no equivalent pull quota.

The estate now has a Docker Hub account, and logging in lifts these pulls off the
anonymous bucket — 200 per hour, and not shared with every other anonymous client
behind the same address. `docker login` once and the scripts use it; none of them
reads a credential, so nothing appears in a command line or a log. The workflow
takes the same pair as `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets and warns
rather than failing when they are absent.

Note that `~/.docker/config.json` stores these base64-encoded, not encrypted,
unless a credential helper is configured — `credsStore` is unset here. On a shared
machine that file is a credential store in all but name.

**Not done.**

- **The packages are private, and this is the blocker on using any of it.** An
  anonymous manifest fetch returns `403` for every one of them, including those
  pushed *after* this repository was made public: making the repo public does not
  make the packages public, and a package created by a manual `docker push` is
  private whatever the repository says. They cannot be flipped by API with the
  tokens here — `PATCH /users/blaktron/packages/container/<name>` returns `404`,
  because every package reports `repository: null`, i.e. unlinked. Each needs a
  one-time **Package settings → link to this repository → Change visibility →
  Public**. Until then nothing shipped can point at them, and a default that did
  would mean no one could run a BriefAgent without a GHCR token.
- **Nothing consumes these yet.** The CLI's `policy.Default*Image` constants
  still name the public refs — see "The defaults have not moved" above. The
  estate's own machines can point at these by policy today, once the packages are
  readable.
- **No live run of the built harness.** It starts, reports the right version and
  commit, and is static — but it has not driven a BriefAgent. The gate before its
  `images.tsv` row flips from `mirror` to `build` is `scripts/acceptance/runner-r2.sh`
  and `runner-r4.sh` in `agentry-cli`, and those need a model key.
- **No self-hosted runner** is registered for this repository, so the workflow
  runs on `ubuntu-latest` like the estate's release workflows. Worth knowing: a
  workflow push in a *public* repository creates public packages by default, so
  routing publication through CI is also a way past the visibility problem for
  any package not yet created.
- **No build attestations** (provenance, SBOM). `opencode`'s official image
  carries both; that is the bar to meet.
- The images are **not reduced**. The harness still carries `docker-cli` and the
  `docker-mcp` CLI plugin, neither of which a run can use — the agent container
  has no docker socket and every tool comes from our gateway. Dropping them is a
  behaviour change that needs a live run to prove, not an argument.

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
