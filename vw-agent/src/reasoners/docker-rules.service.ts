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
import { SqliteService } from '../db/sqlite.service';
import { TelegramService } from '../notifiers/telegram.service';
import {
  DOCKER_SNAPSHOT_EVENT,
  type ContainerSnapshot,
  type DockerSnapshot,
} from '../observers/docker-poller.service';

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
    private readonly sqlite: SqliteService,
    private readonly telegram: TelegramService,
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
    // Docker 소켓 연결 실패 자체는 INFO 로 1회만 — CRIT 남용 방지
    if (!snap.ok) {
      const dedupKey = 'RULE-04:docker-socket-down';
      if (this.sqlite.shouldFire(dedupKey, 'RULE-04', this.dedupMinutes)) {
        this.fire('RULE-04', 'warn', 'Docker 소켓 접근 실패', snap.reason ?? 'unknown', {
          reason: snap.reason,
        });
      }

      return;
    }

    for (const c of snap.containers) {
      if (!this.isMonitored(c.name)) continue;

      // [a] state != running
      if (c.state !== 'running') {
        const dedupKey = `RULE-04:${c.name}:state=${c.state}`;
        if (this.sqlite.shouldFire(dedupKey, 'RULE-04', this.dedupMinutes)) {
          this.fire(
            'RULE-04',
            c.state === 'exited' || c.state === 'dead' ? 'critical' : 'warn',
            `Container ${c.name} state=${c.state}`,
            `image=${c.image} status="${c.status}" exit=${c.exitCode ?? '-'} restarts=${c.restartCount}`,
            { ...c },
          );
        }
      }

      // [b] health=unhealthy
      if (c.health === 'unhealthy') {
        const dedupKey = `RULE-04:${c.name}:unhealthy`;
        if (this.sqlite.shouldFire(dedupKey, 'RULE-04', this.dedupMinutes)) {
          this.fire(
            'RULE-04',
            'critical',
            `Container ${c.name} UNHEALTHY`,
            `image=${c.image} status="${c.status}" restarts=${c.restartCount}`,
            { ...c },
          );
        }
      }

      // [c] restart loop — 직전 대비 증가 감지
      const prev = this.lastRestartCount.get(c.name);
      if (prev !== undefined && c.restartCount > prev) {
        const dedupKey = `RULE-04:${c.name}:restart-inc`;
        if (this.sqlite.shouldFire(dedupKey, 'RULE-04', this.dedupMinutes)) {
          this.fire(
            'RULE-04',
            'warn',
            `Container ${c.name} 재시작 감지 (${prev} → ${c.restartCount})`,
            `image=${c.image} state=${c.state} status="${c.status}"`,
            { ...c, prevRestart: prev },
          );
        }
      }
      this.lastRestartCount.set(c.name, c.restartCount);
    }
  }

  private isMonitored(name: string): boolean {
    if (this.prefixes.length === 0) return true;

    return this.prefixes.some((p) => name.startsWith(p));
  }

  private fire(
    ruleId: string,
    severity: 'info' | 'warn' | 'critical',
    title: string,
    detail: string,
    context: Record<string, unknown>,
  ): void {
    const event = this.sqlite.insertEvent({
      rule_id: ruleId,
      severity,
      title,
      detail,
      context_json: JSON.stringify(context),
    });

    void this.telegram
      .sendAlert({ ruleId, severity, title, detail })
      .then((ok) => {
        if (ok) this.sqlite.markEventNotified(event.id);
      })
      .catch((err) =>
        this.logger.warn(`Telegram 전송 실패: ${err instanceof Error ? err.message : err}`),
      );
  }
}
