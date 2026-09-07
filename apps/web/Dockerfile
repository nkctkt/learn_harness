# syntax=docker/dockerfile:1.7
FROM node:24-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json apps/web/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --ignore-scripts --filter @shelf/web
COPY apps/web ./apps/web
RUN pnpm --filter @shelf/web build

# 静的配信。/api/* は同一オリジンで api コンテナへ proxy する(CORS を開けない)。
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY infra/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/apps/web/dist /usr/share/nginx/html
# nginx-unprivileged は既定で uid 101 で動くが、スキャナは USER 命令の有無で判定するので明示する
USER 101
EXPOSE 8080
