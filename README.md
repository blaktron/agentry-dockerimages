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
| `agentry-node-alpine:24-alpine` | `node:24-alpine` | mirror | installs and runs declared npm MCP servers (the CLI's default since agentry-cli#608) |
| `agentry-node-alpine:22-alpine` | `node:22-alpine` | mirror | the same, for CLIs released before agentry-cli#608 and policies that pin it |
| `agentry-python-alpine:3.12-alpine` | `python:3.12-alpine` | mirror | installs and runs declared PyPI MCP servers |
| `agentry-docker-agent-src:1.128.0` | `github.com/docker/docker-agent` @ `v1.128.0` | build | the harness built from source (`build/docker-agent/`) |
| `agentry-unsafe-kali:2026.09.30.3` | `kalilinux/kali-rolling` + `build/agentry-unsafe-kali/` | build | the base of the desktop's Unsafe Mode exec images, amd64 and arm64 ([below](#the-unsafe-mode-image)) |
| `agentry-files:2026.10.04.3` | `alpine:3.22` + `build/agentry-files/` | build | the decoders and the malware check (clamscan) of the runner's decode step, amd64 and arm64, signed ([below](#the-files-image)) |
| `agentry-typst:2026.10.08.1` | `github.com/typst/typst` @ `v0.15.1`, patched, + the Noto fonts, the report designs' families and cmarker | build | the PDF renderer's files for `export_pdf`, files only, amd64 and arm64, signed ([below](#building-typst-from-source)) |

Three more mirrors are needed only to build `agentry-docker-agent-src`:
`agentry-mcp-gateway-v2:v2` (`docker/mcp-gateway:v2`),
`agentry-harness-alpine:3.23` (`alpine:3.23`) and
`agentry-harness-golang:1.27.0-alpine3.23` (`golang:1.27.0-alpine3.23`).
One more is needed only to build `agentry-unsafe-kali`:
`agentry-kali-rolling:latest` (`kalilinux/kali-rolling`, pinned by digest).
And one only to build `agentry-typst`: `agentry-rust-alpine:1.98.1-alpine3.22`
(`rust:1.98.1-alpine3.22`).

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

The `typst` workflow likewise creates `agentry-typst`, which the runner image
copies from and so must need no login, and its build-time base
`agentry-rust-alpine`.

## Repointing the images

The CLI's defaults are tags, not digests. An operator who wants their own
registry, or digest pins, sets them in the runner's operator policy
(`~/.agentry/runner/policy.yaml`):

```yaml
images:
  gateway: ghcr.io/blaktron/agentry-mcp-gateway:v0.43.3
  harnessDockerAgent: ghcr.io/blaktron/agentry-docker-agent:1.128.0
  goBuilder: ghcr.io/blaktron/agentry-golang-alpine:1.27-alpine
  nodeRuntime: ghcr.io/blaktron/agentry-node-alpine:24-alpine
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
| `scripts/check.sh` | Checks the manifest, the scripts, the workflows, the build contexts' base refs, the Unsafe Mode image's index generator and extras list, and the files image's fixture list, with no registry and no credentials; the header lists the rules. `--self-test` breaks each rule in a copy and expects a failure. `--unsafe-image <ref>` runs a built `agentry-unsafe-kali`, asserts that every fixture command resolves, and fails when a program on the image's own PATH has no row (`CONTAINER` picks the runtime, `PLATFORM` the architecture). `--files-image <ref>` decodes every fixture inside a built `agentry-files` with no network, and runs its clamscan against a one-signature database ([below](#the-files-image)). `--clamav-db <dir> <files-ref>` checks a real signature database with the files image ([below](#the-clamav-signature-bundle)). `--typst-image <ref>` renders the fixture report inside a built `agentry-typst` with no network, and holds an `@preview` import to failing with no network call ([below](#building-typst-from-source)). |
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
which have their own workflows (`unsafe-kali`, `files`, `typst`). It is started by hand, and it
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
| Apache Tika 3.3.2, `openjdk17-jre-headless` | the long tail, detection by content | `tika-app --detect`, `--text`, `--xml` |
| `libarchive-tools` | ZIP, TAR, 7z, RAR and other archives | `bsdtar` |
| `file` (libmagic) | fast content detection | `file --mime-type` |
| `clamav-scanner`, `clamav-libunrar` | the malware check of every input and archive member | `clamscan` |

It is our mirror of `alpine:3.22`, the runner image's own runtime base, with
those packages and their dependencies (libraries and data; no setuid or
setgid file, which the check below asserts) and nothing else. `/etc/agentry/files/packages` lists
the versions apk resolved and Tika's version, one `name-version` a line,
for the receipt. Tika's runnable jar is pinned to Apache's SHA-512 and its
wrapper bounds the heap to 512 MiB. Its upstream licence and notices stay
in the jar. The M3 amd64 local image is 262,592,296 bytes in this workstation's Docker size report. The native
publication reports 640,905,538 bytes for amd64 and 662,635,623 for arm64.

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
fails on any setuid or setgid file in the image. Tika detects the DOCX's
content type and extracts its phrase as text and XHTML. Real ZIP, TAR, 7z
and RAR fixtures are listed by bsdtar under the same containment. clamscan
runs with the decode role's argv against a one-line signature database the
check makes (the EICAR test file's MD5, ClamAV's `.hdb` format), and must
find the EICAR file and a zip of it and pass every fixture.

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

The first build is `ghcr.io/blaktron/agentry-files:2026.10.02.1@sha256:0d35fb3a5239f4571ba0d36d6619250d030bef119ee40e8f765dc3b38428b140`
(run 36997044715, 2026-10-02): both architectures decoded all eight fixtures
before their push and the joined digest again before it was signed; the
signature verified from the workstation the same day, and an anonymous
manifest fetch answered 200. Its packages: `pandoc-cli-3.6.4-r0`,
`poppler-utils-25.04.0-r0`, `tesseract-ocr-5.5.0-r2`,
`tesseract-ocr-data-eng-5.5.0-r2`.

M3's build is `agentry-files:2026.10.03.2@sha256:ee6b4f66fa2f30444cf9ffbac4acb83e4829baa6915963bdc322d547463d5ddd`
(run 37152810514, 2026-10-03). Both native architectures passed all fixture
checks, and the joined digest passed again before keyless signing and
verification. Tika is 3.3.2, Java 17.0.19, libarchive 3.8.3, libmagic 5.46.

M5's build is `agentry-files:2026.10.04.3@sha256:f8da034b365cd86c1498b041e87ee06faeb4264dfc6e25bd9c0d3013cf58a306`
(run 37244194037, 2026-10-04): amd64 `97a407f5…` and arm64 `90cc605e…`. Each
architecture, then the joined digest, passed every check, clamscan 1.4.3
included (the EICAR file and its zip found, the eight fixtures clean). The
signature verified from the workstation and an anonymous manifest fetch
answered 200. The native images report 705,495,677 bytes (amd64) and
710,570,308 (arm64).

The `agentry-files` row in `images.tsv` then takes the tag and its digest, and
the CLI pins that digest; agentry-cli's CI runs the `cosign verify` above on
the pinned digest, and the sandbox hosts run it when they pre-pull the image
(the CLI itself pulls by digest only). A rebuild is a new tag and a new digest, never an
overwrite. M3 adds Apache Tika and libarchive (agentry-dockerimages#29). M5 adds
ClamAV (agentry-dockerimages#30): `clamscan`, with no daemon and no signature
database ([below](#the-clamav-signature-bundle)). Alpine's `clamav-scanner`
depends on `freshclam`, so it is installed too, but nothing runs it: the decode
container has no network, and the CLI's decode image is minimized to its
catalogue's commands, which removes it.

## The ClamAV signature bundle

The decode container has no network, so clamscan's signatures come from
outside: `ghcr.io/blaktron/agentry-clamav-db`, which the `clamav-db` workflow
publishes every day (agentry-notes `plans/file-handling.md` §7, D15;
agentry-dockerimages#30). The CLI refreshes its copy when it is over 24 hours
old, verifies the signature below, and mounts the databases read-only into
the decode container (agentry-cli#563). Past 7 days without a newer bundle,
runs go on and the receipt says the signatures are stale.

The workflow (daily at 07:17 UTC, or dispatched by hand, from `main` only):
- runs `freshclam` from our mirror of `alpine:3.22` (the files image's own
  base and ClamAV version) into an empty directory, and keeps exactly
  `main.cvd`, `daily.cvd` and `bytecode.cvd`, Cisco Talos's signed CVDs,
  which clamscan checks again as it loads them;
- checks them with the files image `images.tsv` pins, with no network
  (`scripts/check.sh --clamav-db`): the EICAR file and its zip found, every
  fixture clean;
- pushes the three files as one OCI artifact (artifact type
  `application/vnd.blaktron.agentry.clamav-db.v1`, one layer a file, media
  type `application/vnd.clamav.cvd`, named by `org.opencontainers.image.title`),
  tagged with the UTC date and run number and refusing a tag that exists, so
  a client downloads only the layers that changed (`main.cvd`, about 89 MB,
  changes a few times a year; `daily.cvd`, about 23 MB, every day);
- signs the pushed digest with cosign, keyless, as the workflow itself,
  verifies it, and only then moves `latest` to it, so `latest` never names an
  unsigned bundle; then fetches `latest` with no credential, as the CLI does.

The bundle has no row in `images.tsv`: it is not pinned, by design, since a
pin would hold every machine to one day's signatures. Its trust is the
signature. Verify one with:

```
cosign verify ghcr.io/blaktron/agentry-clamav-db@<digest> \
  --certificate-identity https://github.com/blaktron/agentry-dockerimages/.github/workflows/clamav-db.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The signature databases are Cisco Talos's. Each CVD carries its licence, the
GNU GPL version 2, as `COPYING` inside it, and the bundle passes each CVD on
unmodified.

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

## Building Typst from source

`build/typst/` builds [Typst](https://github.com/typst/typst) `v0.15.1` at
commit `9dfd3a08500b7896045f907433cf7b4b02434fad` (Apache-2.0;
`source.env`). It is the PDF renderer of the runner's `export_pdf` (agentry-notes
`plans/scratch-and-pdf-reports.md` §5, D23 to D27; agentry-dockerimages#48).
The result, `agentry-typst`, holds only files, for agentry-cli's runner image
to `COPY --from=ghcr.io/blaktron/agentry-typst@<digest>`:

| Path | What |
|---|---|
| `/typst` | the static binary; also the entrypoint, so the checks can run the image |
| `/fonts/` | the Noto set: Sans, Serif and Mono for Latin, Greek and Cyrillic; Arabic, Hebrew, Thai, Devanagari, Bengali, Gujarati, Gurmukhi, Kannada, Malayalam, Oriya, Sinhala, Tamil, Telugu; Simplified Chinese and Korean; Symbols, Symbols 2, Math; Noto Color Emoji (COLRv1). And the report designs' fourteen families ([below](#the-report-design-families)). All OFL-1.1 |
| `/typst-packages/` | the `cmarker` package 0.1.10 (MIT), as Typst's local package directory (`preview/cmarker/0.1.10/`), for `--package-path` |
| `/licenses/` | Typst's `LICENSE` and `NOTICE`, our patch, the licence and notice files of every crate linked into the binary (`crates/`, with `crates.tsv` and `no-licence-file.tsv` for crates that ship none), the OFL text of each font source, and `fetch.tsv` |

Japanese text renders its kana from the Chinese font and its Han characters
in Chinese forms, because no Japanese or Traditional Chinese font is bundled.
A template's font list should put `Noto Color Emoji` straight after its
text font. Typst takes each character from the first family in the list that
has a glyph for it, and the CJK and symbol fonts also draw some emoji (⚠
U+26A0, 🔒 U+1F512), in monochrome. Noto Sans covers the digits and marks
that the emoji font also has, so those never fall through to it. The fixture
template does this.

The first local amd64 build on 2026-10-08 held a 40,204,288-byte binary.
Upstream's own release binary is 55.7 MB, with its downloader and embedded
fonts. The rest is 45 font files (about 42 MB) and cmarker (340 KB). The
published images report 87,356,748 bytes (amd64) and 81,437,396 (arm64).

The first build is `ghcr.io/blaktron/agentry-typst:2026.10.08.1@sha256:37eb0ef5b52af3abd4635f249fa06e6aab4a13626abda482d40bdfe9a38828b9`
(run 37784329814, 2026-10-08): amd64 `d0fe82c2…` and arm64 `027b84c3…`.
Each architecture, then the joined digest, passed every `--typst-image`
check. arm64's binary is statically linked; amd64's is static-pie. 311 crates
are linked into the binary, and 12 of them ship no licence file. The run's
amd64 PNG pages are byte-identical to the local build's. The signature
verified from the workstation, and an anonymous manifest fetch of
`agentry-typst` and `agentry-rust-alpine` answered 200 the same day.

**Without its package downloader (D26).** Typst's cargo features cannot
remove the downloader. typst-cli turns typst-kit's `system-downloader` (ureq,
native-tls, OpenSSL) on unconditionally, and always builds the Universe
package source, so an `@preview` import that is not in the package directory
is fetched from `packages.typst.org`. Checked at v0.15.1, where the upstream
binary under `--network none` sent a DNS query before failing. Its features
cover only `embedded-fonts` and `http-server` (the defaults) and
`self-update`. So:

- the build uses `--no-default-features`: no HTTP server and no embedded
  fonts, since the fonts are the bundled set;
- `disable-package-downloads.patch` (the operator's decision, 2026-10-08):
  - removes `system-downloader` and the `vendor-openssl` feature from
    typst-cli;
  - replaces its downloader with one that refuses every request with
    "package downloads are disabled".

  It touches two files, `crates/typst-cli/Cargo.toml` and
  `crates/typst-cli/src/download.rs`.

The patch is applied with no fuzz. The build fails if the binary's
dependency list (`cargo tree`, normal dependencies) does not name typst-cli
and typst-kit, or names a network client (the list is in the Dockerfile:
ureq, native-tls, OpenSSL, rustls, hyper, reqwest, curl and others). It also
fails if the binary needs a shared library or an interpreter. **Re-check the
patch at every Typst tag bump.** It must still apply, the build's dependency
check must pass, and `scripts/check.sh --typst-image` must still pass.

**The fonts and the package** are fetched by `build/typst/fetch.sh` from the
URLs in `build/typst/fetch.tsv`, each at a pinned commit. A file whose SHA-256
differs fails the build. The sources:

- the Noto project's published builds, `notofonts/notofonts.github.io`;
- `notofonts/noto-cjk`, for the CJK region subsets;
- `googlefonts/noto-emoji` at `v2.051`;
- `google/fonts`, for the report designs' families
  ([below](#the-report-design-families));
- `typst/packages`, for cmarker.

The licence column of `fetch.tsv` names each file's licence, and
`licenses/fonts/` holds the OFL text of every font source repository.
cmarker's own default for `raw-typst` is `true`. The runner's template must
pass `raw-typst: false`, so the Markdown never injects Typst code; that is
the template's job (agentry-cli, M3). The check's fixture template does the
same.

### The report design families

The report designs (agentry-notes `plans/report-designs.md`, D3 and D13;
agentry-dockerimages#58) set their headings, body and code in one of fourteen
open-licence families, with Noto behind each for the scripts it lacks:

- sans: Inter, IBM Plex Sans, Source Sans 3, Work Sans, Montserrat (headings);
- serif: Source Serif 4, Lora, Merriweather, IBM Plex Serif, EB Garamond,
  Playfair Display (headings);
- mono: IBM Plex Mono, JetBrains Mono, Source Code Pro.

All come from `google/fonts` at one pinned commit (`62e55e58`, 2026-10-09),
Google Fonts' published build of each family, under OFL-1.1 with the
`OFL.txt` of each family's directory in `/licenses/fonts/`. That is one source
for all fourteen, and its family names are the ones the site's editor uses for
its web-font preview. Upstream's own repositories do not all commit a TTF: Inter's ships
its static faces only as WOFF2, which Typst does not read, and Playfair
Display's repository now holds its successor. Twelve families ship there only
as a variable roman and a variable italic, which `fetch.tsv` saves as
`*-Variable.ttf`. They carry every weight, and Typst 0.15.1 instances them,
in the PDF as well as the PNG: checked by rasterising the PDF with poppler,
not only Typst's own PNG. A variable family's PDF font name is still its
default instance's (`Montserrat-Thin`, `SourceCodePro-ExtraLight`), which is
only the name. IBM Plex Serif and IBM Plex Mono ship static there, and take
Regular, Italic, Bold and Bold Italic. Together they add 32 font files, about
22 MB; Merriweather's three axes make it 9 MB of that.

`fixtures/fonts.txt` lists the families after Noto's, and every family there
whose name does not start with "Noto" is a design family. The check renders
`fixtures/families.typ` once with all of them. Each family gets a block of
regular, bold, italic and bold italic text, with a line of Chinese, Arabic and
Hindi behind it. The check fails on an "unknown font family" warning, since
Typst would otherwise set the text in the next family without failing. It
also fails unless the PDF is tagged PDF/UA-1 and embeds every design family
and Noto's SC, Arabic and Devanagari fonts.

**The check.** `scripts/check.sh --typst-image <ref>` runs the image the way
`export_pdf` will. The container has no network, every capability dropped, a
read-only root and the invoking uid, with only the bundled fonts and
packages (`--ignore-system-fonts --font-path /fonts --package-path
/typst-packages`). The check:

1. asserts that `typst fonts` lists every family in
   `build/typst/fixtures/fonts.txt`;
2. renders `build/typst/fixtures/report.typ` with `--pdf-standard ua-1` to a
   PDF that must carry a structure tree and the PDF/UA identification. The
   report is the 2026-10-08 prototype's sample: Chinese, Arabic RTL, Hindi,
   emoji, a table, code, a local image, a long unbreakable token. It adds a
   line each of Hebrew, Thai, Korean, Japanese, Bengali, Tamil, Telugu, Greek,
   Cyrillic and symbols;
3. renders the same report to PNG pages, which land in `$OUT_DIR` for a
   person to look at;
4. compiles `fixtures/import.typ`, which imports `@preview/whatever:0.1.0`.
   It must fail with "package downloads are disabled";
5. runs that import and the report again under `strace -e
   trace=%network,execve`, in a helper built from our `agentry-alpine` mirror
   with `strace`, `file` and the image's files. Building the helper needs
   network; the traced runs have none. The check fails on any network system
   call, if the traced import does not reach the refusing downloader, if the
   traced report does not render, and unless `file` calls `/typst` static.
   Against the upstream binary, the same trace shows its DNS query to port 53.

**Publishing and signing.** The `typst` workflow publishes the image as the
`files` workflow publishes `agentry-files` (manual dispatch, from `main`
only). Its `prepare` job also mirrors the builder base, `agentry-rust-alpine`
(`rust:1.98.1-alpine3.22` by digest), so a workflow creates that package and
it is public. The workflow:

- builds amd64 and arm64 natively;
- runs the check on each before pushing it, and keeps the PDF and PNG pages
  as a run artifact;
- joins the pushed digests into one tag named for the UTC date and the run
  number;
- checks that digest again, then signs it with cosign, keyless, and
  verifies the signature.

Verify a published digest with:

```
cosign verify ghcr.io/blaktron/agentry-typst@<digest> \
  --certificate-identity https://github.com/blaktron/agentry-dockerimages/.github/workflows/typst.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

`scripts/build.sh` passes an upstream context's own directory to the build as
the named context `agentry`. That is how the patch, `fetch.tsv` and
`fetch.sh` reach the Dockerfile without being mixed into Typst's tree. A
local build needs several GB of disk; on 2026-10-08 the release build took
12 minutes on the 8-core workstation.

## Licence

The scripts, build contexts and manifest are MIT-licensed (`LICENSE`). Mirrored
and built images keep their own licences; `NOTICE` lists each one and the
changes we make to Docker Agent, which is Apache-2.0. Nothing built here is a
Docker product.
