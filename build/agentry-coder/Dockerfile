# agentry-coder: the toolchain image of the Coding agent, the persistent
# agent that builds and runs software in its sandbox.
#
# The runner builds its exec container from this image, adding its own
# binary as the entrypoint; nothing here opens a network or starts a
# program. What a run may reach, and which folders it mounts, are the
# runner's settings, not this image's.
#
#   /usr/bin, /usr/lib   Debian 13's build-essential (gcc, g++, make,
#                        libc6-dev), cmake, pkg-config, git, curl, Python 3
#                        with pip, venv and its headers, and the archive and
#                        text tools source.env's PACKAGES names, each from
#                        snapshot.debian.org at source.env's timestamp
#                        (install.sh)
#   /usr/local/go        Go, the Go project's release, the one tree taken
#                        from GO_IMAGE; GOTOOLCHAIN=local, so a go.mod that
#                        asks for a newer Go fails rather than downloading a
#                        toolchain
#   /usr/local/bin/node  Node, and npm in /usr/local/lib/node_modules/npm,
#                        the files taken from NODE_IMAGE
#   /etc/agentry/coder/record
#                        one line per tool and its version, and the snapshot,
#                        for the receipt
#   /etc/agentry/coder/packages
#                        every Debian package installed, name and version
#   /usr/share/licenses/agentry-coder
#                        Go's and Node's LICENSE and npm's; each Debian
#                        package's is in /usr/share/doc/<package>/copyright
#
# pip installs into a virtual environment (python3 -m venv): Debian marks its
# own Python as externally managed. No file is setuid or setgid: the base's
# and the packages' are stripped. There is no sudo and no SSH client or
# server: a dev server is reached through the runner's host link, which holds
# the sign-in.
#
# It runs as uid 10001 (coder), never root, in /home/coder.
#
# scripts/build.sh passes DEBIAN_IMAGE, GO_IMAGE and NODE_IMAGE as our
# digest-pinned mirrors (bases.env).
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG DEBIAN_IMAGE=debian:trixie-slim
ARG GO_IMAGE=golang:1.27.2-trixie
ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${GO_IMAGE} AS go
FROM ${NODE_IMAGE} AS node

FROM ${DEBIAN_IMAGE}
COPY --from=go /usr/local/go /usr/local/go
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=node /usr/local/LICENSE /usr/share/licenses/agentry-coder/node/LICENSE
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
	&& ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
COPY source.env install.sh /agentry/
RUN sh /agentry/install.sh /agentry/source.env /agentry/out
RUN find / -xdev -type f -perm /6000 -exec chmod ug-s {} + \
	&& groupadd -g 10001 coder \
	&& useradd -u 10001 -g coder -d /home/coder -m -s /bin/bash coder \
	&& install -d -m 0755 /etc/agentry/coder \
	&& install -d /usr/share/licenses/agentry-coder/go /usr/share/licenses/agentry-coder/npm \
	&& cp /usr/local/go/LICENSE /usr/local/go/PATENTS /usr/share/licenses/agentry-coder/go/ \
	&& cp /usr/local/lib/node_modules/npm/LICENSE /usr/share/licenses/agentry-coder/npm/ \
	&& cp /agentry/out/record /etc/agentry/coder/record \
	&& rm -rf /agentry \
	&& dpkg-query -W -f '${Package} ${Version}\n' | sort >/etc/agentry/coder/packages
ENV PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	GOTOOLCHAIN=local \
	NPM_CONFIG_UPDATE_NOTIFIER=false \
	HOME=/home/coder
USER 10001:10001
WORKDIR /home/coder
CMD ["/bin/bash"]
