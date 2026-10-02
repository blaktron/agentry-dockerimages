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
#
# /etc/agentry/files/packages lists the package versions apk resolved, one
# `name-version` a line, so a receipt can name them.
#
# scripts/build.sh passes ALPINE_IMAGE as our digest-pinned mirror of
# alpine:3.22, the runner image's own runtime base.

ARG ALPINE_IMAGE=alpine:3.22

FROM ${ALPINE_IMAGE}
# The index fetch from Alpine's CDN fails now and then (plan §1.1 measured one
# try in six from a sandbox host). `apk add --no-cache` fetches the indexes
# itself, so the whole add is retried half a minute apart; a failure is never
# taken as a success.
RUN for try in 1 2 3 4 5; do \
		apk add --no-cache pandoc-cli poppler-utils tesseract-ocr tesseract-ocr-data-eng && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done \
	&& mkdir -p /etc/agentry/files \
	&& apk list --installed pandoc-cli poppler-utils tesseract-ocr tesseract-ocr-data-eng | cut -d' ' -f1 >/etc/agentry/files/packages \
	&& test "$(wc -l </etc/agentry/files/packages)" -eq 4
