// Docker Rules — RULE-04: 컨테이너 health / state 이상 감지
// ----------------------------------------------------------------------------
// 감지 조건:
//   - state != 'running' (exited, dead, restarting 등)
//   - health = 'unhealthy'
//   - restartCount 가 직전보다 증가 (루프성 재시작)
// 모니터링 대상 컨테이너 화이트리스트: 환경변수 DOCKER_MONITOR_PREFIXES
//   (예: "api_ventago,ventago_app,dbpostgres,ventago_minio" / 기본: 전체)
// dedup_key: "RULE-04:<container_name>:<state|health>" — 같은 컨테이너 같은 상태 억제
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';
import { DOCKER_SNAPSHOT_EVENT, type DockerSnapshot } from '../observers/docker-poller.service';

import { RuleEngineService } from './rule-engine.service';

@Injectable()
export class DockerRulesService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DockerRulesService.name);
  private dedupMinutes = 15;
  private prefixes: string[] = [];
  private lastRestartCount = new Map<string, number>();
  private readonly onSnapshot = (s: DockerSnapshot): void => this.evaluate(s);

  constructor(
    private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
    private readonly engine: RuleEngineService,
  ) {}

  onModuleInit(): void {
    this.dedupMinutes = this.config.get('DEDUP_WINDOW_MINUTES', { infer: true });
    const raw = this.config.get('DOCKER_MONITOR_PREFIXES', { infer: true }) ?? '';
    this.prefixes = raw
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    this.bus.on(DOCKER_SNAPSHOT_EVENT, this.onSnapshot);
    this.logger.log(
      `Docker Rules 활성 (prefixes=${this.prefixes.length ? this.prefixes.join(',') : '전체'}, dedup=${this.dedupMinutes}m)`,
    );
  }

  onModuleDestroy(): void {
    this.bus.off(DOCKER_SNAPSHOT_EVENT, this.onSnapshot);
    this.lastRestartCount.clear();
    this.logger.log('Docker Rules 종료');
  }

  private evaluate(snap: DockerSnapshot): void {
    // Docker 소켓 연결 실패 자체는 WARN 로 15분에 1회 — CRIT 남용 방지
    if (!snap.ok) {
      this.engine.fire({
        ruleId: 'RULE-04',
        severity: 'warn',
        title: 'Docker 소켓 접근 실패',
        detail: snap.reason ?? 'unknown',
        dedupKey: 'RULE-04:docker-socket-down',
        dedupMinutes: this.dedupMinutes,
        context: { reason: snap.reason ?? null },
      });

      return;
    }

    for (const c of snap.containers) {
      if (!this.isMonitored(c.name)) continue;

      // [a] state != running
      if (c.state !== 'running') {
        this.engine.fire({
          ruleId: 'RULE-04',
          severity: c.state === 'exited' || c.state === 'dead' ? 'critical' : 'warn',
          title: `Container ${c.name} state=${c.state}`,
          detail: `image=${c.image} status="${c.status}" exit=${c.exitCode ?? '-'} restarts=${c.restartCount}`,
          dedupKey: `RULE-04:${c.name}:state=${c.state}`,
          dedupMinutes: this.dedupMinutes,
          context: { ...c },
        });
      }

      // [b] health=unhealthy
      if (c.health === 'unhealthy') {
        this.engine.fire({
          ruleId: 'RULE-04',
          severity: 'critical',
          title: `Container ${c.name} UNHEALTHY`,
          detail: `image=${c.image} status="${c.status}" restarts=${c.restartCount}`,
          dedupKey: `RULE-04:${c.name}:unhealthy`,
          dedupMinutes: this.dedupMinutes,
          context: { ...c },
        });
      }

      // [c] restart loop — 직전 대비 증가 감지
      const prev = this.lastRestartCount.get(c.name);
      if (prev !== undefined && c.restartCount > prev) {
        this.engine.fire({
          ruleId: 'RULE-04',
          severity: 'warn',
          title: `Container ${c.name} 재시작 감지 (${prev} → ${c.restartCount})`,
          detail: `image=${c.image} state=${c.state} status="${c.status}"`,
          dedupKey: `RULE-04:${c.name}:restart-inc`,
          dedupMinutes: this.dedupMinutes,
          context: { ...c, prevRestart: prev },
        });
      }
      this.lastRestartCount.set(c.name, c.restartCount);
    }
  }

  private isMonitored(name: string): boolean {
    if (this.prefixes.length === 0) return true;

    return this.prefixes.some((p) => name.startsWith(p));
  }
}
