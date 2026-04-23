// Heartbeat Service — RULE-08: vw-agent 자체 생존 신호 (일일 리포트)
// ----------------------------------------------------------------------------
// 2026-04-23 개편:
//   이전: 30분마다 setInterval 로 무조건 송신 (하루 48건 noise)
//   지금: 매일 한국시간(KST) 09:00 정각 1회, 지난 24시간 이벤트 요약 포함
//
// 설계:
//   - NestJS @Cron 데코레이터 사용 (@nestjs/schedule 이미 등록됨)
//   - cron 표현: "0 0 9 * * *" = 매일 09:00:00 (6필드 포맷, second 포함)
//   - timeZone: 'Asia/Seoul' 로 한국 기준 고정 (서버 UTC 와 무관하게 동작)
//   - 기동 시 "🟢 vw-agent 기동 완료" 는 main.ts 가 담당 → 여기서는 별도 첫 송신 없음
// 안전 규칙:
//   - 이 서비스는 PG 쿼리를 보내지 않음 — SQLite 만 읽음 (pool 영향 0)
//   - 송신 실패 시 heartbeats 테이블에 ok=0 기록 (실패 내역 관측)
//   - running 플래그로 중첩 실행 방지 (cron 이 느린 네트워크와 겹쳐도 안전)
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';

import { PgReadonlyService } from '../db/pg-readonly.service';
import { SqliteService } from '../db/sqlite.service';
import type { DailyReportData } from '../notifiers/message.templates';
import { TelegramService } from '../notifiers/telegram.service';

const DAILY_CRON = '0 0 9 * * *'; // 매일 09:00:00
const DAILY_TZ = 'Asia/Seoul';

@Injectable()
export class HeartbeatService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(HeartbeatService.name);
  private readonly startTs = Date.now();
  private running = false;

  constructor(
    private readonly pg: PgReadonlyService,
    private readonly sqlite: SqliteService,
    private readonly telegram: TelegramService,
  ) {}

  onModuleInit(): void {
    this.logger.log(`Heartbeat 시작 (daily cron="${DAILY_CRON}" tz=${DAILY_TZ})`);
  }

  onModuleDestroy(): void {
    // @Cron 은 ScheduleModule 생명주기로 자동 정리됨 — 별도 clear 불필요
    this.logger.log('Heartbeat 종료');
  }

  /** 매일 한국시간 09:00 정각 — 일일 리포트 송신 */
  @Cron(DAILY_CRON, { name: 'daily-heartbeat', timeZone: DAILY_TZ })
  async fireDaily(): Promise<void> {
    if (this.running) {
      this.logger.warn('이전 daily heartbeat 진행 중 — 이번 tick 스킵');

      return;
    }
    this.running = true;

    try {
      const data = this.collectDailyReport();
      const ok = await this.telegram.sendDailyReport(data);
      this.sqlite.recordHeartbeat(ok, ok ? undefined : 'telegram_send_failed');
      this.logger.log(
        `일일 리포트 송신 ${ok ? '성공' : '실패'} (critical=${data.severityCounts.critical}, warn=${data.severityCounts.warn})`,
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Heartbeat 실패: ${msg}`);
      this.sqlite.recordHeartbeat(false, msg);
    } finally {
      this.running = false;
    }
  }

  /** 지난 24시간 이벤트 집계 + 현재 상태 스냅샷 → DailyReportData */
  private collectDailyReport(): DailyReportData {
    // SQLite 에서 최근 500건 조회 후 24h 필터 (recent_events 는 DESC 정렬)
    // 24시간 동안 500건을 넘는 폭주 상황은 따로 critical 알림이 이미 갔을 것
    const recent = this.sqlite.recentEvents(500);
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const last24h = recent.filter((e) => Date.parse(`${e.created_at}Z`) > dayAgo);

    // severity 별 집계
    const severityCounts = { critical: 0, warn: 0, info: 0 };
    for (const e of last24h) {
      if (e.severity === 'critical') severityCounts.critical += 1;
      else if (e.severity === 'warn') severityCounts.warn += 1;
      else if (e.severity === 'info') severityCounts.info += 1;
    }

    // 규칙별 집계 (count 내림차순)
    const ruleMap = new Map<string, { count: number; sevSet: Set<string> }>();
    for (const e of last24h) {
      const entry = ruleMap.get(e.rule_id) ?? { count: 0, sevSet: new Set<string>() };
      entry.count += 1;
      entry.sevSet.add(e.severity);
      ruleMap.set(e.rule_id, entry);
    }
    const byRule = [...ruleMap.entries()]
      .map(([ruleId, v]) => ({
        ruleId,
        count: v.count,
        severities: [...v.sevSet].sort(),
      }))
      .sort((a, b) => b.count - a.count);

    // PG pool 은 메모리 카운터 — 쿼리 없음
    const pgStats = this.pg.getStats();

    return {
      nowKst: this.formatKstNow(),
      uptime: this.formatUptime(),
      severityCounts,
      byRule,
      pgPool: {
        total: pgStats.totalCount,
        idle: pgStats.idleCount,
        waiting: pgStats.waitingCount,
        max: 3,
      },
      memoryRssMb: Math.round(process.memoryUsage().rss / 1024 / 1024),
    };
  }

  /** 현재 시각을 KST 로 포맷 (서버 타임존과 무관) */
  private formatKstNow(): string {
    // Intl.DateTimeFormat 로 Asia/Seoul 기준 포맷
    const now = new Date();
    const fmt = new Intl.DateTimeFormat('sv-SE', {
      timeZone: DAILY_TZ,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });

    // sv-SE 는 "YYYY-MM-DD HH:mm:ss" 포맷 (ISO 비슷)
    return fmt.format(now);
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
