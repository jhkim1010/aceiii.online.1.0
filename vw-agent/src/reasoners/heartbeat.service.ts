// Heartbeat Service — RULE-08: vw-agent 자체 생존 신호
// ----------------------------------------------------------------------------
// 목적:
//   - 운영자에게 "vw-agent 가 살아있다" 를 주기적으로 증명
//   - 알림은 silent (disable_notification=true) 로 조용히 송신
//   - 실패 시 SQLite heartbeats 테이블에 ok=0 기록
// 주기: HEARTBEAT_INTERVAL_MIN (기본 30분)
// 첫 송신: 기동 2분 뒤 (부팅 시점 알림 겸)
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { Env } from '../config/env.schema';
import { PgReadonlyService } from '../db/pg-readonly.service';
import { SqliteService } from '../db/sqlite.service';
import { TelegramService } from '../notifiers/telegram.service';

@Injectable()
export class HeartbeatService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(HeartbeatService.name);
  private readonly startTs = Date.now();
  private timer: NodeJS.Timeout | null = null;
  private intervalMs = 30 * 60 * 1000;
  private running = false;

  constructor(
    private readonly config: ConfigService<Env, true>,
    private readonly pg: PgReadonlyService,
    private readonly sqlite: SqliteService,
    private readonly telegram: TelegramService,
  ) {}

  onModuleInit(): void {
    const min = this.config.get('HEARTBEAT_INTERVAL_MIN', { infer: true });
    this.intervalMs = min * 60 * 1000;
    this.logger.log(`Heartbeat 시작 (주기=${min}분)`);

    // 기동 후 2분 뒤 첫 heartbeat (서비스 안정화 대기)
    this.timer = setTimeout(() => {
      void this.fire();
      this.timer = setInterval(() => void this.fire(), this.intervalMs);
    }, 2 * 60 * 1000);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.logger.log('Heartbeat 종료');
  }

  private async fire(): Promise<void> {
    if (this.running) return;
    this.running = true;

    try {
      const stats = this.collectStats();
      const uptime = this.formatUptime();

      const ok = await this.telegram.sendHeartbeat(uptime, stats);
      this.sqlite.recordHeartbeat(ok, ok ? undefined : 'telegram_send_failed');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Heartbeat 실패: ${msg}`);
      this.sqlite.recordHeartbeat(false, msg);
    } finally {
      this.running = false;
    }
  }

  private collectStats(): Record<string, unknown> {
    const pgPool = this.pg.getStats();
    const recent = this.sqlite.recentEvents(100);

    // 최근 1시간 이벤트만 집계
    const oneHourAgo = Date.now() - 60 * 60 * 1000;
    const lastHour = recent.filter((e) => Date.parse(`${e.created_at}Z`) > oneHourAgo);

    const bySeverity: Record<string, number> = { info: 0, warn: 0, critical: 0 };
    for (const e of lastHour) bySeverity[e.severity] = (bySeverity[e.severity] ?? 0) + 1;

    return {
      pg_pool_total: pgPool.totalCount,
      pg_pool_idle: pgPool.idleCount,
      pg_pool_waiting: pgPool.waitingCount,
      events_last_hour: lastHour.length,
      events_critical_1h: bySeverity.critical,
      events_warn_1h: bySeverity.warn,
      memory_rss_mb: Math.round(process.memoryUsage().rss / 1024 / 1024),
    };
  }

  private formatUptime(): string {
    const sec = Math.floor((Date.now() - this.startTs) / 1000);
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;

    if (d > 0) return `${d}d ${h}h ${m}m`;
    if (h > 0) return `${h}h ${m}m ${s}s`;

    return `${m}m ${s}s`;
  }
}
