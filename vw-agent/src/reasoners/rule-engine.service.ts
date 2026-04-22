// RuleEngineService — 규칙 발화 공통 파이프라인
// ----------------------------------------------------------------------------
// 목적:
//   개별 Rule service (pg/docker/agent/log/heartbeat) 가 중복 구현하던
//   "dedup 체크 → SQLite insert → Telegram 비동기 송신 → notified_at 갱신"
//   흐름을 한 곳에 모아서 일관성 + 테스트 용이성 확보.
//
// 안전 규칙:
//   - Telegram 송신 실패해도 이벤트는 SQLite 에 남는다 (감사 추적 보존)
//   - dedup 은 SQLite `dedup_keys` 테이블에서 수행 (프로세스 재시작 후에도 유지)
//   - Rule 쪽에서 예외가 나도 engine 전체가 죽지 않도록 개별 try/catch
// ----------------------------------------------------------------------------
import { Injectable, Logger } from '@nestjs/common';

import { SqliteService } from '../db/sqlite.service';
import { TelegramService } from '../notifiers/telegram.service';

export type Severity = 'info' | 'warn' | 'critical';

export interface FireInput {
  ruleId: string;
  severity: Severity;
  title: string;
  detail: string;
  dedupKey: string;
  dedupMinutes: number;

  /** Telegram 메시지에 포함될 구조화 컨텍스트 (선택) */
  context?: Record<string, unknown>;

  /** true 이면 dedup 윈도우 안이어도 SQLite 에는 insert (알림만 억제) — RULE-05 같은 감사 이벤트 */
  recordOnDedup?: boolean;

  /** true 이면 무음 송신 (heartbeat 용 — 현재는 engine 에서 쓰지 않지만 옵션만 노출) */
  silent?: boolean;
}

export interface FireResult {
  fired: boolean;
  eventId: number | null;
  reason: 'fired' | 'deduped' | 'deduped_recorded' | 'skipped';
}

@Injectable()
export class RuleEngineService {
  private readonly logger = new Logger(RuleEngineService.name);

  constructor(
    private readonly sqlite: SqliteService,
    private readonly telegram: TelegramService,
  ) {}

  /**
   * 규칙 발화 — dedup 체크 후 이벤트 저장 + Telegram 비동기 송신.
   * 반환값으로 발화 여부/이유를 받아 호출측에서 로깅 가능.
   */
  fire(input: FireInput): FireResult {
    try {
      const canFire = this.sqlite.shouldFire(input.dedupKey, input.ruleId, input.dedupMinutes);

      if (!canFire) {
        // dedup window 내 — 선택적으로 감사용 이벤트만 기록
        if (input.recordOnDedup) {
          const row = this.sqlite.insertEvent({
            rule_id: input.ruleId,
            severity: input.severity,
            title: input.title,
            detail: input.detail,
            context_json: input.context ? JSON.stringify(input.context) : null,
          });

          return { fired: false, eventId: row.id, reason: 'deduped_recorded' };
        }

        return { fired: false, eventId: null, reason: 'deduped' };
      }

      // 발화 — 이벤트 먼저 저장 (Telegram 실패해도 남김)
      const row = this.sqlite.insertEvent({
        rule_id: input.ruleId,
        severity: input.severity,
        title: input.title,
        detail: input.detail,
        context_json: input.context ? JSON.stringify(input.context) : null,
      });

      // 비동기 송신 — await 하지 않음 (규칙 평가 차단 금지)
      void this.telegram
        .sendAlert(
          {
            ruleId: input.ruleId,
            severity: input.severity,
            title: input.title,
            detail: input.detail,
            context: input.context,
          },
          { silent: input.silent ?? false },
        )
        .then((ok) => {
          if (ok) this.sqlite.markEventNotified(row.id);
        })
        .catch((err) => {
          const msg = err instanceof Error ? err.message : String(err);
          this.logger.warn(`[${input.ruleId}] Telegram 송신 실패: ${msg}`);
        });

      return { fired: true, eventId: row.id, reason: 'fired' };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`[${input.ruleId}] fire 실패: ${msg}`);

      return { fired: false, eventId: null, reason: 'skipped' };
    }
  }
}
