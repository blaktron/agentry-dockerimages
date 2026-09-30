# syntax=docker/dockerfile:1
#
# agentry-unsafe-kali: the base of the desktop's Unsafe Mode exec images
# (agentry-notes plans/unsafe-mode.md §4.1; agentry-dockerimages#15).
#
# A lean Kali Linux (kali-rolling) with ca-certificates, python3 and Python's
# venv support, and two data files under /etc/agentry/unsafe/ that the CLI
# reads when it builds a QuickAgent's exec image on top of this one (Unsafe
# Mode M2):
#
#   commands.tsv   the command index: command → the Kali package that ships it,
#                  generated here from Kali's Contents-<arch> by make-index.py
#   extras.tsv     the extras list, maintained by hand beside this file
#   ambiguous.tsv  the commands the index leaves out, and why
#
# No security tool is installed here: each QuickAgent's declared commands are
# installed on top of this image, per QuickAgent, by the CLI.
#
# Build natively for each architecture: the index is built from that
# architecture's Contents, and python3 is installed for it. scripts/build.sh
# passes KALI_IMAGE as our digest-pinned mirror of kalilinux/kali-rolling.

ARG KALI_IMAGE=kalilinux/kali-rolling:latest

FROM ${KALI_IMAGE} AS index
ARG DEBIAN_FRONTEND=noninteractive
# apt-get update verifies InRelease's signature against Kali's archive key
# (kali-archive-keyring, in the base). make-index.py then holds every file it
# reads to the SHA-256 that InRelease lists, so the index comes from what Kali
# signed, whichever mirror http.kali.org redirects to.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl python3 \
	&& mkdir -p /work \
	&& cp /var/lib/apt/lists/*_dists_kali-rolling_InRelease /work/InRelease
RUN set -eu; \
	arch="$(dpkg --print-architecture)"; \
	base="$(awk '$1 == "URIs:" { sub("/$", "", $2); print $2; exit }' /etc/apt/sources.list.d/kali.sources)/dists/kali-rolling"; \
	case "$base" in http://*|https://*) ;; *) echo "no Kali URI in kali.sources" >&2; exit 1 ;; esac; \
	for comp in main contrib non-free; do \
		mkdir -p "/work/$comp/binary-$arch"; \
		curl -fsSL --retry 3 -o "/work/$comp/Contents-$arch.gz" "$base/$comp/Contents-$arch.gz"; \
		curl -fsSL --retry 3 -o "/work/$comp/binary-$arch/Packages.gz" "$base/$comp/binary-$arch/Packages.gz"; \
	done; \
	echo "$arch" > /work/arch
COPY make-index.py extras.tsv /build/
RUN python3 /build/make-index.py --self-test \
	&& python3 /build/make-index.py --arch "$(cat /work/arch)" --dir /work --extras /build/extras.tsv --out /out \
	&& cp /build/extras.tsv /out/extras.tsv

FROM ${KALI_IMAGE}
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates python3 python3-venv \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*
COPY --from=index /out/ /etc/agentry/unsafe/

LABEL org.opencontainers.image.title="agentry-unsafe-kali" \
	org.opencontainers.image.source="https://github.com/blaktron/agentry-dockerimages" \
	org.opencontainers.image.licenses="MIT" \
	org.opencontainers.image.description="Kali Linux (kali-rolling) with a command index and an extras list: the base of the Agentry desktop's Unsafe Mode exec images. It carries no security tools; each QuickAgent's declared commands are installed on top of it."
