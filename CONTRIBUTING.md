# Contributing to agentry-dockerimages

This repository holds the manifest of the container images the Agentry
runner uses, and the scripts and workflows that mirror, build, check, sign
and publish them to `ghcr.io/blaktron`. Every image is either an upstream
image copied unchanged and pinned by digest, or built here from pinned
upstream source.

## Before you start

- **Security issues do not go in pull requests or public issues.** See
  [SECURITY.md](SECURITY.md).
- Everyone who takes part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
- For a new image, or a change to which image a run uses, open an issue
  first. Which images a run pulls and how they are configured is the CLI's
  policy, in [blaktron/agentry-cli](https://github.com/blaktron/agentry-cli).

## Contributing from outside

Fork, branch from `dev`, and open a pull request against `dev`. `dev` is
where changes land, and `main` takes only promotions from `dev` (the
`branch-model` check fails any other pull request into `main`). A
maintainer approves the CI run for a first-time contributor. Sign off every
commit (see "Certificate of origin" below), keep a change to one concern,
and say in the pull request what you verified and how.

## Checks

`scripts/check.sh` checks the repository: the manifest's format and pins,
the build contexts, and the workflows. CI runs it on every pull request, and
it must pass before you push. Given an image reference, it also checks a
built image. `scripts/pin.sh` reports upstream tags whose digest has moved,
and `scripts/build.sh <name>` builds a context in `build/`.

## The rules that matter

**Everything is pinned.** An upstream image is referenced by digest, and a
build context names the exact commit, release or tag it builds in
`source.env`, and its base images in `bases.env`. A base image has its own
row in `images.tsv`. A change that adds an unpinned fetch, a floating tag or
`latest` is not accepted.

**A mirror is a copy.** A `mirror` row copies the upstream image unchanged,
with every platform of its manifest list. A change to an image's contents is
a `build` row with its own context.

**Licences travel with the images.** A new upstream image or source gets its
licence in `NOTICE`, and a built image carries the upstream's licence and
notice files.

**Workflows never run a fork's code on a persistent runner.** A job on a
self-hosted runner that a fork's pull request can reach carries the fork
guard, and `scripts/check.sh` enforces it.

## Code style

Shell scripts pass `shellcheck`, which `scripts/check.sh` runs. Commits follow
conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`,
`security:`, `deps:`).

## Certificate of origin

This project uses the [Developer Certificate of Origin](https://developercertificate.org/)
instead of a CLA. Sign off your commits:

```bash
git commit -s -m "deps: move agentry-alpine to the new 3.22 digest"
```

By signing off you state that you wrote the contribution or have the right
to submit it under the project's licence.

## Licensing

The scripts, build contexts and manifest are MIT ([LICENSE](LICENSE)). The
images keep their own licences, listed in `NOTICE`.
