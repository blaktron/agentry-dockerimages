# agentry-hostlink: the host link image, the OpenSSH client the runner's host
# link uses to reach a target host, a machine the person names when a run
# starts.
#
# The host link is a runner-owned container behind one relay to the host's
# address and port. It holds the host's credential in files bound into it
# alone, and makes the SSH session; the agent never does. The runner image
# stays standard-library only, so the client is OpenSSH, in an image
# of its own.
#
# It holds the client and no runner binary: the CLI adds its own runner in an
# offline layer FROM this image's digest, as it does for the files image.
#
#   openssh-client-default   ssh, the session itself (one-shot commands, and
#                            an interactive shell on a remote pseudo-terminal)
#   openssh-client-common    sftp (file reads, writes and copies) and
#                            ssh-keyscan (the host key of an unknown host)
#   openssh-keygen           ssh-keygen (a key's fingerprint, a known_hosts
#                            lookup)
#
# openssh-client-common also holds scp, ssh-add, ssh-agent, ssh-copy-id and
# ssh-pkcs11-helper. The host link uses none of them, and no forwarding of
# any kind is the runner's ssh argv to hold; the CLI's
# minimize step can drop what its catalogue does not name.
#
# A password reaches ssh through SSH_ASKPASS with SSH_ASKPASS_REQUIRE=force,
# which this OpenSSH has; no sshpass is installed.
#
# PACKAGES is the one list of what is installed: apk brings their dependencies
# (libedit, ncurses' library and terminfo data; no setuid program), nothing
# else is added. Alpine's openssh-keysign, the one setuid part of the client,
# is not installed.
# /etc/agentry/hostlink/packages records the version apk resolved for each of
# PACKAGES, one `name-version` a line, so a receipt can name them.
#
# It runs as uid 10001 (hostlink), never root. ssh refuses to start for a uid
# with no passwd entry ("No user exists for uid"), so a container run as
# another uid needs a passwd line for that uid bound in.
#
# scripts/build.sh passes ALPINE_IMAGE as our digest-pinned mirror of
# alpine:3.24, the runner image's own runtime base.
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG ALPINE_IMAGE=alpine:3.24

FROM ${ALPINE_IMAGE}
ARG PACKAGES="openssh-client-default openssh-client-common openssh-keygen"
# The index fetch from Alpine's CDN fails now and then.
# `apk add --no-cache` fetches the indexes itself, so the whole add is retried
# half a minute apart; a failure is never taken as a success.
RUN for try in 1 2 3 4 5; do \
		apk add --no-cache $PACKAGES && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done \
	&& mkdir -p /etc/agentry/hostlink \
	&& apk list --installed $PACKAGES | cut -d' ' -f1 >/etc/agentry/hostlink/packages \
	&& set -- $PACKAGES && test "$(wc -l </etc/agentry/hostlink/packages)" -eq "$#" \
	&& addgroup -g 10001 hostlink \
	&& adduser -D -u 10001 -G hostlink -h /home/hostlink -s /sbin/nologin hostlink
USER 10001:10001
WORKDIR /home/hostlink
