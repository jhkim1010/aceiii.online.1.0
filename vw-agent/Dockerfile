# =============================================================================
# vw-agent Dockerfile — 운영 서버 감시 에이전트 (M1 MVP)
# -----------------------------------------------------------------------------
# 구조:
#   Stage 1 (builder): node:20-bookworm-slim 기반, 네이티브 빌드 도구 + TypeScript 컴파일
#   Stage 2 (runtime): node:20-bookworm-slim 기반, 런타임만, 최소 패키지
#
# 런타임 크기 최소화 원칙:
#   - production dependency 만 설치
#   - TypeScript, eslint, @nestjs/cli 등 devDeps 제외
#   - better-sqlite3 네이티브 바이너리는 builder 에서 컴파일하여 복사
#   - /app/data (SQLite), /app/logs 는 volume 마운트 포인트
#
# 보안:
#   - root 가 아닌 node 유저로 실행
#   - healthcheck 내장
# =============================================================================

# ---------- Stage 1: builder ----------
FROM node:20-bookworm-slim AS builder

# better-sqlite3 네이티브 컴파일에 필요한 도구
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 의존성 캐시 최적화 — package*.json 먼저
COPY package*.json ./
RUN npm ci

# 소스 복사 후 빌드
COPY tsconfig.json nest-cli.json ./
COPY src ./src
RUN npm run build

# production dependency 만 남기고 prune
RUN npm prune --omit=dev

# ---------- Stage 2: runtime ----------
FROM node:20-bookworm-slim AS runtime

# 런타임 필수 패키지 (tini = PID 1 시그널 처리, curl = healthcheck 용)
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 작업 디렉터리 + 데이터/로그 디렉터리
WORKDIR /app
RUN mkdir -p /app/data /app/logs \
    && chown -R node:node /app

# builder 산출물 복사
COPY --from=builder --chown=node:node /build/node_modules ./node_modules
COPY --from=builder --chown=node:node /build/dist ./dist
COPY --from=builder --chown=node:node /build/package.json ./package.json

# Docker socket GID 매핑을 위해 docker group 생성 (compose 에서 GID 전달)
# 기본값 999 — docker-compose.yml 에서 `group_add: - "${DOCKER_GID:-999}"` 로 덮어쓸 수 있음
ARG DOCKER_GID=999
RUN groupadd -g ${DOCKER_GID} docker 2>/dev/null || true \
    && usermod -aG docker node 2>/dev/null || true

USER node

# 로그/데이터 볼륨 마운트 포인트
VOLUME ["/app/data", "/app/logs"]

# HTTP /health 엔드포인트 (PORT 기본 5999)
EXPOSE 5999

# Healthcheck — /health 에 200 OK 인지 확인
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT:-5999}/health" || exit 1

# tini 로 PID 1 신호 처리 (SIGTERM 시 NestJS onModuleDestroy 정상 실행 보장)
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/main.js"]
