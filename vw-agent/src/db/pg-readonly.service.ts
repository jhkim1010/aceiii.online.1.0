// 운영 PostgreSQL 감시 전용 read-only pool
// ----------------------------------------------------------------------------
// SAFETY (절대 변경 금지):
// - max=3 (운영 max_connections=300 의 1%, 운영 부하에 영향 없음)
// - 전용 계정 ventago_watcher (SELECT-only, statement_timeout=3s)
// - application_name='vw-agent-watcher' (운영자가 pg_stat_activity 에서 식별 가능)
// - onShutdown 에서 반드시 pool.end() — 누수 방지
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';

import type { Env } from '../config/env.schema';

@Injectable()
export class PgReadonlyService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PgReadonlyService.name);
  private pool: Pool | null = null;

  constructor(@Inject(ConfigService) private readonly config: ConfigService<Env, true>) {}

  onModuleInit(): void {
    const host = this.config.get('PG_HOST', { infer: true });
    const port = this.config.get('PG_PORT', { infer: true });
    const database = this.config.get('PG_DATABASE', { infer: true });
    const user = this.config.get('PG_WATCHER_USER', { infer: true });
    const password = this.config.get('PG_WATCHER_PASSWORD', { infer: true });

    this.pool = new Pool({
      host,
      port,
      database,
      user,
      password,
      // 안전 기본값 — 변경하지 말 것
      max: 3,
      min: 1,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
      application_name: 'vw-agent-watcher',
      statement_timeout: 3_000,
      query_timeout: 5_000,
      keepAlive: true,
    });

    this.pool.on('error', (err) => {
      // pool 자체 에러는 idle client 의 비정상 종료에서 주로 발생
      this.logger.error(`PG pool 오류: ${err.message}`, err.stack);
    });

    this.logger.log(
      `PG read-only pool 초기화 (host=${host}:${port} db=${database} user=${user} max=3)`,
    );
  }

  async onModuleDestroy(): Promise<void> {
    if (this.pool) {
      this.logger.log('PG pool 종료 중...');
      await this.pool.end();
      this.pool = null;
    }
  }

  /**
   * read-only 쿼리 실행. SELECT/SHOW/EXPLAIN 만 허용.
   * INSERT/UPDATE/DELETE/DDL 은 ventago_watcher 권한으로 차단되지만,
   * 클라이언트 측에서도 1차 방어를 위해 prefix 체크.
   */
  async query<T extends QueryResultRow = QueryResultRow>(
    sql: string,
    params: unknown[] = [],
  ): Promise<QueryResult<T>> {
    if (!this.pool) {
      throw new Error('PG pool 이 초기화되지 않았습니다');
    }

    const trimmed = sql.trim().toUpperCase();
    const allowed = ['SELECT', 'SHOW', 'EXPLAIN', 'WITH'];
    const isAllowed = allowed.some((p) => trimmed.startsWith(p));

    if (!isAllowed) {
      throw new Error(
        `read-only 쿼리만 허용됩니다 (SELECT/SHOW/EXPLAIN/WITH). 시도: ${trimmed.slice(0, 30)}`,
      );
    }

    const client: PoolClient = await this.pool.connect();
    try {
      return await client.query<T>(sql, params);
    } finally {
      // 반드시 release — 누수 방지의 핵심
      client.release();
    }
  }

  /**
   * pool 내부 상태 노출 — /health 와 통계용
   */
  getStats(): { totalCount: number; idleCount: number; waitingCount: number } {
    if (!this.pool) {
      return { totalCount: 0, idleCount: 0, waitingCount: 0 };
    }

    return {
      totalCount: this.pool.totalCount,
      idleCount: this.pool.idleCount,
      waitingCount: this.pool.waitingCount,
    };
  }
}
