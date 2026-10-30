# syntax=docker/dockerfile:1
#
# agentry-files: the files image, the decoders the runner's decode step runs
# over a run's documents before any agent starts.
#
# The decoders are not installed with `apk add` from Alpine's CDN inside the
# run, where a failed fetch fails the run. Here the fetch happens once, in CI,
# and the CLI pulls the result by digest.
#
# It holds the decoders and their data, and no runner binary: the CLI adds its
# own runner in an offline layer FROM this image's digest and minimizes the
# result to the decoders and the runner. The decode container runs with no
# network, every capability dropped and a read-only root.
#
#   pandoc-cli               .docx .odt .epub .rtf  (pandoc --sandbox)
#   poppler-utils            .pdf                   (pdftotext)
#   tesseract-ocr, -data-eng images, English OCR    (tesseract)
#   openjdk17-jre-headless   Apache Tika, added below, for detection and the long tail
#   libarchive-tools         archives                (bsdtar, bsdcat)
#   file                     content detection       (libmagic)
#   clamav-scanner           the malware check       (clamscan)
#   clamav-libunrar          clamscan's rar reader, loaded by libclamav
#
# ClamAV is the scanner, with no daemon (clamd). Alpine's clamav-scanner
# depends on freshclam, so freshclam is here too, but nothing runs it: the
# decode container has no network, and the CLI's decode image is minimized
# to its catalogue's commands, which removes it. The signatures come from
# outside: the CLI mounts the daily signed bundle the clamav-db workflow
# publishes (ghcr.io/blaktron/agentry-clamav-db) read-only. This
# image holds no signature database.
#
# PACKAGES is the one list of what is installed: apk brings their dependencies
# (libraries and data, no setuid program), nothing else is added.
# /etc/agentry/files/packages records the version apk resolved for each of
# PACKAGES, one `name-version` a line, so a receipt can name them.
#
# scripts/build.sh passes ALPINE_IMAGE as our digest-pinned mirror of
# alpine:3.24, the runner image's own runtime base.

ARG ALPINE_IMAGE=alpine:3.24

FROM ${ALPINE_IMAGE}
ARG PACKAGES="pandoc-cli poppler-utils tesseract-ocr tesseract-ocr-data-eng openjdk17-jre-headless libarchive-tools file clamav-scanner clamav-libunrar"
# The index fetch from Alpine's CDN fails now and then (about one try
# in six from a sandbox host). `apk add --no-cache` fetches the indexes
# itself, so the whole add is retried half a minute apart; a failure is never
# taken as a success.
RUN for try in 1 2 3 4 5; do \
		apk add --no-cache $PACKAGES && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done \
	&& mkdir -p /etc/agentry/files \
	&& apk list --installed $PACKAGES | cut -d' ' -f1 >/etc/agentry/files/packages \
	&& set -- $PACKAGES && test "$(wc -l </etc/agentry/files/packages)" -eq "$#"

# Tika's application distribution: the runnable tika-app jar and the lib/
# directory of parser jars its manifest names, as Apache publishes them in one
# zip. Pin the Apache release by SHA-512; a mirror returning different bytes
# fails the build. /opt/tika/tika-app.jar is the path the decode step runs.
ARG TIKA_VERSION=4.2.0
ARG TIKA_SHA512=a9966e238fc0178a4ba3e7dd870c7b59894a16ec7759fc5582d62d0ecf9006b84e8ec97270ec2c3c0171acd57ef6ed351d55fa6884a4e52f2635fd148652bf0f
ADD https://archive.apache.org/dist/tika/${TIKA_VERSION}/tika-app-${TIKA_VERSION}.zip /tmp/tika-app.zip
RUN echo "$TIKA_SHA512  /tmp/tika-app.zip" | sha512sum -c - \
    && mkdir -p /opt/tika \
    && bsdtar -xf /tmp/tika-app.zip -C /opt/tika \
    && rm /tmp/tika-app.zip \
    && ln -s "tika-app-${TIKA_VERSION}.jar" /opt/tika/tika-app.jar \
    && chmod -R u=rwX,go=rX /opt/tika \
    && test -f "/opt/tika/tika-app-${TIKA_VERSION}.jar" \
    && printf 'tika-app-%s\n' "$TIKA_VERSION" >>/etc/agentry/files/packages
COPY tika-app /usr/bin/tika-app
RUN chmod 755 /usr/bin/tika-app
