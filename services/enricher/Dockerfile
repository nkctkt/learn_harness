# syntax=docker/dockerfile:1.7
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS build
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev --no-install-project
COPY enricher ./enricher

FROM python:3.13-slim-bookworm AS runtime
WORKDIR /app
RUN useradd --system --uid 10001 app
COPY --from=build /app /app
ENV PATH=/app/.venv/bin:$PATH
USER app
EXPOSE 8000
CMD ["uvicorn", "enricher.main:app", "--host", "0.0.0.0", "--port", "8000"]
