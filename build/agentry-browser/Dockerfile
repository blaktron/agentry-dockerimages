# agentry-browser: the browser server image, Microsoft's @playwright/mcp and
# the Chrome for Testing build of the Playwright it pins, for a QuickAgent that
# declares capabilities.browser (agentry-notes plans/browser-testing.md §4, §7,
# D3, D5, D14; agentry-dockerimages#82).
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
#                        (Playwright needs Node 20 or later; noble's is 18)
#   /ms-playwright       Chrome for Testing at the revision the lockfile's
#                        playwright-core names, held to source.env's SHA-256
#                        (fetch.sh). The full build, not the headless shell:
#                        @playwright/mcp's --browser chromium launches it, and
#                        the shell ignores enterprise policies (M1)
#   /etc/opt/chrome_for_testing/policies/managed/agentry.json
#                        the Chrome policy (policy.json), the one path this
#                        build reads. EncryptedClientHelloEnabled false is
#                        what lets the browse proxy's SNI check pass: no
#                        launch flag stops Chromium's GREASE ECH (M1). The
#                        rest turns off QUIC, DNS-over-HTTPS, non-proxied
#                        WebRTC UDP and Google's background services
#   /etc/agentry/browser/record
#                        one line each for the server, Playwright, Node and
#                        the browser (revision, version, architecture and
#                        archive SHA-256), for the receipt
#   /etc/agentry/browser/packages
#                        every Debian package installed, name and version
#   /usr/share/licenses/agentry-browser
#                        Node's LICENSE, the three npm packages' LICENSE (and
#                        Playwright's NOTICE and ThirdPartyNotices.txt), and
#                        Chrome for Testing's ABOUT, which points at the
#                        credits the browser itself carries (chrome://credits)
#
# The system libraries come from Ubuntu's archive through Playwright's own
# install-deps for chromium, which names the packages for this release; their
# versions are the archive's on the day of the build, recorded in
# /etc/agentry/browser/packages, not pinned (as apk's are recorded for the
# host link image). No
# file is setuid or setgid: the base's are stripped, and Chrome's own
# chrome_sandbox helper is not made one (the runner runs Chromium's namespace
# sandbox, or the container is the sandbox).
#
# It runs as uid 10001 (browser), never root. WORKDIR is /out-browser, where
# the runner binds the run's reports/browser/: @playwright/mcp resolves a file
# name the model chooses against its working directory, and the gateway's
# catalog cannot set one (M1).
#
# scripts/build.sh passes UBUNTU_IMAGE and NODE_IMAGE as our digest-pinned
# mirrors (bases.env).
#
# No `# syntax=` line: the Dockerfile frontend built into BuildKit reads this,
# so no frontend image is pulled from a floating tag.

ARG UBUNTU_IMAGE=ubuntu:noble
ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE} AS server
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev --no-audit --no-fund \
	&& node -e 'const v = require("@playwright/mcp/package.json").version; console.log("@playwright/mcp " + v)'

FROM ${UBUNTU_IMAGE} AS fetch
ARG TARGETARCH
# Ubuntu's archive fails now and then; the whole step is retried half a
# minute apart, and a failure is never taken as a success.
RUN for try in 1 2 3 4 5; do \
		{ apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip; } && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done
COPY --from=server /usr/local/bin/node /usr/local/bin/node
COPY --from=server /app/node_modules/playwright-core/browsers.json /agentry/browsers.json
COPY source.env fetch.sh /agentry/
RUN TARGETARCH="$TARGETARCH" sh /agentry/fetch.sh /agentry/source.env /agentry/browsers.json /ms-playwright

FROM ${UBUNTU_IMAGE}
COPY --from=server /usr/local/bin/node /usr/local/bin/node
COPY --from=server /app /app
# install-deps runs apt-get against the same archive; retried the same way.
RUN for try in 1 2 3 4 5; do \
		node /app/node_modules/playwright-core/cli.js install-deps chromium && break; \
		[ "$try" = 5 ] && exit 1; sleep 30; \
	done \
	&& rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
COPY --from=fetch /ms-playwright /ms-playwright
COPY --from=server /usr/local/LICENSE /usr/share/licenses/agentry-browser/node/LICENSE
COPY policy.json /etc/opt/chrome_for_testing/policies/managed/agentry.json
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
	&& install -d /usr/share/licenses/agentry-browser/chrome-for-testing \
	&& cp /ms-playwright/chromium-*/chrome-linux*/ABOUT /usr/share/licenses/agentry-browser/chrome-for-testing/ \
	&& { \
		echo "mcp $(node -p 'require("/app/node_modules/@playwright/mcp/package.json").version')"; \
		echo "playwright $(node -p 'require("/app/node_modules/playwright-core/package.json").version')"; \
		echo "node $(node --version)"; \
		cat /ms-playwright/chromium.record; \
	} >/etc/agentry/browser/record \
	&& rm /ms-playwright/chromium.record \
	&& dpkg-query -W -f '${Package} ${Version}\n' | sort >/etc/agentry/browser/packages
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
	NODE_ENV=production \
	HOME=/home/browser
USER 10001:10001
WORKDIR /out-browser
ENTRYPOINT ["/usr/local/bin/node", "/app/node_modules/@playwright/mcp/cli.js"]
