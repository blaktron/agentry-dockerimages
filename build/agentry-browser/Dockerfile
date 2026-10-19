# agentry-browser: the browser server image, Microsoft's @playwright/mcp
# driving Debian's Chromium, for a QuickAgent that declares
# capabilities.browser.
#
# The runner starts it as a server in the run's gateway, behind one relay to
# the run's browse proxy, its only route out; nothing here opens a network.
# The settings that hold a run (the proxy, the tool filter, the sandbox, the
# output folder, the secrets file) are the runner's, passed when it starts
# the server; this image holds what they need and nothing more.
#
#   /app                 @playwright/mcp from package-lock.json, installed
#                        with --ignore-scripts, so no package runs code at
#                        install
#   /usr/local/bin/node  Node 24, the one file taken from NODE_IMAGE
#                        (Playwright needs Node 20 or later)
#   /usr/lib/chromium/chromium
#                        Debian's chromium package, built by Debian from the
#                        Chromium project's source, at source.env's version
#                        and SHA-256, from snapshot.debian.org at source.env's
#                        timestamp (install.sh). It carries no Widevine CDM
#                        and no other proprietary component. Playwright's
#                        own browser download is Google's Chrome for Testing,
#                        which is not open source, so the image has none:
#                        PLAYWRIGHT_MCP_EXECUTABLE_PATH points the server at
#                        this executable whatever --browser it is given
#   /etc/chromium/policies/managed/agentry.json
#                        the Chromium policy (policy.json), at the path
#                        Debian's Chromium reads. EncryptedClientHelloEnabled
#                        false is what lets the browse proxy's SNI check pass:
#                        no launch flag stops Chromium's GREASE ECH. The rest
#                        turns off QUIC, DNS-over-HTTPS, non-proxied WebRTC
#                        UDP and the browser's background services
#   /etc/agentry/browser/record
#                        one line each for the server, Playwright, Node and
#                        the browser (version, Debian version, architecture,
#                        package SHA-256 and snapshot), for the receipt
#   /etc/agentry/browser/packages
#                        every Debian package installed, name and version
#   /usr/share/licenses/agentry-browser
#                        Node's LICENSE, the three npm packages' LICENSE (and
#                        Playwright's NOTICE and ThirdPartyNotices.txt), and
#                        Debian's copyright file for chromium, which lists the
#                        licences of Chromium and the code it bundles (also
#                        in the browser itself, chrome://credits)
#
# Every Debian package, Chromium's libraries and the fonts included, comes
# from the one snapshot, so a rebuild of the same commit installs the same
# versions; they are recorded in /etc/agentry/browser/packages. No file is
# setuid or setgid: the base's are stripped, and chromium-sandbox (Debian's
# setuid sandbox helper) is not installed (the runner runs Chromium's
# namespace sandbox, or the container is the sandbox).
#
# It runs as uid 10001 (browser), never root. WORKDIR is /out-browser, where
# the runner binds the run's reports/browser/: @playwright/mcp resolves a file
# name the model chooses against its working directory, and the gateway's
# catalog cannot set one.
#
# scripts/build.sh passes DEBIAN_IMAGE and NODE_IMAGE as our digest-pinned
# mirrors (bases.env).
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG DEBIAN_IMAGE=debian:trixie-slim
ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE} AS server
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev --no-audit --no-fund \
	&& node -e 'const v = require("@playwright/mcp/package.json").version; console.log("@playwright/mcp " + v)'

FROM ${DEBIAN_IMAGE}
ARG TARGETARCH
COPY --from=server /usr/local/bin/node /usr/local/bin/node
COPY --from=server /app /app
COPY source.env install.sh /agentry/
RUN TARGETARCH="$TARGETARCH" sh /agentry/install.sh /agentry/source.env /app/node_modules/playwright-core/browsers.json /agentry
COPY --from=server /usr/local/LICENSE /usr/share/licenses/agentry-browser/node/LICENSE
COPY policy.json /etc/chromium/policies/managed/agentry.json
RUN find / -xdev -type f -perm /6000 -exec chmod ug-s {} + \
	&& groupadd -g 10001 browser \
	&& useradd -u 10001 -g browser -d /home/browser -m -s /usr/sbin/nologin browser \
	&& install -d -o 10001 -g 10001 -m 0755 /out-browser \
	&& install -d -m 0755 /etc/agentry/browser \
	&& for p in @playwright/mcp playwright playwright-core; do \
		install -d "/usr/share/licenses/agentry-browser/$p" \
		&& cp /app/node_modules/$p/LICENSE "/usr/share/licenses/agentry-browser/$p/"; \
	done \
	&& cp /app/node_modules/playwright-core/NOTICE /app/node_modules/playwright-core/ThirdPartyNotices.txt \
		/usr/share/licenses/agentry-browser/playwright-core/ \
	&& install -d /usr/share/licenses/agentry-browser/chromium \
	&& cp /usr/share/doc/chromium/copyright /usr/share/licenses/agentry-browser/chromium/ \
	&& { \
		echo "mcp $(node -p 'require("/app/node_modules/@playwright/mcp/package.json").version')"; \
		echo "playwright $(node -p 'require("/app/node_modules/playwright-core/package.json").version')"; \
		echo "node $(node --version)"; \
		cat /agentry/chromium.record; \
	} >/etc/agentry/browser/record \
	&& rm -rf /agentry \
	&& dpkg-query -W -f '${Package} ${Version}\n' | sort >/etc/agentry/browser/packages
ENV PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/lib/chromium/chromium \
	NODE_ENV=production \
	HOME=/home/browser
USER 10001:10001
WORKDIR /out-browser
ENTRYPOINT ["/usr/local/bin/node", "/app/node_modules/@playwright/mcp/cli.js"]
