// 로그 라인에서 위험 패턴을 매칭하는 규칙 모음
// ----------------------------------------------------------------------------
// RULE-05: 스키마 드리프트 (column / relation does not exist)
//   - 실제 운영에서 가장 자주 발생: column "use_variants", "Envio.priority",
//     "p.cost_price", "pin_hash", relation "product_branches" 등
//   - 첫 발생 즉시 critical 알림 + 15분 dedup (같은 컬럼 반복 알림 방지)
//
// RULE-06: 5xx 폭주 (1분 60건 이상 또는 단일 엔드포인트 30건 이상)
//   - 로그의 "GET/POST/... 5XX" 패턴을 슬라이딩 윈도우(60s) 로 카운트
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { Env } from '../config/env.schema';
import { SqliteService } from '../db/sqlite.service';
import { TelegramService } from '../notifiers/telegram.service';
import { LogLineEvent, LogTailService } from '../observers/log-tail.service';

interface FiveXXEntry {
  ts: number;
  endpoint: string;
  status: number;
}

@Injectable()
export class LogRulesService implements OnModuleInit {
  private readonly logger = new Logger(LogRulesService.name);

  // 슬라이딩 윈도우 — 메모리 캐시, 60초 보관
  private fiveXXWindow: FiveXXEntry[] = [];

  // 정규식 — Sequelize 가 던지는 메시지 형식
  private readonly RE_COLUMN = /column\s+["']?([^"'\s]+)["']?\s+does not exist/i;
  private readonly RE_RELATION = /relation\s+["']?([^"'\s]+)["']?\s+does not exist/i;

  // ExceptionFilter 형식: "GET /api/xxx 500 - user:N ip:..."
  private readonly RE_5XX = /\b(GET|POST|PUT|DELETE|PATCH)\s+(\/[^\s]+)\s+(5\d{2})\b/;

  constructor(
    private readonly tail: LogTailService,
    private readonly telegram: TelegramService,
    private readonly sqlite: SqliteService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  onModuleInit(): void {
    this.tail.on('line', (event: LogLineEvent) => {
      // void 처리 — emit handler 는 동기여야 함
      void this.handleLine(event);
    });
    this.logger.log('LogRulesService 가동 — RULE-05, RULE-06 활성');
  }

  private async handleLine(event: LogLineEvent): Promise<void> {
    try {
      await this.checkRule05(event);
      this.checkRule06(event);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`rule 처리 오류: ${msg}`);
    }
  }

  // ---------- RULE-05: 스키마 드리프트 ----------
  private async checkRule05(event: LogLineEvent): Promise<void> {
    const colMatch = this.RE_COLUMN.exec(event.line);
    const relMatch = this.RE_RELATION.exec(event.line);

    if (!colMatch && !relMatch) return;

    const kind = colMatch ? 'column' : 'relation';
    const name = (colMatch?.[1] ?? relMatch?.[1] ?? '').trim();
    const dedupKey = `RULE-05:${kind}:${name}`;
    const window = this.config.get('DEDUP_WINDOW_MINUTES', { infer: true });

    const ruleId = 'RULE-05';
    const fire = this.sqlite.shouldFire(dedupKey, ruleId, window);

    // 항상 이벤트는 저장 (분석 위해), 알림만 dedup
    const row = this.sqlite.insertEvent({
      rule_id: ruleId,
      severity: 'critical',
      title: `스키마 드리프트 — ${kind} "${name}" 없음`,
      detail:
        `로그에서 PostgreSQL 스키마 불일치 감지.\n` +
        `종류: ${kind}\n이름: ${name}\n원본: ${event.line.slice(0, 300)}`,
      context_json: JSON.stringify({
        file: event.filePath,
        kind,
        name,
        sample: event.line.slice(0, 500),
      }),
    });

    if (!fire) {
      return; // dedup window 내 — 알림 스킵
    }

    const ok = await this.telegram.sendAlert({
      ruleId,
      severity: 'critical',
      title: `스키마 드리프트 — ${kind} ${name} 없음`,
      detail:
        `운영 PG 와 코드(Sequelize 모델) 가 어긋났습니다. ` +
        `최근 마이그레이션 누락 또는 배포 후 모델 갱신 미반영 의심.`,
      context: {
        kind,
        name,
        file: event.filePath.split('/').slice(-2).join('/'),
        action: '미적용 마이그레이션 확인 → api-ventago/migrations/ 검토',
      },
    });

    if (ok) {
      this.sqlite.markEventNotified(row.id);
    }
  }

  // ---------- RULE-06: 5xx 폭주 ----------
  private checkRule06(event: LogLineEvent): void {
    const m = this.RE_5XX.exec(event.line);
    if (!m) return;

    const endpoint = m[2];
    const status = parseInt(m[3], 10);
    const now = event.ts;

    // 윈도우 추가 + 60초 이전 항목 제거
    this.fiveXXWindow.push({ ts: now, endpoint, status });
    const cutoff = now - 60_000;
    this.fiveXXWindow = this.fiveXXWindow.filter((e) => e.ts >= cutoff);

    const total = this.fiveXXWindow.length;

    // 동일 엔드포인트 카운트
    const perEndpoint = new Map<string, number>();
    for (const e of this.fiveXXWindow) {
      perEndpoint.set(e.endpoint, (perEndpoint.get(e.endpoint) ?? 0) + 1);
    }

    let topEndpoint = '';
    let topCount = 0;
    for (const [ep, cnt] of perEndpoint) {
      if (cnt > topCount) {
        topEndpoint = ep;
        topCount = cnt;
      }
    }

    const triggerTotal = total >= 60;
    const triggerEndpoint = topCount >= 30;
    if (!triggerTotal && !triggerEndpoint) return;

    // dedup: 60초 단위로만 1회 발화
    const dedupKey = `RULE-06:${triggerEndpoint ? topEndpoint : 'TOTAL'}`;
    const fire = this.sqlite.shouldFire(dedupKey, 'RULE-06', 1);
    if (!fire) return;

    const row = this.sqlite.insertEvent({
      rule_id: 'RULE-06',
      severity: 'critical',
      title: `5xx 폭주 (${total}건/분)`,
      detail: `최근 60초 5xx 총 ${total}건. 최다 엔드포인트: ${topEndpoint} (${topCount}건)`,
      context_json: JSON.stringify({ total, topEndpoint, topCount }),
    });

    void this.telegram
      .sendAlert({
        ruleId: 'RULE-06',
        severity: 'critical',
        title: `5xx 폭주`,
        detail: `최근 60초 5xx 총 ${total}건 발생. 즉시 점검이 필요합니다.`,
        context: {
          total_60s: total,
          top_endpoint: topEndpoint,
          top_count: topCount,
          last_status: status,
        },
      })
      .then((ok) => {
        if (ok) this.sqlite.markEventNotified(row.id);
      });
  }
}
