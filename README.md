# agentry-dockerimages

The container images the Agentry runner uses, published to
`ghcr.io/blaktron`. Each image is either a mirror of an upstream image, copied
unchanged and pinned by digest, or built here from pinned upstream source or
from a build context in this repository. This repository holds the manifest of
those images, the scripts that mirror, build and check them, and the
workflows that publish and sign them.

What each image does inside a run is documented with the runner:
<https://docs.secureagentry.net/runner/>.

## Layout

| Path | What it holds |
|---|---|
| `images.tsv` | The manifest: one tab-separated row per image, `name`, upstream ref, digest, kind (`mirror` or `build`) and role. Every upstream ref is pinned by digest. A `build` row names our own published tag and that tag's manifest digest. |
| `build/<name>/` | One build context per built image: a `Dockerfile`, `source.env` (what is built and from which pinned commit, release or tag), `bases.env` (the base images, which must have rows in `images.tsv`) and the files that build needs. |
| `scripts/mirror.sh` | Copies the `mirror` rows into the registry by digest. |
| `scripts/pin.sh` | Reports upstream tags whose digest has moved. |
| `scripts/build.sh` | Builds a context in `build/`. |
| `scripts/check.sh` | Checks the repository, and checks built images. |
| `.github/workflows/` | `ci` (checks), `images` (mirror and simple builds), and one publishing workflow per image that is built per architecture and signed. |
| `NOTICE`, `LICENSE` | Licences, see the end of this file. |

The Agentry server's own images (Postgres, Redis, the edge, authentik,
OpenSearch, `secureagentryd`) are not here, with one exception: the object
store of the headless compose stack, `agentry-minio`, whose publisher serves
only a `latest` tag and does not promise an older digest stays pullable, so
the compose file pins our copy instead. Neither are the runner
image and the per-release exec and MCP-server images: the CLI builds those
locally on the machine that runs them.

## Images

Mirrors keep the upstream digest and every platform of the upstream manifest
list. Built images are listed with what they are built from.

| Image | Source | Kind | What it is for |
|---|---|---|---|
| `agentry-mcp-gateway` | `docker/mcp-gateway` | mirror | The MCP gateway, started once per run: the run's tool plane. |
| `agentry-docker-agent` | `docker/docker-agent` | mirror | The vendor's harness image, byte for byte, the default before the build from source; kept for comparison and for policies that pin it. |
| `agentry-golang-alpine` | `golang:1.27-alpine` | mirror | Builds the runner image. |
| `agentry-alpine` | `alpine:3.24` | mirror | The runner image's runtime base, and the base of the files and host link images. |
| `agentry-node-alpine` | `node:22-alpine`, `node:24-alpine`, `node:26-alpine` | mirror | Installs and runs the npm MCP servers a QuickAgent declares. |
| `agentry-python-slim` | `python:3.14-slim-trixie` | mirror | Installs and runs the PyPI MCP servers a QuickAgent declares (the default). Debian's glibc, so packages that publish only manylinux wheels install. |
| `agentry-python-alpine` | `python:3.14-alpine` | mirror | The same on Alpine's musl, for runner policies that pin it. |
| `agentry-unsafe-kali` | `kalilinux/kali-rolling` + `build/agentry-unsafe-kali/` | build | The base of the desktop's Unsafe Mode exec images, amd64 and arm64. |
| `agentry-files` | `alpine:3.24` + `build/agentry-files/` | build | The decoders of the runner's file decode step (pandoc, pdftotext, tesseract, Tika, bsdtar, libmagic) and its malware check (clamscan), amd64 and arm64. |
| `agentry-typst` | Typst, patched, plus the Noto fonts, the report designs' font families and the cmarker package (`build/typst/`) | build | The PDF renderer's files for `export_pdf`, files only, amd64 and arm64. |
| `agentry-codex` | OpenAI's Codex CLI release binary on `alpine:3.24` (`build/agentry-codex/`) | build | The Codex harness image, used for a ChatGPT model sign-in, amd64 and arm64. |
| `agentry-hostlink` | `alpine:3.24` + OpenSSH client (`build/agentry-hostlink/`) | build | The OpenSSH client the runner's host link reaches a target host with, amd64 and arm64. |
| `agentry-ripgrep` | ripgrep (`build/ripgrep/`) | build | The search engine for the tools server's `grep` and `glob`, files only, amd64 and arm64. |
| `agentry-browser` | `debian:trixie-slim` + `@playwright/mcp` + Debian's Chromium (`build/agentry-browser/`) | build | The browser server for a QuickAgent that declares `capabilities.browser`, amd64 and arm64. |
| `agentry-coder` | `debian:trixie-slim` + Debian's build tools and Python + Go + Node + the git hosts' CLIs and two scanners (`build/agentry-coder/`) | build | The Coding agent's toolchain, the image its exec container is built from, amd64 and arm64. |
| `agentry-gog` | gog built from source (`build/gog/`) | build | The Google Workspace MCP server (`gog mcp`), amd64 and arm64, signed. |
| `agentry-ms365` | Softeria's ms-365-mcp-server built from source (`build/ms365/`) | build | The Microsoft 365 and Outlook.com MCP server, its token cache sealed under a key the runner gives it, amd64 and arm64, signed. |
| `agentry-docker-agent-src` | `docker/docker-agent` built from source (`build/docker-agent/`) | build | The default harness: Docker Agent built from a pinned commit with its cold-cache clear patch, amd64 and arm64, signed. Published beside the mirror so the two can be compared. |
| `agentry-minio` | `cgr.dev/chainguard/minio:latest` | mirror | The object store of the core's headless compose stack: MinIO, AGPL-3.0 (see `NOTICE` for its source). Not used by a run. |

Mirrors used only as bases when building:

| Image | Source | Used by |
|---|---|---|
| `agentry-mcp-gateway-v2` | `docker/mcp-gateway:v2` | `build/docker-agent/`: the `docker-mcp` CLI plugin is copied from this digest. |
| `agentry-harness-alpine` | `alpine:3.24` | `build/docker-agent/` and `build/gog/`: runtime base. |
| `agentry-harness-golang` | `golang:1.27.3-alpine3.24` | `build/docker-agent/` and `build/gog/`: compiler. |
| `agentry-kali-rolling` | `kalilinux/kali-rolling` | `build/agentry-unsafe-kali/`: base. |
| `agentry-rust-alpine` | `rust:1.99.1-alpine3.24` | `build/typst/` and `build/ripgrep/`: compiler, on the same Alpine as the runner image. |
| `agentry-cosign` | `ghcr.io/sigstore/cosign/cosign` | `build/agentry-codex/`: verifies OpenAI's signature on the Codex binary. |
| `agentry-debian` | `debian:trixie-slim` | `build/agentry-browser/` and `build/agentry-coder/`: base. |
| `agentry-node-bookworm` | `node:24-bookworm-slim` | `build/agentry-browser/`: installs `@playwright/mcp` from its lockfile and supplies the image's `node`. `build/agentry-coder/`: supplies `node` and npm. |
| `agentry-golang-trixie` | `golang:1.27.3-trixie` | `build/agentry-coder/`: supplies `/usr/local/go`. |

Packages that the publishing workflows create in this public repository are
public, so the images a run pulls need no registry login. The build-time
bases of `build/docker-agent/` and its output are not pulled by a run;
building that context needs a `docker login ghcr.io` with read access.

Each image is referenced by digest, for example:

```
ghcr.io/blaktron/agentry-alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
```

The runner's operator policy can point these at another registry or pin them
by digest; see the runner documentation.

## Prerequisites

- Docker with `buildx` (`docker buildx imagetools` copies manifests between
  registries without pulling layers).
- `bash`, `git`, `python3` with PyYAML, and `shellcheck`, for
  `scripts/check.sh`.
- For mirroring or pushing: `docker login ghcr.io` with a token that can write
  packages in the namespace. The scripts read no credential themselves.
  `REGISTRY` sets the destination (default `ghcr.io/blaktron`) and `MANIFEST`
  the manifest file (default `images.tsv`).
- Docker Hub allows only a limited number of anonymous pulls per IP, which a
  full mirror run can exceed; `docker login` to Docker Hub first.
- For the image checks: a container runtime. `--codex-image` also needs
  `cosign`, `file` and network access to Sigstore.
- Building a context from upstream source needs `git` and network access to
  the upstream repository, and several GB of free disk.

## Mirror, pin, build and check

**Check the repository** (no registry, no credentials, nothing pulled):

```
scripts/check.sh               # manifest, scripts, workflows, build contexts
scripts/check.sh --self-test   # break each rule in a copy and expect a failure
```

The header of `scripts/check.sh` lists every rule. The `ci` workflow runs both
commands on each pull request and on each push to `dev` and `main`.

**Report moved upstream tags:**

```
scripts/pin.sh
```

It resolves every ref in `images.tsv` and prints `ok` or `MOVED` with the
pinned and current digest. It never edits the manifest. A moved tag changes
nothing that is published, because mirroring copies by digest.

**Mirror:**

```
scripts/mirror.sh              # every mirror row
scripts/mirror.sh <name> ...   # only these names
```

Each `mirror` row is copied with `docker buildx imagetools create` to
`$REGISTRY/<name>:<tag>`, and the destination digest is read back and must
equal the pinned digest.

**Build:**

```
scripts/build.sh <name>                  # build build/<name>/, do not push
PUSH=1 scripts/build.sh <name>           # build and push to $REGISTRY
```

`scripts/build.sh` refuses to build when a base named in `bases.env` has no
row in `images.tsv`: each base is passed to the build as our mirror's tag and
pinned digest together. A context's `source.env` sets `IMAGE_NAME` and
`IMAGE_TAG`, and for a build from upstream source `UPSTREAM_REPO`,
`UPSTREAM_COMMIT` and `UPSTREAM_TAG`: the script clones that commit and passes
the context directory to the build as the named build context `agentry`
(patches and fetch lists reach the Dockerfile that way). `IMAGE_TAG` from the
environment overrides `source.env`.

A context with `PLATFORMS` in `source.env` is built one architecture at a
time, each natively:

```
PLATFORM=linux/arm64 IMAGE_TAG=<tag> PUSH=1 scripts/build.sh <name>   # pushes <tag>-arm64
IMAGE_TAG=<tag> scripts/build.sh --merge <name>                       # joins <tag>-<arch> into <tag>
PART_DIGESTS='amd64=sha256:... arm64=sha256:...' IMAGE_TAG=<tag> scripts/build.sh --merge <name>
```

With `PART_DIGESTS`, `--merge` joins exactly those digests instead of the
tags, refuses an `IMAGE_TAG` that already exists, and checks that the joined
index lists exactly the given images.

**Check a built image.** Each built image has a check that runs it the way the
runner does (no network, every capability dropped, read-only root where the
runner uses one) and asserts what it holds:

```
scripts/check.sh --unsafe-image <ref>     # CONTAINER=<runtime> PLATFORM=<os/arch> pick runtime and architecture
scripts/check.sh --files-image <ref>
scripts/check.sh --clamav-db <dir> <files-ref>
scripts/check.sh --typst-image <ref>
scripts/check.sh --codex-image <ref>
scripts/check.sh --hostlink-image <ref>
scripts/check.sh --ripgrep-image <ref>
scripts/check.sh --browser-image <ref>
scripts/check.sh --coder-image <ref>
```

`PLATFORM` (for example `linux/arm64`) asks for, and checks, one
architecture.

## Adding an image or moving a pin

**Move a mirror's pin.** Run `scripts/pin.sh`, review what changed upstream,
edit the digest in `images.tsv` by hand, run `scripts/check.sh`, then run
`scripts/mirror.sh <name>`. The `images` workflow does the same from
`workflow_dispatch`; its `names` input restricts it to the named rows and
builds nothing.

**Add a mirror.** Add a row with kind `mirror`: our name, the upstream ref,
its digest (`docker buildx imagetools inspect <ref> --format
'{{.Manifest.Digest}}'`), and a role. Run `scripts/check.sh`, then
`scripts/mirror.sh <name>`.

**Add a built image.**

1. Create `build/<name>/` with a `Dockerfile`, `source.env` and `bases.env`.
2. Give every base in `bases.env` a `mirror` row in `images.tsv` and mirror it.
3. Add a `build` row for the image once it is published; its digest is the
   manifest digest of the published tag.
4. Add a check to `scripts/check.sh` for the image's contents, and a workflow
   for a per-architecture, signed image (copy the closest existing one).
5. Add the licences to `NOTICE`.

A published tag is never overwritten: a rebuild is a new tag and a new digest.

## Publishing and signing

The `images` workflow (manual dispatch) runs the repository check, reports
moved tags, mirrors every `mirror` row (or the named ones) and builds every
context that has no `PLATFORMS`.

Each built image that has `PLATFORMS` has a workflow of its own: `unsafe-kali`,
`files`, `typst`, `codex`, `hostlink`, `ripgrep`, `browser`, `coder`, `docker-agent` and `gog`. They are
dispatched by hand and refuse to run from any branch but `main`. Each:

- mirrors its build-time base by digest, so the package exists and is public
  before a build pulls it;
- builds amd64 on `ubuntu-latest` and arm64 on `ubuntu-24.04-arm`, natively,
  and runs the image's check on each before pushing it;
- joins the architectures into one tag named for the UTC date and the run
  number, refusing a tag that exists, and checks the joined image;
- writes the `images.tsv` row to the run's summary. A person then puts the row
  in `images.tsv`.

All of them except `unsafe-kali` also hand the merge the digest each push
produced (never a tag), hold the joined index to listing exactly those images,
sign the joined digest with cosign, keyless, as the workflow itself
(`id-token: write` is granted to that job alone), verify the signature, and
print the verify command in the run's summary.

Verify a published digest, with the workflow named for the image (`files`,
`typst`, `codex`, `hostlink`, `ripgrep`, `browser`, `coder`, `docker-agent` or `gog`):

```
cosign verify ghcr.io/blaktron/agentry-<image>@<digest> \
  --certificate-identity https://github.com/blaktron/agentry-dockerimages/.github/workflows/<workflow>.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The `clamav-db` workflow publishes the ClamAV signature bundle
`ghcr.io/blaktron/agentry-clamav-db` daily (07:17 UTC) and on dispatch, always
from `main`: the scheduled run starts on the default branch and only dispatches
the workflow on `main`, whose run publishes. It
has no row in `images.tsv`, because a pin would hold every machine to one
day's signatures; its trust is the signature. Verify it the same way, with
`clamav-db.yaml` as the workflow.

## Per-image build notes

The header of `scripts/check.sh` lists what each image check asserts.

### agentry-unsafe-kali

A lean Kali Linux (`kali-rolling`) with `ca-certificates`, `python3` and
`python3-venv`, and no security tool. Under `/etc/agentry/unsafe/` it holds
`commands.tsv`, an index of each command a Kali package ships in `usr/bin`,
`usr/sbin`, `bin` or `sbin`, mapped to its package; `ambiguous.tsv`, the
commands the index rules leave undecided (never guessed); and `extras.tsv`,
maintained by hand, a closed set of two recipes (`pip <command>
<name>==<version>` and `link <command> <package> <path>`) for commands no
package puts on `PATH`. `build/agentry-unsafe-kali/make-index.py` generates
the index at build time from Kali's `Contents-<arch>` and `Packages`, each file
held to the SHA-256 in `InRelease`. A program on the `PATH` that no package
owns fails the build unless `base-unowned.txt` names it with a reason.
`fixture-commands.txt` lists commands that must resolve; `--unsafe-image`
asserts it.

Kali has no release tags and no snapshot service, so the base is re-pinned by
hand. The monthly scheduled `unsafe-kali` run only reports whether the base has
moved (a red run is the reminder) and builds nothing. To re-pin: `scripts/pin.sh`
reports the move; put the new digest in the `agentry-kali-rolling` row;
dispatch the `unsafe-kali` workflow; record the new image's digest in the
`agentry-unsafe-kali` row.

arm64 can be tested without emulation on an Apple-silicon machine with Apple's
`container` CLI:

```
container build --build-arg KALI_IMAGE=<the base by digest> -t local/agentry-unsafe-kali:arm64 build/agentry-unsafe-kali
CONTAINER=container PLATFORM=linux/arm64 scripts/check.sh --unsafe-image local/agentry-unsafe-kali:arm64
```

Unsafe Mode is described at <https://docs.secureagentry.net/agentry/unsafe-mode/>.

### agentry-files

`alpine:3.24` with `pandoc-cli`, `poppler-utils`, `tesseract-ocr` with English
data, Apache Tika (with `openjdk17-jre-headless`), `libarchive-tools`, `file`
(libmagic) and `clamav-scanner` with `clamav-libunrar`, and their dependencies.
There is no setuid or setgid file. `/etc/agentry/files/packages` lists the
resolved versions. Tika's jar is pinned to Apache's SHA-512 and its wrapper
bounds the heap to 512 MiB. The image holds no runner binary and no signature
database; `clamscan` runs with no daemon, and `freshclam` is installed only
because Alpine's package depends on it. `build/agentry-files/fixtures/` holds
the documents and images the check decodes, and `expect.tsv` the phrase each
must yield.

The decode step and the malware checks are described at
<https://docs.secureagentry.net/runner/#running-with-files> and
<https://docs.secureagentry.net/runner/#the-malware-checks>.

### The ClamAV signature bundle

The decode container has no network, so clamscan's signatures come from
`ghcr.io/blaktron/agentry-clamav-db`. The `clamav-db` workflow runs
`freshclam` from the `alpine:3.24` mirror into an empty directory, keeps
exactly `main.cvd`, `daily.cvd` and `bytecode.cvd` (Cisco Talos's signed
CVDs, which clamscan checks again as it loads them), checks them with the
pinned files image and no network (`scripts/check.sh --clamav-db`), and pushes
them as one OCI artifact (artifact type
`application/vnd.blaktron.agentry.clamav-db.v1`, one layer per file, media type
`application/vnd.clamav.cvd`) tagged with the UTC date and run number. It signs
the pushed digest, verifies it, and only then moves `latest`, so `latest` never
names an unsigned bundle. Each CVD carries its licence, the GNU GPL version 2,
as `COPYING` inside it, and the bundle passes each CVD on unmodified.

### agentry-codex

Nothing is compiled. `build/agentry-codex/` puts OpenAI's release binary
(`codex-<arch>-unknown-linux-musl` from the GitHub release `CODEX_TAG` in
`source.env`), unmodified, on the `alpine:3.24` mirror, running as uid 10001.
The fetch stage (`fetch.sh`) holds the tarball to its SHA-256; verifies the
binary against OpenAI's `.sigstore` bundle with `verify.sh` (signer: OpenAI's
`rust-release.yml` at `refs/tags/<CODEX_TAG>`, run at `CODEX_COMMIT`); proves
on every build that the verifier refuses a changed byte, another tag's identity
and another commit; and fetches `LICENSE` and `NOTICE`, each held to its
SHA-256. The cosign that verifies is Sigstore's own image (`agentry-cosign`),
whose signature the `codex` workflow checks before it mirrors it. The binary
is `/usr/local/bin/codex`; `/etc/agentry/codex/` holds the release record and
the bundle, so it can be verified again. `CODEX_HOME` is `/home/codex`, a tmpfs
over the runner's read-only root.

To bump Codex: set `CODEX_VERSION`, `CODEX_TAG`, `CODEX_COMMIT`,
`CODEX_SHA256_AMD64`, `CODEX_SHA256_ARM64` (and the licence hashes if they
changed) in `source.env`, update the release line in `NOTICE`, run
`--codex-image` on a local build, and dispatch the `codex` workflow from `main`.
Harness adapters are described at
<https://docs.secureagentry.net/runner/#harness-adapters> and model sign-ins
at <https://docs.secureagentry.net/runner/#model-sign-ins>.

### agentry-hostlink

`alpine:3.24` with `openssh-client-default` (`ssh`), `openssh-client-common`
(`sftp`, `ssh-keyscan`, and `scp`, `ssh-add`, `ssh-agent` from the same
package) and `openssh-keygen`, and their dependencies. `openssh-keysign`, the
client's one setuid program, is not installed, and there is no setuid or
setgid file. `/etc/agentry/hostlink/packages` lists the resolved versions. A
password reaches `ssh` through `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force`,
so no `sshpass` is installed. The image holds no runner binary and no agent
socket or configuration, and forwards nothing.

It runs as uid 10001 (`hostlink`). `ssh` will not start for a uid with no
passwd entry, so running it as another uid needs a passwd line for that uid
bound in; and `ssh` accepts a private key of mode 0600 only when the uid
running it owns the file. The check runs against a throwaway OpenSSH server
(the `alpine:3.24` mirror with `openssh-server`, built by the check) on an
internal Docker network with no route out.

Target hosts are described at
<https://docs.secureagentry.net/runner/#target-hosts-a-server-named-at-run-time>.

### agentry-browser

Microsoft's [`@playwright/mcp`](https://github.com/microsoft/playwright-mcp)
driving a headless Chromium, Debian's `chromium` package, on the
`debian:trixie-slim` mirror. The runner starts it as a server in the run's
gateway and passes the settings that hold a run (proxy, tool filter, Chromium
sandbox, output folder, secrets file).

- `@playwright/mcp` is installed in `/app` with `npm ci --ignore-scripts
  --omit=dev` on the `node:24-bookworm-slim` mirror, held by
  `package-lock.json` (exact versions, sha512 integrity). That mirror also
  supplies `/usr/local/bin/node`.
- Chromium is Debian's build from the Chromium project's open-source code, with
  no Widevine CDM and no other proprietary component. `install.sh` installs it
  from [snapshot.debian.org](https://snapshot.debian.org/) at the timestamp in
  `source.env`, so every package it installs (Chromium's libraries and the
  fonts too) is the one that snapshot held. apt checks each index against
  Debian's archive signature and each package against the index, and
  `install.sh` refuses unless each suite's signed index (`InRelease`) has the
  SHA-256 in `source.env`, unless the `chromium` and `chromium-common` packages have
  `source.env`'s version and, for the architecture, its SHA-256s, and unless
  the lockfile's `playwright-core` was made for that Chromium major version or
  the next one (its `browsers.json`).
  The server is pointed at `/usr/lib/chromium/chromium` by
  `PLAYWRIGHT_MCP_EXECUTABLE_PATH`. Playwright's own browser download is
  Google's Chrome for Testing, which this image must not carry; the checks fail
  if a Chrome for Testing build, a Widevine CDM or a Google Chrome file appears
  in the context or the image.
- `policy.json` is installed as Chromium's managed policy, in
  `/etc/chromium/policies/managed/`. It sets
  `EncryptedClientHelloEnabled: false` (no launch flag can; Chromium otherwise
  sends a GREASE ECH extension, which the run's browse proxy refuses) and turns
  off QUIC, DNS-over-HTTPS, WebRTC UDP outside the proxy, component updates,
  Cast discovery and the browser's background services.

It runs as uid 10001 (`browser`) in `/out-browser`, where the runner binds the
run's `reports/browser/`, with no setuid or setgid file (Debian's setuid
`chromium-sandbox` is not installed). Debian package versions are recorded in
`/etc/agentry/browser/packages`, the server and browser versions in
`/etc/agentry/browser/record`, licences in `/usr/share/licenses/agentry-browser`.

To bump: set the new version in `package.json` and run `npm install
--package-lock-only --ignore-scripts` in `build/agentry-browser/`; copy
`MCP_VERSION` and `PLAYWRIGHT_VERSION` into `source.env`. Then pick a
snapshot.debian.org timestamp whose `trixie-security` (or `trixie`) holds a
`chromium` for the major version the new `browsers.json` names, or the one
before it, and set `DEBIAN_SNAPSHOT`, `CHROMIUM_VERSION`,
`CHROMIUM_DEB_VERSION`, the SHA-256s of `chromium` and `chromium-common` in
that snapshot's `binary-amd64` and `binary-arm64` `Packages` indexes, and the
SHA-256 of the `InRelease` of `trixie`, `trixie-updates` and `trixie-security`
at that snapshot.

### agentry-coder

The toolchain of the Coding agent, the persistent agent that builds and runs
software in its sandbox. The runner builds the agent's exec container from it,
adding its own binary; what the container may reach and which folders it
mounts are the runner's settings. It holds:

- from Debian 13's archive, at the snapshot.debian.org timestamp in
  `source.env`, with each suite's signed index held to its SHA-256:
  `build-essential` (GCC and G++, GNU Make, the C library's headers), `cmake`,
  `pkg-config`, `git`, `curl`, `ca-certificates`, `python3` with `python3-pip`,
  `python3-venv` and `python3-dev`, and `unzip`, `zip`, `xz-utils`, `bzip2`,
  `patch`, `file`, `jq`, `procps` and `less` (`PACKAGES` in `source.env`);
- Go, the Go project's release, in `/usr/local/go`, from the
  `golang:1.27.3-trixie` mirror, with `GOTOOLCHAIN=local`, so a module that
  asks for a newer Go fails instead of downloading a toolchain;
- Node 24 and npm, from the `node:24-bookworm-slim` mirror;
- in `/usr/local/bin`, five release binaries, each its project's static
  build, fetched over https and held to the SHA-256 that `source.env` pins
  for each architecture: `gh` (GitHub), `glab` (GitLab) and `tea` (Gitea),
  for the git hosts a person gives the agent an account on, and the scanners
  `osv-scanner` (known vulnerabilities in a project's dependencies, against a
  database fetched for it) and `gitleaks` (secrets in a tree or a history).
  `gh` and `glab` are told not to send usage reports or look for updates
  (`GH_TELEMETRY=false`, `GH_NO_UPDATE_NOTIFIER`,
  `GH_NO_EXTENSION_UPDATE_NOTIFIER`, `GLAB_SEND_TELEMETRY=false`,
  `GLAB_CHECK_UPDATE=false`).

Python packages install into a virtual environment (`python3 -m venv`):
Debian marks its own Python as externally managed. There is no `sudo` and no
SSH client or server (a dev server is reached through the runner's host link,
which holds the sign-in), and `scripts/check.sh` refuses a `PACKAGES` that adds
one; with no setuid file, the base's `su` cannot change user.

It runs as uid 10001 (`coder`) in `/home/coder`, with no setuid or setgid file.
Debian package versions are recorded in `/etc/agentry/coder/packages`, each
tool's version and the snapshot in `/etc/agentry/coder/record`, Go's, Node's
and npm's licences and each release binary's in
`/usr/share/licenses/agentry-coder`.

To bump Go: mirror the new `golang:<version>-trixie` (a row in `images.tsv`),
then set `GO_IMAGE` in `bases.env` and `GO_VERSION` in `source.env`. To move
the Debian packages: pick a snapshot.debian.org timestamp and set
`DEBIAN_SNAPSHOT` and the SHA-256 of the `InRelease` of `trixie`,
`trixie-updates` and `trixie-security` at it. To move a release binary: set
its version and both architectures' SHA-256 in `source.env`, after checking
each download against what its project publishes: `gh` against its
`checksums.txt` and its GitHub artifact attestation (`gh attestation verify
<file> --repo cli/cli`), `osv-scanner` against its `SHA256SUMS` and its SLSA
provenance (`slsa-verifier verify-artifact <file> --provenance-path
multiple.intoto.jsonl --source-uri github.com/google/osv-scanner
--source-tag v<version>`), and `glab`, `tea` and `gitleaks` against the
checksums their releases publish (they sign nothing). `tea` and
`osv-scanner` ship no licence beside the binary, so their `LICENSE` at the
release's tag is pinned too. Then run `--coder-image` on a local build and
dispatch the `coder` workflow from `main`.

### agentry-docker-agent-src

`build/docker-agent/` builds Docker Agent from the commit in `source.env`; it
is the runner's default harness. `upstream.Dockerfile` is the vendor's
Dockerfile at that commit, for comparison. Ours differs in six ways: every
base comes from the digest-pinned mirrors; the `docker-mcp` plugin is copied
from a pinned digest instead of the floating `docker/mcp-gateway:v2`;
`DOCKER_AGENT_DISABLE_DESKTOP_PROXY=1` is set; it builds Linux only, without
upstream's cross-compilation stages, with the binary checked to be statically
linked; otel's `otlptracegrpc` exporter is raised to the release that fixes
the advisories reported against upstream's pin; and it carries
`cold-cache-clear.patch`.

The patch adds one agent setting, `cold_cache_clear: {after, keep_turns,
keep_browser, browser_tools}`. On the first model request of a turn that
starts more than `after` since the previous model response ended, when the
provider's prompt cache has expired and the whole history is re-sent uncached
anyway, every tool result older than the newest `keep_turns` turns before the
current one (default 2), and every result of a tool in `browser_tools` but the
newest `keep_browser` (default 2), is sent as
`[cleared: <tool>(<arguments>) returned <n> bytes; call it again to read it]`,
with the arguments cut at 200 bytes. The stored session keeps every original
and records which results are cleared, so later requests, a reload of the
session and docker-agent's own compaction send the same bytes. Nothing is
cleared inside a turn, and an agent without the setting behaves as upstream.
The image keeps the patch at `/usr/share/doc/docker-agent/`. The patch leaves
upstream's `agent-schema.json` alone: it is outside the build's context and
the binary does not read it, so an editor validating an agent file against it
does not know the setting, and upstream's `TestSchemaMatchesGoTypes` in
`pkg/config` fails on the patched tree for that reason alone.

**Re-porting the patch on a commit bump.** Apply it to the new commit
(`git apply --3way build/docker-agent/cold-cache-clear.patch` in a clone at
`UPSTREAM_COMMIT`), resolve what no longer matches, and run its tests there:
`go test -tags no_audio -run 'ColdC|LastResponseAt' ./pkg/session
./pkg/runtime ./pkg/config/latest`. The hooks it needs are the session's two
history assemblies (`getMessages` and `CompactionInput`), the run loop's first
model request (`runStreamLoop`, before its loop), the agent config's latest
schema and the teamloader's agent options. Write the result back with `git
diff > cold-cache-clear.patch`. The build applies it with `patch --fuzz=0`, so
a hunk that moved fails the build rather than landing nearby, and runs its
tests before the binary is built; `scripts/check.sh` fails if the patch, its
application or its tests leave the Dockerfile.

The `docker-agent` workflow builds it natively for amd64 and arm64, runs each
hardened (`scripts/check.sh --docker-agent-image`), joins the two into one tag
(`<upstream version>-<UTC date>.<run number>`), signs that digest keyless and
prints the `images.tsv` row. It needs several GB of free disk per
architecture.

### agentry-gog

`build/gog/` builds [gog](https://github.com/openclaw/gogcli) from the commit
in `source.env`, for the Google Workspace MCP server: `gog mcp` serves Gmail,
Drive, Docs, Sheets and Calendar's events over stdio, reading only unless it
is started with `--allow-write`, and sending mail only with
`--allow-gmail-send` too. It is built rather than mirrored because gog's own
image is amd64 only and unsigned, and its Linux release binaries carry
checksums and no signature. `build/gog/Dockerfile` lists how it differs
from the project's own Dockerfile at that commit; it uses the digest-pinned Go and Alpine 3.24
mirrors, the project's release build settings (CGO off, `-trimpath`,
`GOTOOLCHAIN=local`, module sums verified), keeps its licence at
`/usr/share/licenses/gog/LICENSE`, strips setuid and setgid bits, and
otherwise matches upstream: uid 10001 (`gog`), `/persist/gogcli` for its
documented `GOG_HOME`, and `gog` as the entrypoint.

`scripts/check.sh --gog-image <ref>` runs it with no network and a read-only
root, `GOG_HOME` on a tmpfs and the file keyring, and drives `gog mcp` over
stdio with `build/gog/check/mcp.py`: every tool reads with no flag,
`--allow-write` adds tools and no send, `--allow-gmail-send` adds the send
tools, and a call with nobody signed in is an error. The `gog` workflow
builds amd64 and arm64 natively, checks each, joins them into one tag
(`<upstream version>-<UTC date>.<run number>`), signs that digest keyless and
prints the `images.tsv` row. To move it: set the commit and tag in
`source.env`, compare the project's Dockerfile at that commit with the
differences `build/gog/Dockerfile` lists, run `govulncheck ./...` over the
source, then `--gog-image` on a
local build, and dispatch the workflow from `main`.

### agentry-ms365

`build/ms365/` builds Softeria's
[ms-365-mcp-server](https://github.com/Softeria/ms-365-mcp-server) from the
commit in `source.env`, for the Microsoft 365 and Outlook.com MCP server: mail,
calendar, contacts and OneDrive over stdio, with the tools each switch allows
named by `--enabled-tools`. It is built rather than taken from npm or the
project's image because upstream's build downloads Microsoft Graph's OpenAPI
documents and its code generator unpinned, so neither can be rebuilt to the
same bytes, and neither is signed. `build/ms365/Dockerfile` lists how it
differs from the project's own Dockerfile: the documents pinned by commit and
sha256, the generator from `build/ms365/tools/`'s lockfile, every `npm ci`
with scripts off, the account tools left out of stdio mode, the log on `/tmp`
at level error with the audit log off, and the token cache sealed by
`/opt/agentry/cache-wrap` (`cache-wrap.mjs`) under the key in
`MS365_CACHE_KEY`, which refuses to run without one. It runs as uid 10001
(`ms365`) with its state at `/persist/ms365`.

`scripts/check.sh --ms365-image <ref>` runs it with no network and a
read-only root and drives it over stdio with `build/ms365/check/mcp.py` for
each switch combination with the allow-lists in `build/ms365/check/`: read
only, with changes, with sending. It checks the tools listed, the scopes
`--list-permissions` asks for, a call with nobody signed in, a start with no
cache key, and the keeper's sealing. The `ms365` workflow also scans each
architecture's image with OSV-Scanner against `build/ms365/osv-scanner.toml`,
which names each known vulnerability in its runtime packages that does not
reach a stdio server signed in by device code, and why; any other fails the
build. To move it: set the commit and tag in `source.env`, compare the
project's Dockerfile at that commit with the differences
`build/ms365/Dockerfile` lists, re-pin Graph's documents, rebuild
`tools/package-lock.json` if the generator moves, review `osv-scanner.toml`,
then run `--ms365-image` on a local build, and dispatch the workflow from
`main`.

### agentry-typst

`build/typst/` builds [Typst](https://github.com/typst/typst) at the commit in
`source.env`. The result holds only files, for the runner image to
`COPY --from=ghcr.io/blaktron/agentry-typst@<digest>`:

| Path | What |
|---|---|
| `/typst` | the static binary; also the entrypoint, so the checks can run the image |
| `/fonts/` | the Noto set (Latin, Greek, Cyrillic, Arabic, Hebrew, Thai, the Indic scripts, Simplified Chinese, Korean, symbols, math, Noto Color Emoji) and the report designs' fourteen families. All OFL-1.1 |
| `/typst-packages/` | the `cmarker` package (MIT), as Typst's local package directory, for `--package-path` |
| `/licenses/` | Typst's `LICENSE` and `NOTICE`, our patch, the licence files of every crate linked into the binary (`crates/`, with `crates.tsv` and `no-licence-file.tsv`), the OFL text of each font source, and `fetch.tsv` |

Japanese text renders its kana from the Chinese font and its Han characters in
Chinese forms; no Japanese or Traditional Chinese font is bundled. A template's
font list should put `Noto Color Emoji` straight after its text font.

**Built without Typst's package downloader.** Typst's cargo features cannot
remove the downloader: typst-cli turns typst-kit's `system-downloader` (ureq,
native-tls, OpenSSL) on unconditionally, so an `@preview` import that is not in
the package directory is fetched from `packages.typst.org`. So the build uses
`--no-default-features` (no HTTP server, no embedded fonts, since the fonts are
the bundled set) and applies `disable-package-downloads.patch`, which removes
`system-downloader` and `vendor-openssl` from typst-cli and replaces its
downloader with one that refuses every request with "package downloads are
disabled" (it touches `crates/typst-cli/Cargo.toml` and
`crates/typst-cli/src/download.rs`). The patch is applied with no fuzz. The
build fails if the binary's dependency list (`cargo tree`, normal
dependencies) does not name typst-cli and typst-kit or names a network client
(the list is in the Dockerfile), or if the binary needs a shared library or an
interpreter. Re-check the patch at every Typst tag bump: it must still apply,
the dependency check must pass, and `scripts/check.sh --typst-image` must
still pass, including its `strace` run that finds no network system call.

**Fonts and package.** `build/typst/fetch.sh` fetches them from the URLs in
`build/typst/fetch.tsv`, each at a pinned commit; a file whose SHA-256 differs
fails the build, and the licence column names each file's licence. The sources
are `notofonts/notofonts.github.io`, `notofonts/noto-cjk`,
`googlefonts/noto-emoji`, `google/fonts` and `typst/packages` (cmarker, whose
`raw-typst` default is `true`; the runner's template passes `raw-typst: false`
so Markdown never injects Typst code). The fourteen report design families are
Inter, IBM Plex Sans, Source Sans 3, Work Sans, Montserrat, Source Serif 4,
Lora, Merriweather, IBM Plex Serif, EB Garamond, Playfair Display, IBM Plex
Mono, JetBrains Mono and Source Code Pro, all OFL-1.1 from one pinned
`google/fonts` commit. Twelve ship there as variable fonts, which `fetch.tsv`
saves as `*-Variable.ttf`. `fixtures/fonts.txt` lists the families after
Noto's; the check renders `fixtures/families.typ` with each and fails on an
"unknown font family" warning.

PDF reports are described at
<https://docs.secureagentry.net/runner/#pdf-reports-export_pdf>.

### agentry-ripgrep

`build/ripgrep/` builds [ripgrep](https://github.com/BurntSushi/ripgrep) at the
commit in `source.env`, on the `agentry-rust-alpine` builder, with its default
features only: no PCRE2. The Dockerfile refuses a dependency tree that names
PCRE2 or a common network client crate, and a binary that needs a shared
library or an interpreter. On 64-bit musl ripgrep links jemalloc, which its
build compiles from vendored source.

The result holds only files, for the runner image to
`COPY --from=ghcr.io/blaktron/agentry-ripgrep@<digest>`: `/rg` (the static
binary, also the entrypoint) and `/licenses/` (ripgrep's `COPYING`,
`LICENSE-MIT` and `UNLICENSE`, and the licence files of every crate linked into
the binary, with `crates.tsv` and `no-licence-file.tsv`).
`scripts/check.sh --ripgrep-image <ref>` runs it with the fixed flags the tools
server passes (`--json --no-config --no-ignore --hidden --glob '!.git'` and the
size, column, thread and regex caps) over `build/ripgrep/fixtures/tree`, and
traces a search to show it makes no network system call and starts no second
program.

## Licence

The scripts, build contexts and manifest are MIT-licensed (`LICENSE`). Mirrored
and built images keep their own licences; `NOTICE` lists each one and the
changes made to Docker Agent, which is Apache-2.0. Nothing built here is a
Docker product.
