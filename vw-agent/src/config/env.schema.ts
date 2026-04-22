// 환경변수 스키마 정의 (zod 기반 타입 안전 검증)
// 기동 시점에 검증 실패하면 프로세스 exit(1) — fail-fast 원칙
import { z } from 'zod';

// ---------- 스키마 정의 ----------
export const envSchema = z.object({
  // 런타임 모드
  NODE_ENV: z.enum(['development', 'production', 'test']).default('production'),
  PORT: z.coerce.number().int().min(1).max(65535).default(5999),

  // PostgreSQL 감시 전용 read-only 계정 (pool max=3 고정)
  PG_HOST: z.string().min(1).default('host.docker.internal'),
  PG_PORT: z.coerce.number().int().min(1).max(65535).default(5432),
  PG_DATABASE: z.string().min(1).default('ventago'),
  PG_WATCHER_USER: z.string().min(1).default('ventago_watcher'),
  PG_WATCHER_PASSWORD: z.string().min(8, 'PG_WATCHER_PASSWORD 는 최소 8자'),

  // 모니터링 대상 로그 경로 (api-ventago/logs/)
  API_LOG_DIR: z.string().min(1),

  // Docker socket 접근 (host socket 을 bind-mount)
  DOCKER_SOCKET_PATH: z.string().default('/var/run/docker.sock'),
  // 모니터링 대상 컨테이너 이름 prefix (콤마 구분, 빈값이면 전체)
  // 예: "api_ventago,ventago_app,dbpostgres"
  DOCKER_MONITOR_PREFIXES: z.string().default(''),

  // Telegram Bot (M1 의 유일한 알림 채널)
  TELEGRAM_BOT_TOKEN: z.string().min(10, 'TELEGRAM_BOT_TOKEN 필수'),
  TELEGRAM_CHAT_ID: z.string().min(1, 'TELEGRAM_CHAT_ID 필수'),

  // SQLite 이벤트 저장소 경로 (컨테이너 내부)
  SQLITE_PATH: z.string().default('/app/data/vw-agent.db'),

  // 임계치 (RULE 기본값)
  THRESHOLD_PG_ACTIVE_WARN: z.coerce.number().int().min(1).default(150),
  THRESHOLD_PG_ACTIVE_CRIT: z.coerce.number().int().min(1).default(200),
  THRESHOLD_DISK_WARN_PERCENT: z.coerce.number().int().min(1).max(100).default(80),
  THRESHOLD_DISK_CRIT_PERCENT: z.coerce.number().int().min(1).max(100).default(90),
  THRESHOLD_AGENT_OFFLINE_MINUTES: z.coerce.number().int().min(1).default(5),

  // 루프 주기 (초)
  PG_POLL_INTERVAL_SEC: z.coerce.number().int().min(5).default(30),
  DOCKER_POLL_INTERVAL_SEC: z.coerce.number().int().min(5).default(60),
  AGENT_POLL_INTERVAL_SEC: z.coerce.number().int().min(5).default(60),
  HEARTBEAT_INTERVAL_MIN: z.coerce.number().int().min(1).default(30),

  // 중복 억제 (동일 알림 재발화 금지 시간)
  DEDUP_WINDOW_MINUTES: z.coerce.number().int().min(1).default(15),
});

// ---------- 타입 export ----------
export type Env = z.infer<typeof envSchema>;

/**
 * process.env 를 검증하여 타입 안전한 Env 객체로 반환.
 * 실패 시 상세 메시지와 함께 process.exit(1).
 */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(source);

  if (!parsed.success) {
    // eslint-disable-next-line no-console
    console.error('[vw-agent] 환경변수 검증 실패:');
    for (const issue of parsed.error.issues) {
      // eslint-disable-next-line no-console
      console.error(`  - ${issue.path.join('.')}: ${issue.message}`);
    }
    process.exit(1);
  }

  return parsed.data;
}
