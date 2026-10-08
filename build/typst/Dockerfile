#
# Typst, built from pinned upstream source, with the Noto fonts and the
# cmarker package, as a files-only image (agentry-notes
# plans/scratch-and-pdf-reports.md §5, D23, D25, D26, D27;
# agentry-dockerimages#48).
#
#   upstream   github.com/typst/typst
#   commit     source.env beside this file
#   licence    Apache-2.0
#   reference  upstream's own Dockerfile is in the cloned tree at that commit
#
# scripts/build.sh clones the upstream commit as the build context and passes
# this directory as the named context `agentry`, which holds the patch, the
# fetch list and the fetch script.
#
# Changes from upstream's build:
#
#   1. Every base is an ARG, and scripts/build.sh passes our digest-pinned
#      mirror for it. Upstream builds on the floating rust:alpine and
#      tonistiigi/xx.
#   2. disable-package-downloads.patch removes the package downloader
#      (typst-kit's `system-downloader`: ureq, native-tls, OpenSSL), and the
#      vendor-openssl feature, from typst-cli. Its downloader now refuses
#      every request with "package downloads are disabled". So an
#      `#import "@preview/…"` the package directory cannot serve fails with
#      no network call. Typst's cargo features cannot do this: typst-cli
#      turns `system-downloader` on unconditionally (checked at v0.15.1). The
#      patch must be re-checked at every tag bump.
#   3. `--no-default-features`: no HTTP server (`typst watch` serving) and no
#      embedded fonts. The fonts are the bundled Noto set in /fonts. Upstream
#      builds the defaults.
#   4. Native builds only, one architecture per run (no xx cross-compiling).
#      The binary is checked to be static, with no OpenSSL or HTTP client in
#      its dependency tree.
#
# The image is files only (FROM scratch), for the runner image to
# `COPY --from=<this image>@<digest>`:
#
#   /typst            the static binary (it is also the entrypoint, so the
#                     image can be run for the checks)
#   /fonts/           the Noto set (fetch.tsv)
#   /typst-packages/  the cmarker package, for --package-path
#   /licenses/        Typst's LICENSE and NOTICE, the patch, the fonts' OFL
#                     texts and fetch.tsv
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG RUST_IMAGE=rust:1.98.1-alpine3.22

FROM ${RUST_IMAGE} AS fetch
COPY --from=agentry fetch.tsv fetch.sh /agentry/
RUN sh /agentry/fetch.sh /agentry/fetch.tsv /out && \
	cp /agentry/fetch.tsv /out/licenses/fetch.tsv

FROM ${RUST_IMAGE} AS builder
# gcc and musl-dev are in the base; patch is not.
RUN apk add --no-cache patch
WORKDIR /src
COPY . ./
COPY --from=agentry disable-package-downloads.patch /agentry/
RUN patch -p1 --forward --no-backup-if-mismatch </agentry/disable-package-downloads.patch
ARG GIT_TAG
ARG GIT_COMMIT
# typst --version reports the commit (typst-utils/build.rs); there is no .git here.
ENV TYPST_COMMIT_SHA=${GIT_COMMIT}
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	set -eu; \
	cargo build --locked --release -p typst-cli --no-default-features; \
	cp target/release/typst /typst; \
	cargo tree --locked -p typst-cli --no-default-features -e normal --prefix none \
		| sed 's/ .*//' | sort -u >/deps.txt
# The patch's whole point: no network client in the binary's dependency tree.
RUN set -eu; \
	for c in ureq native-tls openssl openssl-sys env_proxy tiny_http self-replace; do \
		if grep -qx "$c" /deps.txt; then \
			echo "typst still depends on $c: the patch no longer removes the downloader" >&2; \
			exit 1; \
		fi; \
	done; \
	if readelf -d /typst | grep -q NEEDED || readelf -l /typst | grep -q INTERP; then \
		echo "typst is dynamically linked" >&2; \
		exit 1; \
	fi; \
	/typst --version

FROM scratch
COPY --from=builder /typst /typst
COPY --from=fetch /out/fonts/ /fonts/
COPY --from=fetch /out/typst-packages/ /typst-packages/
COPY --from=fetch /out/licenses/ /licenses/
COPY --from=builder /src/LICENSE /src/NOTICE /licenses/typst/
COPY --from=agentry disable-package-downloads.patch /licenses/typst/
ENTRYPOINT ["/typst"]

LABEL org.opencontainers.image.title="Typst (built by Agentry), with the Noto fonts and cmarker" \
	org.opencontainers.image.source="https://github.com/blaktron/agentry-dockerimages" \
	org.opencontainers.image.licenses="Apache-2.0 AND OFL-1.1 AND MIT" \
	org.opencontainers.image.description="Typst built from a pinned upstream commit without its package downloader, the Noto font set and the cmarker package, files only, for the QuickAgent runner's export_pdf"
