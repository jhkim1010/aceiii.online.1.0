// Agent Poller — branch_agents 테이블 주기 조회 (RULE-07)
// ----------------------------------------------------------------------------
// 책임:
//   - 60초 주기로 public.branch_agents 에서 id/label/is_online/last_seen_at 조회
//   - EventBus 로 스냅샷 방출 → AgentRulesService 가 구독
// 안전 규칙:
//   - 단일 SELECT (tick 당 1쿼리) — pool max=3 낭비 없음
//   - information_schema 로 테이블 존재 확인 후 쿼리 (로컬 dev 에 테이블 없어도 안전)
//   - 존재하지 않으면 1회 warn 로그 후 자동 비활성화
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';
import { PgReadonlyService } from '../db/pg-readonly.service';

export interface BranchAgentRow {
  id: number;
  branch_id: number;
  agent_type: string;
  label: string;
  is_online: boolean;
  last_seen_at: string | null;
  seconds_since_seen: number | null;
}

export interface AgentSnapshot {
  at: Date;
  ok: boolean;
  reason?: string;
  agents: BranchAgentRow[];
}

export const AGENT_SNAPSHOT_EVENT = 'agent.snapshot';

@Injectable()
export class AgentPollerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AgentPollerService.name);
  private timer: NodeJS.Timeout | null = null;
  private intervalSec = 60;
  private running = false;
  private disabled = false;

  constructor(
    private readonly pg: PgReadonlyService,
    private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
  ) {}

  onModuleInit(): void {
    // RULE-07 영구 비활성화 플래그 — false 면 polling 자체를 안 함
    // (불필요한 PG SELECT 60초 주기 제거 → pool 낭비 방지)
    const rule07Enabled = this.config.get('RULE_07_ENABLED', { infer: true });

    if (!rule07Enabled) {
      this.disabled = true;
      this.logger.warn(
        'Agent Poller 비활성 (RULE_07_ENABLED=false) — branch_agents 주기 조회 생략',
      );

      return;
    }

    this.intervalSec = this.config.get('AGENT_POLL_INTERVAL_SEC', { infer: true });
    this.logger.log(`Agent Poller 시작 (주기=${this.intervalSec}s)`);

    // 7초 지연 후 시작 — PgPoller (3s) / DockerPoller (5s) 와 겹침 분산
    this.timer = setTimeout(() => {
      void this.tick();
      this.timer = setInterval(() => void this.tick(), this.intervalSec * 1000);
    }, 7_000);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.logger.log('Agent Poller 종료');
  }

  private async tick(): Promise<void> {
    if (this.disabled) return;

    if (this.running) {
      this.logger.warn('이전 tick 진행 중 — 이번 tick 건너뜁니다');

      return;
    }

    this.running = true;
    try {
      const snapshot = await this.collect();
      this.bus.emit(AGENT_SNAPSHOT_EVENT, snapshot);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Agent 상태 수집 실패: ${msg}`);
      this.bus.emit(AGENT_SNAPSHOT_EVENT, {
        at: new Date(),
        ok: false,
        reason: msg,
        agents: [],
      });
    } finally {
      this.running = false;
    }
  }

  private async collect(): Promise<AgentSnapshot> {
    // branch_agents 테이블 존재 확인 + agent 목록 조회를 한 번의 쿼리로
    // pg_tables 조회는 pg_catalog read-only 라 watcher 권한으로 가능
    const sql = `
      WITH exist_check AS (
        SELECT EXISTS (
          SELECT 1 FROM information_schema.tables
           WHERE table_schema='public' AND table_name='branch_agents'
        ) AS tbl_exists
      )
      SELECT
        (SELECT tbl_exists FROM exist_check) AS tbl_exists,
        COALESCE(
          (SELECT json_agg(row_to_json(a)) FROM (
             SELECT id, branch_id, agent_type, label, is_online,
                    last_seen_at,
                    CASE WHEN last_seen_at IS NULL THEN NULL
                         ELSE EXTRACT(EPOCH FROM (NOW() - last_seen_at))::int
                    END AS seconds_since_seen
               FROM public.branch_agents
              ORDER BY id
           ) a),
          '[]'::json
        ) AS agents
    `;

    const res = await this.pg.query<{ tbl_exists: boolean; agents: BranchAgentRow[] | null }>(sql);
    const row = res.rows[0];

    if (!row?.tbl_exists) {
      if (!this.disabled) {
        this.logger.warn('branch_agents 테이블이 존재하지 않습니다 — Agent Poller 자동 비활성화');
        this.disabled = true;
      }

      return { at: new Date(), ok: false, reason: 'table_not_found', agents: [] };
    }

    return { at: new Date(), ok: true, agents: row.agents ?? [] };
  }
}
