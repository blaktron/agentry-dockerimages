# agentry-dockerimages

The container images the Agentry BriefAgent runtime runs, published to
`ghcr.io/blaktron`. Each image is either a mirror of an upstream image, copied
unchanged and pinned by digest, or built here from a pinned upstream commit.

## Images

| Image | Upstream | Kind | Used for |
|---|---|---|---|
| `agentry-mcp-gateway:v0.43.3` | `docker/mcp-gateway:v0.43.3` | mirror | the MCP gateway, the run's tool plane |
| `agentry-docker-agent:1.128.0` | `docker/docker-agent:1.128.0` | mirror | the default agent harness |
| `agentry-golang-alpine:1.27-alpine` | `golang:1.27-alpine` | mirror | builds the runner image |
| `agentry-alpine:3.22` | `alpine:3.22` | mirror | the runner image's runtime base |
| `agentry-node-alpine:22-alpine` | `node:22-alpine` | mirror | installs and runs declared npm MCP servers |
| `agentry-python-alpine:3.12-alpine` | `python:3.12-alpine` | mirror | installs and runs declared PyPI MCP servers |
| `agentry-docker-agent-src:1.128.0` | `github.com/docker/docker-agent` @ `v1.128.0` | build | the harness built from source (`build/docker-agent/`) |

Three more mirrors are needed only to build `agentry-docker-agent-src`:
`agentry-mcp-gateway-v2:v2` (`docker/mcp-gateway:v2`),
`agentry-harness-alpine:3.23` (`alpine:3.23`) and
`agentry-harness-golang:1.27.0-alpine3.23` (`golang:1.27.0-alpine3.23`).

`images.tsv` is the manifest: one tab-separated row per mirrored image, with
our name, the upstream ref, the upstream digest, the kind and the role.

The Agentry server's own images (Postgres, MinIO, Redis, the edge, authentik,
OpenSearch, `secureagentryd`) are not here. Neither are the runner image and
the per-release exec and MCP-server images: the CLI builds those locally on
the machine that runs them.

## Digests

`scripts/mirror.sh` copies each manifest registry to registry with
`docker buildx imagetools create`, so a mirrored image keeps the upstream
digest and every platform in its manifest list. The script checks the
destination digest after each copy and fails if it differs. Pin by digest:

```
ghcr.io/blaktron/agentry-alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
```

## Who pulls these

Since 2026-09-23 the Agentry CLI's built-in defaults name these images
(agentry-cli#231, recorded as register entry DR-32), so an ordinary
`agentry run` uses them with nothing to configure:

- The runner image is built on `agentry-golang-alpine` and `agentry-alpine`.
- The gateway is pulled.
- `agentry-docker-agent` is pulled when the default harness is used.
- `agentry-node-alpine` or `agentry-python-alpine` is pulled when a BriefAgent
  declares npm or PyPI MCP servers.

The desktop app and Agentry's hosted runs use the same defaults, but they
move later:

- The desktop embeds a pinned version of the CLI's code and moves when that
  pin is bumped.
- Hosted runs move when their installed CLI is updated.

The defaults moved off Docker Hub for two reasons:

- Docker Hub limits anonymous pulls, and a first run pulls at least four
  images from whatever address the user is on.
- The harness holds the model API key, and it arrived by a tag that only its
  vendor controlled.

The tags here are ours, and each was verified against the upstream digest
when it was mirrored. They are still tags (see "Repointing the images").

The CLI moved on 2026-09-23, once the six packages below were public.

## Public and private packages

Six packages are public, so pulling them needs no login. These are the ones a
run pulls:

- `agentry-mcp-gateway`
- `agentry-docker-agent`
- `agentry-golang-alpine`
- `agentry-alpine`
- `agentry-node-alpine`
- `agentry-python-alpine`

Four packages are private:

- `agentry-mcp-gateway-v2`, `agentry-harness-alpine` and
  `agentry-harness-golang`, the build-time bases of `build/docker-agent/`
- `agentry-docker-agent-src`, that build's output, which nothing uses yet

A run never pulls these four. Building `build/docker-agent/` needs a
`docker login ghcr.io` with read access.

Both groups were checked with an anonymous manifest fetch on 2026-09-24.

## Repointing the images

The CLI's defaults are tags, not digests. An operator who wants their own
registry, or digest pins, sets them in the runner's operator policy
(`~/.agentry/runner/policy.yaml`):

```yaml
images:
  gateway: ghcr.io/blaktron/agentry-mcp-gateway:v0.43.3
  harnessDockerAgent: ghcr.io/blaktron/agentry-docker-agent:1.128.0
  goBuilder: ghcr.io/blaktron/agentry-golang-alpine:1.27-alpine
  nodeRuntime: ghcr.io/blaktron/agentry-node-alpine:22-alpine
  pythonRuntime: ghcr.io/blaktron/agentry-python-alpine:3.12-alpine
```

To pin by digest, append `@sha256:…` from `images.tsv` to each ref.

The runner image's two bases are set differently. `goBuilder` becomes the
`GO_IMAGE` build argument of the CLI's `runnerimage/Dockerfile`.
`agentry-alpine` is that Dockerfile's `RUNTIME_IMAGE` argument, and it has no
policy field. The CLI passes only `GO_IMAGE` when it builds, so the runtime
base is the default built into the CLI and cannot be changed from
`policy.yaml`.

## Scripts

| Script | What it does |
|---|---|
| `scripts/pin.sh` | Resolves every upstream ref and reports the tags whose digest has moved or that no longer resolve. It does not edit `images.tsv`. |
| `scripts/mirror.sh [name …]` | Copies the `mirror` rows to `$REGISTRY` by digest and verifies each destination digest. |
| `scripts/check.sh` | Checks the manifest, the scripts, the workflows and the build contexts' base refs, with no registry and no credentials; the header lists the rules. `--self-test` breaks each rule in a copy and expects a failure. |
| `scripts/build.sh <name>` | Builds `build/<name>/` from its pinned upstream commit, with every base taken from our mirrors. `PUSH=1` pushes the result. |

`REGISTRY` sets the destination (default `ghcr.io/blaktron`). The scripts read
no credentials: run `docker login ghcr.io` first, and `docker login` for
Docker Hub. Docker Hub allows 100 anonymous pulls per IP, and its sources
disagree about the window. The registry's response header says one hour
(`ratelimit-limit: 100;w=3600`), while Docker's documentation says six
hours. Both were checked on 2026-09-24. A full mirror run can exceed either.

The `ci` workflow runs `scripts/check.sh` and its self-test on every pull
request and every push to `dev` and `main`, on a GitHub-hosted runner. It
pulls no image and needs no credentials.

The `images` workflow runs the same steps. It is started by hand, and it logs
in to Docker Hub when the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets
are set.

## Building Docker Agent from source

`build/docker-agent/` builds Docker Agent `v1.128.0` at commit
`1a0e7ffbcbad4b2cbdd690f48689e87fb0c69599` (`source.env`).
`upstream.Dockerfile` is the vendor's Dockerfile at that commit, for
comparison. Our Dockerfile differs from it in four ways:

1. Every base comes from our digest-pinned mirrors.
2. The `docker-mcp` plugin is copied from a pinned digest instead of the
   floating `docker/mcp-gateway:v2`.
3. `DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1` is set.
4. It builds Linux only, without upstream's cross-compilation stages. The
   binary is still checked to be statically linked.

The result is published as `agentry-docker-agent-src`, separate from the
`agentry-docker-agent` mirror, so the two can be compared. It is built for the
build host's platform only, while the mirror has linux/amd64 and linux/arm64.
A build needs several GB of free disk. It replaces the mirror only after it
passes the CLI's live runner acceptance tests; the `agentry-docker-agent` row
in `images.tsv` then changes from `mirror` to `build`.

## Licence

The scripts, build contexts and manifest are MIT-licensed (`LICENSE`). Mirrored
and built images keep their own licences; `NOTICE` lists each one and the
changes we make to Docker Agent, which is Apache-2.0. Nothing built here is a
Docker product.
