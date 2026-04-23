// Agent Rules — RULE-07: BranchAgent offline 감지 + 복귀 알림
// ----------------------------------------------------------------------------
// 판정:
//   offline = is_online = false OR seconds_since_seen > THRESHOLD * 60
// dedup_key:
//   "RULE-07:agent=<id>:offline" (offline 지속 시 15분 dedup)
//   "RULE-07:agent=<id>:recovered" (복귀 시 15분 dedup)
// 복귀 감지:
//   prev(offline) → curr(online) 전이를 메모리 맵으로 추적
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';
import {
  AGENT_SNAPSHOT_EVENT,
  type AgentSnapshot,
  type BranchAgentRow,
} from '../observers/agent-poller.service';

import { RuleEngineService } from './rule-engine.service';

@Injectable()
export class AgentRulesService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AgentRulesService.name);
  private offlineThresholdSec = 300; // 5분
  private dedupMinutes = 15;
  private enabled = true;
  private readonly lastState = new Map<number, 'online' | 'offline'>();
  private readonly onSnapshot = (s: AgentSnapshot): void => this.evaluate(s);

  constructor(
    private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
    private readonly engine: RuleEngineService,
  ) {}

  onModuleInit(): void {
    this.enabled = this.config.get('RULE_07_ENABLED', { infer: true });

    // RULE-07 영구 비활성화 플래그 체크 — false 면 bus 구독 자체를 안 함
    if (!this.enabled) {
      this.logger.warn('Agent Rules 비활성 (RULE_07_ENABLED=false) — 프린터 에이전트 알림 생략');

      return;
    }

    const offlineMin = this.config.get('THRESHOLD_AGENT_OFFLINE_MINUTES', { infer: true });
    this.offlineThresholdSec = offlineMin * 60;
    this.dedupMinutes = this.config.get('DEDUP_WINDOW_MINUTES', { infer: true });
    this.bus.on(AGENT_SNAPSHOT_EVENT, this.onSnapshot);
    this.logger.log(`Agent Rules 활성 (offline ≥ ${offlineMin}m, dedup=${this.dedupMinutes}m)`);
  }

  onModuleDestroy(): void {
    // enabled=false 였으면 bus 구독도 안 했으므로 off 호출 불필요하지만 안전하게 호출 (no-op)
    this.bus.off(AGENT_SNAPSHOT_EVENT, this.onSnapshot);
    this.lastState.clear();
    this.logger.log('Agent Rules 종료');
  }

  private evaluate(snap: AgentSnapshot): void {
    if (!snap.ok) return; // table_not_found / error → 조용히 skip (AgentPoller 가 로그 남김)

    for (const a of snap.agents) {
      const isOffline = this.isOffline(a);
      const prev = this.lastState.get(a.id);
      const curr: 'online' | 'offline' = isOffline ? 'offline' : 'online';

      // 전이 감지: offline → online = 복귀 알림 (info)
      if (prev === 'offline' && curr === 'online') {
        this.engine.fire({
          ruleId: 'RULE-07',
          severity: 'info',
          title: `Agent 복귀: ${a.label} (branch=${a.branch_id})`,
          detail: `agent_id=${a.id} type=${a.agent_type} last_seen_at=${a.last_seen_at ?? '-'}`,
          dedupKey: `RULE-07:agent=${a.id}:recovered`,
          dedupMinutes: this.dedupMinutes,
          context: { ...a },
        });
      }

      // 현재 offline 이면 알림 (prev 여부 무관 — 재시작 직후에도 발화)
      if (curr === 'offline') {
        const secSince = a.seconds_since_seen;
        const sinceStr =
          secSince == null
            ? 'last_seen_at NULL'
            : `마지막 heartbeat ${Math.floor(secSince / 60)}분 ${secSince % 60}초 전`;

        this.engine.fire({
          ruleId: 'RULE-07',
          severity: 'warn',
          title: `Agent offline: ${a.label} (branch=${a.branch_id})`,
          detail: `agent_id=${a.id} type=${a.agent_type} is_online=${a.is_online} ${sinceStr}`,
          dedupKey: `RULE-07:agent=${a.id}:offline`,
          dedupMinutes: this.dedupMinutes,
          context: { ...a },
        });
      }

      this.lastState.set(a.id, curr);
    }
  }

  private isOffline(a: BranchAgentRow): boolean {
    if (!a.is_online) return true;
    if (a.seconds_since_seen == null) return true; // 한 번도 hb 없으면 offline 간주

    return a.seconds_since_seen > this.offlineThresholdSec;
  }
}
