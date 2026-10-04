# syntax=docker/dockerfile:1
#
# agentry-files: the files image, the decoders the runner's decode step runs
# over a run's documents before any agent starts (agentry-notes
# plans/file-handling.md §4, D3, D4; agentry-dockerimages#28).
#
# It replaces the decode image the CLI used to build at run time with
# `apk add` from Alpine's CDN, inside the run (plan §1.1: a production Voice
# Writer run failed when that fetch failed). Here the fetch happens once, in
# CI, and the CLI pulls the result by digest.
#
# It holds the decoders and their data, and no runner binary: the CLI adds its
# own runner in an offline layer FROM this image's digest and minimizes the
# result to the decoders and the runner (agentry-cli#559). The decode container
# runs with no network, every capability dropped and a read-only root (DR-39).
#
#   pandoc-cli               .docx .odt .epub .rtf  (pandoc --sandbox)
#   poppler-utils            .pdf                   (pdftotext)
#   tesseract-ocr, -data-eng images, English OCR    (tesseract)
#   openjdk17-jre-headless   Apache Tika, added below, for detection and the long tail
#   libarchive-tools         archives                (bsdtar, bsdcat)
#   file                     content detection       (libmagic)
#   clamav-scanner           the malware check       (clamscan; agentry-dockerimages#30)
#   clamav-libunrar          clamscan's rar reader, loaded by libclamav
#
# ClamAV is the scanner, with no daemon (clamd). Alpine's clamav-scanner
# depends on freshclam, so freshclam is here too, but nothing runs it: the
# decode container has no network, and the CLI's decode image is minimized
# to its catalogue's commands, which removes it. The signatures come from
# outside: the CLI mounts the daily signed bundle the clamav-db workflow
# publishes (ghcr.io/blaktron/agentry-clamav-db) read-only (plan
# file-handling.md §7, D15). This image holds no signature database.
#
# PACKAGES is the one list of what is installed: apk brings their dependencies
# (libraries and data, no setuid program), nothing else is added.
# /etc/agentry/files/packages records the version apk resolved for each of
# PACKAGES, one `name-version` a line, so a receipt can name them.
#
# scripts/build.sh passes ALPINE_IMAGE as our digest-pinned mirror of
# alpine:3.22, the runner image's own runtime base.

ARG ALPINE_IMAGE=alpine:3.22

FROM ${ALPINE_IMAGE}
ARG PACKAGES="pandoc-cli poppler-utils tesseract-ocr tesseract-ocr-data-eng openjdk17-jre-headless libarchive-tools file clamav-scanner clamav-libunrar"
# The index fetch from Alpine's CDN fails now and then (plan §1.1 measured one
# try in six from a sandbox host). `apk add --no-cache` fetches the indexes
# itself, so the whole add is retried half a minute apart; a failure is never
# taken as a success.
RUN for try in 1 2 3 4 5; do \
		apk add --no-cache $PACKAGES && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done \
	&& mkdir -p /etc/agentry/files \
	&& apk list --installed $PACKAGES | cut -d' ' -f1 >/etc/agentry/files/packages \
	&& set -- $PACKAGES && test "$(wc -l </etc/agentry/files/packages)" -eq "$#"

# Tika's runnable jar includes its parser dependencies. Pin the Apache release
# by SHA-512; a mirror returning different bytes fails the build.
ARG TIKA_VERSION=3.3.2
ARG TIKA_SHA512=88c2032cba0d45feea361e6eebd2918bd04707614cdda5d89a1b167da5503c98e7b4cd368336f0402d559abcaf5006fcc7c825c32c749ae0417ea2f3b8423aba
ADD https://repo.maven.apache.org/maven2/org/apache/tika/tika-app/${TIKA_VERSION}/tika-app-${TIKA_VERSION}.jar /opt/tika/tika-app.jar
RUN echo "$TIKA_SHA512  /opt/tika/tika-app.jar" | sha512sum -c - \
    && chmod 644 /opt/tika/tika-app.jar \
    && printf 'tika-app-%s\n' "$TIKA_VERSION" >>/etc/agentry/files/packages
COPY tika-app /usr/bin/tika-app
RUN chmod 755 /usr/bin/tika-app
