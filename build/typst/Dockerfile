# Typst, built from pinned upstream source, with the Noto fonts, the report
# designs' font families and the cmarker package, as a files-only image
# (agentry-notes plans/scratch-and-pdf-reports.md §5, D23, D25, D26, D27;
# agentry-dockerimages#48; plans/report-designs.md D13, agentry-dockerimages#58).
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
#      embedded fonts. The fonts are the bundled set in /fonts. Upstream
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
#   /fonts/           the Noto set and the report designs' fourteen families
#                     (fetch.tsv)
#   /typst-packages/  the cmarker package, for --package-path
#   /licenses/        Typst's LICENSE and NOTICE, the patch, the licence files
#                     of the crates linked into the binary, the fonts' OFL
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
# gcc, musl-dev and binutils (readelf) are in the base; patch is not.
RUN apk add --no-cache patch
WORKDIR /src
COPY . ./
COPY --from=agentry disable-package-downloads.patch /agentry/
# --fuzz=0: a hunk that no longer matches exactly fails the build rather than
# landing somewhere near.
RUN patch -p1 --forward --fuzz=0 --no-backup-if-mismatch </agentry/disable-package-downloads.patch
ARG GIT_COMMIT
# typst --version reports the commit (typst-utils/build.rs); set it rather
# than have the build script ask git.
ENV TYPST_COMMIT_SHA=${GIT_COMMIT}
# One RUN, because the registry is a cache mount: the build, the binary's
# dependency list (normal dependencies only: what is linked in), and each
# registry crate's licence and notice files, which a statically linked
# binary must carry (most are MIT or Apache-2.0). Typst's own workspace
# crates are covered by its LICENSE. A crate that ships no licence file is
# listed in no-licence-file.tsv with the licence its manifest declares.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	set -eu; set -o pipefail; \
	cargo build --locked --release -p typst-cli --no-default-features; \
	cp target/release/typst /typst; \
	cargo tree --locked -p typst-cli --no-default-features -e normal --prefix none --format '{p}|{l}' \
		| sed 's/ (\*)$//' | sort -u >/crates.txt; \
	sed 's/ .*//' /crates.txt | sort -u >/deps.txt; \
	mkdir -p /crate-licenses; \
	printf '# crate\tversion\tlicence (Cargo.toml)\n' >/crate-licenses/crates.tsv; \
	while IFS='|' read -r pkg licence; do \
		case "$pkg" in *"(/src"*) continue ;; esac; \
		name=${pkg%% *}; ver=${pkg#* v}; ver=${ver%% *}; \
		dir=$(ls -d /usr/local/cargo/registry/src/*/"$name-$ver" | head -1); \
		printf '%s\t%s\t%s\n' "$name" "$ver" "$licence" >>/crate-licenses/crates.tsv; \
		found=0; \
		for f in "$dir"/LICENSE* "$dir"/LICENCE* "$dir"/COPYING* "$dir"/NOTICE* "$dir"/UNLICENSE*; do \
			if [ -f "$f" ]; then mkdir -p "/crate-licenses/$name-$ver"; cp "$f" "/crate-licenses/$name-$ver/"; found=1; fi; \
		done; \
		[ "$found" = 1 ] || printf '%s\t%s\t%s\n' "$name" "$ver" "$licence" >>/crate-licenses/no-licence-file.tsv; \
	done </crates.txt
# The patch's whole point: no network client in the binary's dependency tree.
# The list must name typst-cli and typst-kit, so an empty or unreadable one
# cannot pass.
RUN set -eu; \
	if ! grep -qx typst-cli /deps.txt || ! grep -qx typst-kit /deps.txt; then \
		echo "the dependency list does not name typst-cli and typst-kit" >&2; exit 1; \
	fi; \
	for c in ureq native-tls openssl openssl-sys env_proxy tiny_http self-replace \
		rustls hyper h2 reqwest attohttpc isahc curl curl-sys; do \
		if grep -qx "$c" /deps.txt; then \
			echo "typst depends on $c: the patch no longer keeps a network client out" >&2; \
			exit 1; \
		fi; \
	done; \
	command -v readelf >/dev/null; \
	if readelf -d /typst | grep -q NEEDED || readelf -l /typst | grep -q INTERP; then \
		echo "typst needs a shared library or an interpreter: it is not static" >&2; \
		exit 1; \
	fi; \
	touch /crate-licenses/no-licence-file.tsv; \
	echo "$(grep -vc '^#' /crate-licenses/crates.tsv) crates linked; $(wc -l </crate-licenses/no-licence-file.tsv) ship no licence file"; \
	/typst --version

FROM scratch
COPY --from=builder /typst /typst
COPY --from=fetch /out/fonts/ /fonts/
COPY --from=fetch /out/typst-packages/ /typst-packages/
COPY --from=fetch /out/licenses/ /licenses/
COPY --from=builder /src/LICENSE /src/NOTICE /licenses/typst/
COPY --from=agentry disable-package-downloads.patch /licenses/typst/
COPY --from=builder /crate-licenses/ /licenses/crates/
ENTRYPOINT ["/typst"]

LABEL org.opencontainers.image.title="Typst (built by Agentry), with the Noto fonts, the report design fonts and cmarker" \
	org.opencontainers.image.source="https://github.com/blaktron/agentry-dockerimages" \
	org.opencontainers.image.licenses="Apache-2.0 AND OFL-1.1 AND MIT" \
	org.opencontainers.image.description="Typst built from a pinned upstream commit without its package downloader, the Noto font set, the report designs' open-licence font families and the cmarker package, files only, for the QuickAgent runner's export_pdf"
