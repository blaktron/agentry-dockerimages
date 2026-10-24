# syntax=docker/dockerfile:1
#
# Softeria's ms-365-mcp-server, built from pinned upstream source.
#
#   upstream   github.com/Softeria/ms-365-mcp-server
#   commit     source.env beside this file
#   licence    MIT
#   reference  the project's Dockerfile at that commit,
#              https://github.com/Softeria/ms-365-mcp-server/blob/<commit>/Dockerfile
#
# Changes from upstream's Dockerfile:
#
#   1. Every base is an ARG, and scripts/build.sh passes our digest-pinned
#      mirror of node:24-alpine for it, so no mutable tag is resolved at build
#      time. Upstream resolves node:24-alpine by tag.
#   2. Microsoft Graph's two OpenAPI documents (v1.0 and beta), which
#      upstream's generator downloads from msgraph-metadata's moving master
#      branch, are fetched in a stage of their own at the pinned commit below
#      and refused unless each matches its sha256. The generator finds them in
#      place and downloads nothing.
#   3. The generator's code generator, openapi-zod-client, which upstream runs
#      with `npx -y` at whatever version is newest, is installed from the
#      lockfile in tools/ (version 1.18.3 and its dependencies, each with its
#      integrity hash), and the generator is pointed at it.
#   4. Every `npm ci` runs with --ignore-scripts, so no package's install
#      script runs at build time.
#   5. In stdio mode the server no longer registers its six account tools
#      (login, logout, verify-login, list-accounts, select-account,
#      remove-account) unless --enable-auth-tools is given; upstream always
#      registers them in stdio mode. The model must not be able to sign the
#      person out or start a sign-in. The sign-in is the runner's, through
#      --login in a one-shot of its own.
#   6. package.json's version is the release's (upstream's release tooling
#      sets it at publish time; the source carries 0.0.0-development), so
#      --version names it.
#   7. The runtime stage adds the token cache's keeper, /opt/agentry/cache-wrap
#      (cache-wrap.mjs beside this file), given as MS365_MCP_AUTH_CACHE_COMMAND:
#      it seals each cache entry with AES-256-GCM under the key in
#      MS365_CACHE_KEY and refuses to run without one, so the server's volume
#      alone opens nothing. keytar is off (MS365_MCP_USE_KEYTAR=0), so the
#      server never falls back to a key file of its own beside the cache.
#   8. The log goes to /tmp (a tmpfs where the runner runs it) at level
#      error, and the audit log is off: at its default level the server logs
#      every Graph request's URL and body, and its audit log every tool call,
#      which would leave mail content on the volume.
#   9. The server runs as uid 10001 with its state at /persist/ms365, every
#      setuid and setgid bit stripped, its licence at
#      /usr/share/licenses/ms-365-mcp-server/LICENSE, and the image's labels
#      naming this build.
#
# Everything else matches upstream: the build (`npm ci`, `npm run generate`,
# `npm run build`), the runtime's production dependencies from the same
# lockfile, and the entrypoint, node dist/index.js.

ARG NODE_IMAGE=node:24-alpine

# Microsoft Graph's OpenAPI documents at a pinned msgraph-metadata commit.
FROM ${NODE_IMAGE} AS openapi
ARG GRAPH_METADATA_COMMIT=1fd0ef510f79f3dadb3e083bdebc9496f939a11c
ARG GRAPH_V1_SHA256=69de68b2c895bc608a58229e662e2b3eeb23524385516afc250ff0b8f165ff29
ARG GRAPH_BETA_SHA256=1cc7badd129364daec0c97b37aa2785e5d4b299fceef866170d4f576c263caef
WORKDIR /openapi
RUN base="https://raw.githubusercontent.com/microsoftgraph/msgraph-metadata/${GRAPH_METADATA_COMMIT}/openapi" \
	&& wget -q -O openapi.yaml "$base/v1.0/openapi.yaml" \
	&& wget -q -O openapi-beta.yaml "$base/beta/openapi.yaml" \
	&& printf '%s  openapi.yaml\n%s  openapi-beta.yaml\n' "$GRAPH_V1_SHA256" "$GRAPH_BETA_SHA256" | sha256sum -c -

# The code generator, from our lockfile.
FROM ${NODE_IMAGE} AS tools
WORKDIR /tools
COPY --from=agentry tools/package.json tools/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund

FROM ${NODE_IMAGE} AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY . .
COPY --from=openapi /openapi/ ./openapi/
COPY --from=tools /tools/node_modules /tools/node_modules
ARG GIT_TAG
# The generator runs our pinned openapi-zod-client; the server leaves its
# account tools out of stdio mode; package.json names the release. Each edit
# is refused if it did not take, so a change upstream fails the build here.
RUN sed -i 's#npx -y openapi-zod-client #/tools/node_modules/.bin/openapi-zod-client #' bin/modules/generate-mcp-tools.mjs \
	&& grep -qF '/tools/node_modules/.bin/openapi-zod-client ' bin/modules/generate-mcp-tools.mjs \
	&& ! grep -qF 'npx -y openapi-zod-client' bin/modules/generate-mcp-tools.mjs \
	&& sed -i 's#const shouldRegisterAuthTools = !this.options.http || this.options.enableAuthTools;#const shouldRegisterAuthTools = Boolean(this.options.enableAuthTools);#' src/server.ts \
	&& grep -qF 'const shouldRegisterAuthTools = Boolean(this.options.enableAuthTools);' src/server.ts \
	&& npm pkg set "version=${GIT_TAG#v}"
RUN npm run generate && npm run build

FROM ${NODE_IMAGE}
WORKDIR /app
COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev --no-audit --no-fund \
	&& npm cache clean --force \
	&& mkdir -p /persist \
	&& adduser -D -u 10001 -h /persist/ms365 ms365 \
	&& chmod 0700 /persist/ms365 \
	&& find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
COPY --from=build /app/dist ./dist
COPY --from=build /app/LICENSE /usr/share/licenses/ms-365-mcp-server/LICENSE
COPY --from=agentry --chmod=0755 cache-wrap.mjs /opt/agentry/cache-wrap
ENV NODE_ENV=production \
	HOME=/persist/ms365 \
	MS365_CACHE_DIR=/persist/ms365/cache \
	MS365_MCP_AUTH_CACHE_COMMAND=/opt/agentry/cache-wrap \
	MS365_MCP_USE_KEYTAR=0 \
	MS365_MCP_LOG_DIR=/tmp/ms365-logs \
	LOG_LEVEL=error \
	MS365_MCP_AUDIT_LOG=false
USER ms365
ENTRYPOINT ["node", "/app/dist/index.js"]

LABEL org.opencontainers.image.title="ms-365-mcp-server (built by Agentry)" \
	org.opencontainers.image.source="https://github.com/Softeria/ms-365-mcp-server" \
	org.opencontainers.image.licenses="MIT" \
	org.opencontainers.image.description="Softeria's ms-365-mcp-server built by Agentry from a pinned upstream commit, its token cache sealed under a key the runner gives it"
