# ripgrep, built from pinned upstream source, as a files-only image
# (agentry-notes plans/ripgrep-search.md D1, D3, D9; agentry-dockerimages#81).
#
#   upstream   github.com/BurntSushi/ripgrep
#   commit     source.env beside this file
#   licence    Unlicense OR MIT
#
# scripts/build.sh clones the upstream commit as the build context; this
# directory's own files are not needed by the build.
#
# Changes from upstream's release build:
#
#   1. The base is an ARG, and scripts/build.sh passes our digest-pinned
#      mirror for it (the Rust builder Typst uses).
#   2. Default features only: no `pcre2` (plan D9), so no C regex library is
#      linked in. The dependency check below refuses a build whose tree names
#      PCRE2 or a network client.
#   3. Native builds only, one architecture per run. The binary is checked to
#      be static.
#
# On 64-bit musl ripgrep links jemalloc (tikv-jemallocator), which its build
# compiles from the vendored C source; that is upstream's own choice for musl
# and stays.
#
# The image is files only (FROM scratch), for the runner image to
# `COPY --from=<this image>@<digest>`:
#
#   /rg          the static binary (also the entrypoint, so the image can be
#                run for the checks)
#   /licenses/   ripgrep's COPYING, LICENSE-MIT and UNLICENSE, and the licence
#                files of the crates linked into the binary
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG RUST_IMAGE=rust:1.98.1-alpine3.22

FROM ${RUST_IMAGE} AS builder
# gcc, musl-dev and binutils (readelf) are in the base; make, which jemalloc's
# build runs, is not.
RUN apk add --no-cache make
WORKDIR /src
COPY . ./
# One RUN, because the registry is a cache mount: the build, the binary's
# dependency list (normal dependencies only: what is linked in), and each
# registry crate's licence and notice files, which a statically linked binary
# must carry. ripgrep's own workspace crates are covered by its licence files.
# A crate that ships no licence file is listed in no-licence-file.tsv with the
# licence its manifest declares.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/src/target \
	set -eu; set -o pipefail; \
	cargo build --locked --release --bin rg; \
	cp target/release/rg /rg; \
	cargo tree --locked -p ripgrep -e normal --prefix none --format '{p}|{l}' \
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
# No PCRE2 and no network client in the binary's dependency tree, and a static
# binary. The list must name ripgrep and grep, so an empty or unreadable one
# cannot pass.
RUN set -eu; \
	if ! grep -qx ripgrep /deps.txt || ! grep -qx grep /deps.txt; then \
		echo "the dependency list does not name ripgrep and grep" >&2; exit 1; \
	fi; \
	for c in pcre2 pcre2-sys grep-pcre2 ureq native-tls openssl openssl-sys \
		rustls hyper h2 reqwest attohttpc isahc curl curl-sys; do \
		if grep -qx "$c" /deps.txt; then \
			echo "ripgrep depends on $c: only the default features may be built" >&2; \
			exit 1; \
		fi; \
	done; \
	command -v readelf >/dev/null; \
	if readelf -d /rg | grep -q NEEDED || readelf -l /rg | grep -q INTERP; then \
		echo "rg needs a shared library or an interpreter: it is not static" >&2; \
		exit 1; \
	fi; \
	touch /crate-licenses/no-licence-file.tsv; \
	echo "$(grep -vc '^#' /crate-licenses/crates.tsv) crates linked; $(wc -l </crate-licenses/no-licence-file.tsv) ship no licence file"; \
	/rg --version

FROM scratch
COPY --from=builder /rg /rg
COPY --from=builder /src/COPYING /src/LICENSE-MIT /src/UNLICENSE /licenses/ripgrep/
COPY --from=builder /crate-licenses/ /licenses/crates/
ENTRYPOINT ["/rg"]

LABEL org.opencontainers.image.title="ripgrep (built by Agentry)" \
	org.opencontainers.image.source="https://github.com/blaktron/agentry-dockerimages" \
	org.opencontainers.image.licenses="Unlicense OR MIT" \
	org.opencontainers.image.description="ripgrep built from a pinned upstream commit with its default features (no PCRE2), static, files only, for the QuickAgent runner's grep and glob tools"
