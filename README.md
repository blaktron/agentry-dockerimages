# agentry-dockerimages

The container images the Agentry QuickAgent runtime runs, published to
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
| `agentry-unsafe-kali:2026.09.30.3` | `kalilinux/kali-rolling` + `build/agentry-unsafe-kali/` | build | the base of the desktop's Unsafe Mode exec images, amd64 and arm64 ([below](#the-unsafe-mode-image)) |
| `agentry-files` (first build pending) | `alpine:3.22` + `build/agentry-files/` | build | the decoders of the runner's decode step, amd64 and arm64, signed ([below](#the-files-image)) |

Three more mirrors are needed only to build `agentry-docker-agent-src`:
`agentry-mcp-gateway-v2:v2` (`docker/mcp-gateway:v2`),
`agentry-harness-alpine:3.23` (`alpine:3.23`) and
`agentry-harness-golang:1.27.0-alpine3.23` (`golang:1.27.0-alpine3.23`).
One more is needed only to build `agentry-unsafe-kali`:
`agentry-kali-rolling:latest` (`kalilinux/kali-rolling`, pinned by digest).

`images.tsv` is the manifest: one tab-separated row per image, with our
name, the upstream ref, the upstream digest, the kind and the role. A `build`
row names our own published tag and its digest instead.

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
- `agentry-node-alpine` or `agentry-python-alpine` is pulled when a QuickAgent
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

The `unsafe-kali` workflow creates two more packages, and a package a
workflow creates in this public repository is public:

- `agentry-unsafe-kali`, which the desktop pulls when Unsafe Mode is turned
  on, so it must need no login;
- `agentry-kali-rolling`, its build-time base.

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
| `scripts/check.sh` | Checks the manifest, the scripts, the workflows, the build contexts' base refs, the Unsafe Mode image's index generator and extras list, and the files image's fixture list, with no registry and no credentials; the header lists the rules. `--self-test` breaks each rule in a copy and expects a failure. `--unsafe-image <ref>` runs a built `agentry-unsafe-kali`, asserts that every fixture command resolves, and fails when a program on the image's own PATH has no row (`CONTAINER` picks the runtime, `PLATFORM` the architecture). `--files-image <ref>` decodes every fixture inside a built `agentry-files` with no network ([below](#the-files-image)). |
| `scripts/build.sh <name>` | Builds `build/<name>/` from its pinned upstream commit, or from the context itself, with every base taken from our mirrors by tag and digest. `PUSH=1` pushes the result. A context with `PLATFORMS` is built one architecture at a time (`PLATFORM=…`, tagged `<tag>-<arch>`), and `--merge` joins them into `<tag>`; with `PART_DIGESTS` (`amd64=sha256:… arm64=sha256:…`) it joins those digests instead of the tags, refuses a tag that exists, and holds the joined index to listing exactly them. |

`REGISTRY` sets the destination (default `ghcr.io/blaktron`). The scripts read
no credentials: run `docker login ghcr.io` first, and `docker login` for
Docker Hub. Docker Hub allows 100 anonymous pulls per IP, and its sources
disagree about the window. The registry's response header says one hour
(`ratelimit-limit: 100;w=3600`), while Docker's documentation says six
hours. Both were checked on 2026-09-24. A full mirror run can exceed either.

The `ci` workflow runs `scripts/check.sh` and its self-test on every pull
request and every push to `dev` and `main`, on a GitHub-hosted runner. It
pulls no image and needs no credentials.

The `images` workflow runs the same steps, then mirrors every `mirror` row
and builds every context in `build/` except those built per architecture,
which have their own workflows (`unsafe-kali`, `files`). It is started by hand, and it
logs in to Docker Hub when the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
secrets are set.

## The Unsafe Mode image

`agentry-unsafe-kali` is the base the desktop's Unsafe Mode builds a
QuickAgent's exec image on, when that QuickAgent declares commands the
machine's exec catalogue does not carry (agentry-notes `plans/unsafe-mode.md`;
agentry-dockerimages#15). The desktop pulls it when a person turns Unsafe
Mode on; the CLI (Unsafe Mode M2) reads its two data files and installs each
declared command on top of it, one package at a time.

It is a lean Kali Linux (`kali-rolling`): `ca-certificates`, `python3` and
`python3-venv`, and no security tool. Under `/etc/agentry/unsafe/`:

- **`commands.tsv`, the command index.** Each command a Kali package puts in
  `usr/bin`, `usr/sbin`, `bin` or `sbin` (main, contrib and non-free), mapped
  to its package. It is generated at build time by
  `build/agentry-unsafe-kali/make-index.py` from Kali's `Contents-<arch>` and
  `Packages` for the image's own architecture. Each file is first held to the
  SHA-256 in Kali's `InRelease`, whose signature `apt-get update` has checked.
  A command several packages ship takes the package named like the command,
  then the one package of priority standard or higher. Then, in the finished
  image, the programs it already carries that Contents does not list
  (alternatives links such as `awk`, `which` and `pager`) or left ambiguous
  (`python3.14`) get a row naming the package that owns the file each resolves
  to, from dpkg's own lists (agentry-dockerimages#23). A program on the PATH
  that no package owns fails the build unless
  `build/agentry-unsafe-kali/base-unowned.txt` names it with a reason; only
  `policy-rc.d`, the Debian container image's service hook, is there.
- **`ambiguous.tsv`.** The commands that rule leaves undecided. They are left
  out of the index, never guessed.
- **`extras.tsv`, the extras list.** It is maintained by hand for commands no
  package puts on `PATH`, and is a closed set of two recipes: `pip <command>
  <name>==<version>` and `link <command> <package> <path>`. The build refuses
  any other shape, and a link path its package does not ship.

`build/agentry-unsafe-kali/fixture-commands.txt` holds the declared commands
of `blaktron/binary-reverse-engineer@0.1.0`, the QuickAgent that prompted
Unsafe Mode. `scripts/check.sh --unsafe-image` asserts that each resolves
through the extras list or the index. On 2026-09-30 all 16 resolved on both
architectures:

- 13 through the index;
- `analyzeHeadless` through a link from `ghidra`;
- `decompyle3` and `uncompyle6` through pip.

The index held 47,098 commands on amd64 and 46,071 on arm64.

**Publishing.** The `unsafe-kali` workflow (manual dispatch) mirrors the base,
builds each architecture natively (amd64 on `ubuntu-latest`, arm64 on
`ubuntu-24.04-arm`), runs the fixture check on each before pushing it, joins
them into one tag named for the UTC build date and the run number
(`2026.09.30.1`), and checks the joined image. It runs only from `main`, and
refuses a tag that already exists. The `agentry-unsafe-kali` row in
`images.tsv` then takes that tag and its digest. The package is public, so
the desktop pulls it without a login. The first published build was
`2026.09.30.2` (run 36710671499). The one pinned now is
`ghcr.io/blaktron/agentry-unsafe-kali:2026.09.30.3@sha256:7c3da264fd0e8420f0367fa179e6b89110fa2f86bef8850f48d5f89ae21ab869`
(run 36776537608), the first whose index also holds the base's own
programs (agentry-dockerimages#23). Its base is `kali-rolling` at the pinned
digest, with Kali's index of 2026-09-30 18:05 UTC. An anonymous manifest
fetch answered 200 the same day. On the first of each month the
workflow also runs by itself, only to report whether the Kali base has moved
since it was pinned: a red run is the reminder to re-pin.

**The monthly re-pin (D10).** Kali has no release tags and no snapshot
service, so the base is re-pinned monthly, and on demand:

1. `scripts/pin.sh` reports that `kalilinux/kali-rolling` has moved.
2. A pull request puts the new digest in the `agentry-kali-rolling` row.
3. The `unsafe-kali` workflow is dispatched.
4. A second pull request records the new image's digest in the
   `agentry-unsafe-kali` row.
5. The CLI's default follows with its own pin change.

Package versions are not frozen. Each build records what it installed, and
the CLI records what each exec image installed in the run's receipt.

**arm64 by hand.** The workstation has no arm64 emulation. arm64 is tested on
the Mac build host (`maxbookpro`, Apple silicon) with Apple's `container` CLI
(1.5.0, installed 2026-09-30):

```
container build --build-arg KALI_IMAGE=<the base by digest> -t local/agentry-unsafe-kali:arm64 build/agentry-unsafe-kali
CONTAINER=container PLATFORM=linux/arm64 scripts/check.sh --unsafe-image local/agentry-unsafe-kali:arm64
```

## The files image

`agentry-files` holds the decoders the runner's decode step runs over a run's
documents before any agent starts (agentry-notes `plans/file-handling.md` §4,
D3, D4; agentry-dockerimages#28):

| Package | Decodes | Decoder |
|---|---|---|
| `pandoc-cli` | `.docx`, `.odt`, `.epub`, `.rtf` | `pandoc --sandbox` |
| `poppler-utils` | `.pdf` | `pdftotext` |
| `tesseract-ocr`, `tesseract-ocr-data-eng` | images, English OCR | `tesseract` |

It is our mirror of `alpine:3.22`, the runner image's own runtime base, with
those packages and their dependencies (libraries and data; no setuid or
setgid file, which the check below asserts) and nothing else. `/etc/agentry/files/packages` lists
the versions apk resolved, one `name-version` a line, for the receipt.

**Why it exists.** Until it, the CLI built this image at run time with
`apk add` from Alpine's CDN, inside the run. On 2026-10-02 that fetch failed in
a production Voice Writer run, which ended with no reason given (plan §1.1).
Here the fetch happens once, in CI, retried, and the CLI pulls the result by
digest. It holds no runner binary: the CLI adds its own in an offline layer
`FROM` the pinned digest and minimizes the result to the decoders and the
runner (agentry-cli#559). The decode container still runs with no network,
every capability dropped and a read-only root (DR-39).

**The fixture check.** `scripts/check.sh --files-image <ref>` decodes each
file in `build/agentry-files/fixtures/` (eight documents and images from the
CLI's Knowledge Creator corpus) the way the CLI's decode container runs a
decoder: the decode role's argv with absolute paths, the invoking uid, no
network, every capability dropped, a read-only root, a 512 MiB `/tmp` and the
role's environment. It asserts the phrase `expect.tsv` names for each, and
fails on any setuid or setgid file in the image.

**Publishing and signing.** The `files` workflow (manual dispatch, from
`main` only):
- builds each architecture natively (amd64 on `ubuntu-latest`, arm64 on
  `ubuntu-24.04-arm`) and runs the fixture check on each before pushing it;
- hands the merge the digest each push produced, never a tag, and joins
  those digests into one tag named for the UTC build date and the run
  number, refusing a tag that already exists;
- holds the joined index to listing exactly those images, checks it by its
  digest, and signs that same digest with cosign, keyless, as the workflow
  itself, then verifies the signature before reporting the `images.tsv` row.
  A tag can be re-pointed by anything with write access to the package; a
  digest cannot, so what is signed is what was checked.

Verify a published digest with:

```
cosign verify ghcr.io/blaktron/agentry-files@<digest> \
  --certificate-identity https://github.com/blaktron/agentry-dockerimages/.github/workflows/files.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The `agentry-files` row in `images.tsv` then takes the tag and its digest, and
the CLI pins that digest; agentry-cli's CI runs the `cosign verify` above on
the pinned digest, and the sandbox hosts run it when they pre-pull the image
(the CLI itself pulls by digest only). A rebuild is a new tag and a new digest, never an
overwrite. Later milestones of the plan add Apache Tika and libarchive (M3,
agentry-dockerimages#29) and ClamAV (M5, agentry-dockerimages#30).

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
