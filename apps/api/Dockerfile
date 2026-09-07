# syntax=docker/dockerfile:1.7
# ---- build: 全依存で tsc を実行し、JS だけを成果物にする ----
FROM node:24-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json apps/api/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --ignore-scripts --filter @shelf/api
COPY apps/api ./apps/api
RUN pnpm --filter @shelf/api build

# ---- deps: 実行時依存だけを解決する(devDependencies を image に入れない) ----
FROM node:24-alpine AS deps
RUN corepack enable
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json apps/api/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --ignore-scripts --filter @shelf/api --prod

# ---- runtime: 非 root、JS と migration と実行時依存のみ ----
FROM node:24-alpine AS runtime
ENV NODE_ENV=production PORT=3000
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /repo
COPY --from=deps /repo/node_modules ./node_modules
COPY --from=deps /repo/apps/api/node_modules ./apps/api/node_modules
COPY --from=build /repo/apps/api/dist ./apps/api/dist
COPY apps/api/package.json ./apps/api/
COPY apps/api/drizzle ./apps/api/drizzle
USER 10001
WORKDIR /repo/apps/api
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["wget", "-qO-", "http://127.0.0.1:3000/health"]
CMD ["node", "dist/index.js"]
