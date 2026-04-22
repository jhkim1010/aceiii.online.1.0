// /health 엔드포인트 — T22 강화판
// ----------------------------------------------------------------------------
// 목적:
//   - Docker healthcheck + 운영자 대시보드용 상태 페이지
//   - PG read-only pool stats (total/idle/waiting) 노출 → pool 낭비 감시의 핵심
//   - SQLite 이벤트 수 + 규칙별 최근 발화 시각
//   - Telegram 구성 여부 (토큰 유무만 — 값은 노출 금지)
// 안전 규칙:
//   - 이 엔드포인트는 절대 PG 쿼리를 보내지 않는다 (pool 낭비 방지)
//   - pool stats 는 pg 드라이버 내부 카운터(메모리)만 참조 → 비용 0
//   - SQLite 는 동기 호출이지만 최근 1건 조회만 (부하 없음)
// ----------------------------------------------------------------------------
import { Controller, Get, Inject } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { Env } from '../config/env.schema';
import { PgReadonlyService } from '../db/pg-readonly.service';
import { SqliteService } from '../db/sqlite.service';

export interface HealthResponse {
  status: 'ok' | 'degraded';
  uptime_sec: number;
  version: string;
  started_at: string;
  pg_pool: {
    total: number;
    idle: number;
    waiting: number;
    max: number;
  };
  sqlite: {
    recent_events: number;
    last_event_at: string | null;
    last_heartbeat_at: string | null;
  };
  telegram: {
    configured: boolean;
  };
  rules: Record<string, { last_fired_at: string | null; count_24h: number }>;
}

@Controller('health')
export class HealthController {
  private readonly startedAt = Date.now();
  private readonly startedAtIso = new Date().toISOString();

  constructor(
    private readonly pg: PgReadonlyService,
    private readonly sqlite: SqliteService,
    @Inject(ConfigService) private readonly config: ConfigService<Env, true>,
  ) {}

  @Get()
  check(): HealthResponse {
    const pgStats = this.pg.getStats();
    const recent = this.sqlite.recentEvents(200);

    // 최근 24시간 이벤트만 집계 (규칙별 카운트)
    const now = Date.now();
    const dayAgo = now - 24 * 60 * 60 * 1000;
    const rules: Record<string, { last_fired_at: string | null; count_24h: number }> = {};

    for (const e of recent) {
      const ts = Date.parse(`${e.created_at}Z`);
      if (Number.isNaN(ts) || ts < dayAgo) continue;

      const entry = rules[e.rule_id] ?? { last_fired_at: null, count_24h: 0 };
      entry.count_24h += 1;

      // 목록이 DESC 정렬이므로 최초 만난 값이 가장 최근
      if (entry.last_fired_at === null) entry.last_fired_at = `${e.created_at}Z`;
      rules[e.rule_id] = entry;
    }

    const lastEvent = recent[0] ?? null;
    const lastHeartbeat = this.sqlite.lastHeartbeat();

    // degraded 판정: pool waiting > 0 이거나 pool total == 0 (미초기화)
    const degraded = pgStats.waitingCount > 0 || pgStats.totalCount === 0;

    const telegramToken = this.config.get('TELEGRAM_BOT_TOKEN', { infer: true });

    return {
      status: degraded ? 'degraded' : 'ok',
      uptime_sec: Math.floor((now - this.startedAt) / 1000),
      version: process.env.npm_package_version ?? '0.1.0',
      started_at: this.startedAtIso,
      pg_pool: {
        total: pgStats.totalCount,
        idle: pgStats.idleCount,
        waiting: pgStats.waitingCount,
        max: 3,
      },
      sqlite: {
        recent_events: recent.length,
        last_event_at: lastEvent ? `${lastEvent.created_at}Z` : null,
        last_heartbeat_at: lastHeartbeat,
      },
      telegram: {
        configured: Boolean(telegramToken && telegramToken.length > 0),
      },
      rules,
    };
  }
}
