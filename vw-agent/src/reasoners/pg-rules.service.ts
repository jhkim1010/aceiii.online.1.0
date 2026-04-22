// PG Rules — PgPoller 스냅샷을 받아 RULE-01/02/03 판정
// ----------------------------------------------------------------------------
// RULE-01: 활성 connection 수 임계 초과 (WARN/CRIT)
//   - 기준: THRESHOLD_PG_ACTIVE_WARN / CRIT 환경변수
//   - dedup_key: "RULE-01:active"
// RULE-02: 장시간 실행 쿼리 (>= 10s) 또는 idle in transaction (>= 30s)
//   - 기준: long_queries 중 age_sec >= 10 (active) / 30 (idle in txn)
//   - dedup_key: "RULE-02:pid=<pid>" (pid 별 억제)
// RULE-03: pool saturation — max_connections 대비 사용률 >= 80%
//   - dedup_key: "RULE-03:saturation"
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';
import {
  PG_SNAPSHOT_EVENT,
  type PgActivityRow,
  type PgSnapshot,
} from '../observers/pg-poller.service';

import { RuleEngineService } from './rule-engine.service';

@Injectable()
export class PgRulesService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PgRulesService.name);
  private warnThreshold = 250;
  private critThreshold = 320;
  private dedupMinutes = 15;
  private readonly onSnapshot = (s: PgSnapshot): void => this.evaluate(s);

  constructor(
    @Inject(ConfigService) private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
    private readonly engine: RuleEngineService,
  ) {}

  onModuleInit(): void {
    this.warnThreshold = this.config.get('THRESHOLD_PG_ACTIVE_WARN', { infer: true });
    this.critThreshold = this.config.get('THRESHOLD_PG_ACTIVE_CRIT', { infer: true });
    this.dedupMinutes = this.config.get('DEDUP_WINDOW_MINUTES', { infer: true });
    this.bus.on(PG_SNAPSHOT_EVENT, this.onSnapshot);
    this.logger.log(
      `PG Rules 활성 (WARN=${this.warnThreshold}, CRIT=${this.critThreshold}, dedup=${this.dedupMinutes}m)`,
    );
  }

  onModuleDestroy(): void {
    this.bus.off(PG_SNAPSHOT_EVENT, this.onSnapshot);
    this.logger.log('PG Rules 종료');
  }

  private evaluate(snap: PgSnapshot): void {
    try {
      this.checkActiveConn(snap);
      this.checkLongQueries(snap);
      this.checkSaturation(snap);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Rule evaluate 실패: ${msg}`);
    }
  }

  // ---------- RULE-01: active connection 임계 ----------
  private checkActiveConn(s: PgSnapshot): void {
    const active = s.activeConn;
    const severity =
      active >= this.critThreshold ? 'critical' : active >= this.warnThreshold ? 'warn' : null;
    if (!severity) return;

    const title =
      severity === 'critical'
        ? `PG active connection CRIT (${active} ≥ ${this.critThreshold})`
        : `PG active connection WARN (${active} ≥ ${this.warnThreshold})`;
    const detail =
      `total=${s.totalConn} active=${s.activeConn} idle=${s.idleConn} ` +
      `idle_in_txn=${s.idleInTxnConn} max_conn=${s.maxConnections}`;

    this.engine.fire({
      ruleId: 'RULE-01',
      severity,
      title,
      detail,
      dedupKey: `RULE-01:active:${severity}`,
      dedupMinutes: this.dedupMinutes,
      context: {
        totalConn: s.totalConn,
        activeConn: s.activeConn,
        idleConn: s.idleConn,
        idleInTxnConn: s.idleInTxnConn,
        maxConnections: s.maxConnections,
      },
    });
  }

  // ---------- RULE-02: long query / idle in transaction ----------
  private checkLongQueries(s: PgSnapshot): void {
    const IDLE_IN_TXN_THRESHOLD = 30; // 초
    const ACTIVE_LONG_THRESHOLD = 10; // 초 (pg-poller 에서 이미 >=10 필터했지만 명시)

    for (const q of s.longQueries) {
      const isIdleInTxn = q.state === 'idle in transaction';
      const threshold = isIdleInTxn ? IDLE_IN_TXN_THRESHOLD : ACTIVE_LONG_THRESHOLD;
      if (q.query_age_sec < threshold) continue;

      const severity: 'critical' | 'warn' = q.query_age_sec >= 60 ? 'critical' : 'warn';
      const title = isIdleInTxn
        ? `Idle in transaction ${Math.floor(q.query_age_sec)}s (pid=${q.pid})`
        : `Long query ${Math.floor(q.query_age_sec)}s (pid=${q.pid})`;
      const detail = this.truncateQuery(q);

      // pid + state 별로 dedup (같은 pid 가 계속 떠도 윈도우 내 1회만)
      this.engine.fire({
        ruleId: 'RULE-02',
        severity,
        title,
        detail,
        dedupKey: `RULE-02:pid=${q.pid}:state=${q.state ?? 'null'}`,
        dedupMinutes: this.dedupMinutes,
        context: {
          pid: q.pid,
          state: q.state,
          wait_event_type: q.wait_event_type,
          wait_event: q.wait_event,
          age_sec: q.query_age_sec,
          application_name: q.application_name,
          usename: q.usename,
        },
      });
    }
  }

  // ---------- RULE-03: pool saturation ----------
  private checkSaturation(s: PgSnapshot): void {
    if (s.maxConnections <= 0) return;
    const usageRatio = s.totalConn / s.maxConnections;

    // 80% 이상 사용 → WARN, 95% 이상 → CRIT
    const severity = usageRatio >= 0.95 ? 'critical' : usageRatio >= 0.8 ? 'warn' : null;
    if (!severity) return;

    const pct = (usageRatio * 100).toFixed(1);
    const title = `PG pool saturation ${pct}% (${s.totalConn}/${s.maxConnections})`;
    const detail =
      `active=${s.activeConn} idle=${s.idleConn} idle_in_txn=${s.idleInTxnConn}. ` +
      `RULE-03 발화 시 연결 누수/API 급증 점검 필요.`;

    this.engine.fire({
      ruleId: 'RULE-03',
      severity,
      title,
      detail,
      dedupKey: `RULE-03:saturation:${severity}`,
      dedupMinutes: this.dedupMinutes,
      context: {
        totalConn: s.totalConn,
        maxConnections: s.maxConnections,
        usageRatio,
      },
    });
  }

  private truncateQuery(q: PgActivityRow): string {
    const head = q.query.replace(/\s+/g, ' ').trim().slice(0, 200);
    const wait = q.wait_event_type ? ` wait=${q.wait_event_type}:${q.wait_event}` : '';

    return `app=${q.application_name ?? '?'} user=${q.usename ?? '?'}${wait}\nquery: ${head}`;
  }
}
