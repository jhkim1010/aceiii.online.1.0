// PG Poller — 운영 PostgreSQL 메트릭 주기 수집
// ----------------------------------------------------------------------------
// 책임:
//   - pg_stat_activity / pg_stat_database 등에서 active conn, idle in txn,
//     long-running query, lock wait 등을 주기적으로 SELECT
//   - 수집 결과를 EventEmitter 로 방출 → PgRulesService 가 구독
// 안전 규칙:
//   - 모든 쿼리는 PgReadonlyService.query() 경유 (SELECT 만 허용, 3s timeout)
//   - 한 tick 당 최대 3개 쿼리 이하 — pool(max=3) 낭비 방지
//   - 실패해도 서비스 중단 금지 (warn 로그 + 다음 tick 재시도)
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';
import { PgReadonlyService } from '../db/pg-readonly.service';

export interface PgActivityRow {
  pid: number;
  state: string | null;
  wait_event_type: string | null;
  wait_event: string | null;
  query_age_sec: number;
  query: string;
  application_name: string | null;
  usename: string | null;
}

export interface PgSnapshot {
  at: Date;
  totalConn: number;
  activeConn: number;
  idleConn: number;
  idleInTxnConn: number;
  longQueries: PgActivityRow[];
  maxConnections: number;
}

export const PG_SNAPSHOT_EVENT = 'pg.snapshot';

@Injectable()
export class PgPollerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PgPollerService.name);
  private timer: NodeJS.Timeout | null = null;
  private intervalSec = 30;
  private running = false;

  constructor(
    private readonly pg: PgReadonlyService,
    private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
  ) {}

  onModuleInit(): void {
    this.intervalSec = this.config.get('PG_POLL_INTERVAL_SEC', { infer: true });
    this.logger.log(`PG Poller 시작 (주기=${this.intervalSec}s)`);

    // 최초 1회는 약간 지연 (app 완전 부팅 대기)
    this.timer = setTimeout(() => {
      void this.tick();
      this.timer = setInterval(() => void this.tick(), this.intervalSec * 1000);
    }, 3_000);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.logger.log('PG Poller 종료');
  }

  private async tick(): Promise<void> {
    // 이전 tick 이 아직 끝나지 않았으면 건너뛰기 (pool 낭비 방지)
    if (this.running) {
      this.logger.warn('이전 tick 진행 중 — 이번 tick 건너뜁니다');

      return;
    }

    this.running = true;
    try {
      const snapshot = await this.collect();
      this.bus.emit(PG_SNAPSHOT_EVENT, snapshot);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`PG 메트릭 수집 실패: ${msg}`);
    } finally {
      this.running = false;
    }
  }

  /**
   * 한 tick 에 실행하는 쿼리 (총 2회 — pool 낭비 최소화)
   *   1) activity 집계 + long query 조회 (단일 쿼리 CTE)
   *   2) max_connections 조회 (SHOW)
   */
  private async collect(): Promise<PgSnapshot> {
    // [1] pg_stat_activity 한 번에 집계 + long query TOP-N
    //     - query_start NULL (idle 이전 커넥션) 은 age 0 으로 계산
    const activitySql = `
      WITH acts AS (
        SELECT pid, state, wait_event_type, wait_event,
               COALESCE(EXTRACT(EPOCH FROM (NOW() - query_start)), 0)::float AS age_sec,
               query, application_name, usename
          FROM pg_stat_activity
         WHERE datname = current_database()
           AND backend_type = 'client backend'
      )
      SELECT
        (SELECT COUNT(*) FROM acts)                                   AS total_conn,
        (SELECT COUNT(*) FROM acts WHERE state = 'active')            AS active_conn,
        (SELECT COUNT(*) FROM acts WHERE state = 'idle')              AS idle_conn,
        (SELECT COUNT(*) FROM acts WHERE state = 'idle in transaction') AS idle_in_txn,
        COALESCE(
          (SELECT json_agg(row_to_json(t))
             FROM (
               SELECT pid, state, wait_event_type, wait_event,
                      age_sec AS query_age_sec,
                      LEFT(query, 500) AS query,
                      application_name, usename
                 FROM acts
                WHERE state = 'active' AND age_sec >= 10
                ORDER BY age_sec DESC
                LIMIT 10
             ) t),
          '[]'::json
        ) AS long_queries
    `;

    const result = await this.pg.query<{
      total_conn: string | number;
      active_conn: string | number;
      idle_conn: string | number;
      idle_in_txn: string | number;
      long_queries: PgActivityRow[] | null;
    }>(activitySql);

    const row = result.rows[0];

    // [2] max_connections (SHOW — 가볍지만 별도 커넥션)
    const showRes = await this.pg.query<{ max_connections: string }>(
      `SHOW max_connections`,
    );
    const maxConnections = Number(showRes.rows[0]?.max_connections ?? 0);

    return {
      at: new Date(),
      totalConn: Number(row.total_conn),
      activeConn: Number(row.active_conn),
      idleConn: Number(row.idle_conn),
      idleInTxnConn: Number(row.idle_in_txn),
      longQueries: row.long_queries ?? [],
      maxConnections,
    };
  }
}
