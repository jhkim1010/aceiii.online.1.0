// RuleEngineService 단위 테스트
// ----------------------------------------------------------------------------
// 검증 목표:
//   - 첫 발화: 이벤트 insert + Telegram 송신 시도 + fired:true
//   - dedup 윈도우 내 재발화: 이벤트 insert 없음, Telegram 미호출, reason='deduped'
//   - recordOnDedup=true: dedup 이어도 이벤트는 저장, Telegram 은 미호출
//   - Telegram 실패: notified_at 미갱신 (이벤트는 저장됨)
//   - Telegram 성공: notified_at 갱신
// 의존성은 테스트 double 로 대체해 SQLite/Telegram 실제 I/O 없음.
// ----------------------------------------------------------------------------
import type { EventInsert, EventRow, SqliteService } from '../db/sqlite.service';
import type { TelegramService } from '../notifiers/telegram.service';

import { RuleEngineService } from './rule-engine.service';

// ---------- 테스트용 Stub ----------

class StubSqlite {
  private nextId = 1;
  private dedup = new Map<string, number>(); // key → lastFiredMs
  public events: EventRow[] = [];
  public notified: number[] = [];

  shouldFire(key: string, _ruleId: string, windowMin: number): boolean {
    const now = Date.now();
    const last = this.dedup.get(key);
    if (last !== undefined && now - last < windowMin * 60_000) return false;
    this.dedup.set(key, now);

    return true;
  }

  insertEvent(e: EventInsert): EventRow {
    const row: EventRow = {
      id: this.nextId++,
      rule_id: e.rule_id,
      severity: e.severity,
      title: e.title,
      detail: e.detail,
      context_json: e.context_json,
      created_at: new Date().toISOString(),
      notified_at: null,
    };
    this.events.push(row);

    return row;
  }

  markEventNotified(id: number): void {
    this.notified.push(id);
  }
}

class StubTelegram {
  public sendCount = 0;
  public shouldSucceed = true;

  sendAlert(): Promise<boolean> {
    this.sendCount += 1;

    return Promise.resolve(this.shouldSucceed);
  }
}

// ---------- 테스트 ----------

describe('RuleEngineService', () => {
  let sqlite: StubSqlite;
  let telegram: StubTelegram;
  let engine: RuleEngineService;

  beforeEach(() => {
    sqlite = new StubSqlite();
    telegram = new StubTelegram();
    engine = new RuleEngineService(
      sqlite as unknown as SqliteService,
      telegram as unknown as TelegramService,
    );
  });

  it('첫 발화는 이벤트 insert + Telegram 송신 + fired=true', async () => {
    const result = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:1',
      dedupMinutes: 15,
    });

    expect(result.fired).toBe(true);
    expect(result.reason).toBe('fired');
    expect(result.eventId).toBe(1);
    expect(sqlite.events.length).toBe(1);

    // Telegram 송신은 비동기 Promise — microtask flush
    await Promise.resolve();
    await Promise.resolve();
    expect(telegram.sendCount).toBe(1);
    expect(sqlite.notified).toContain(1);
  });

  it('dedup 윈도우 내 재발화: 이벤트 저장 없음, Telegram 미호출', () => {
    engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:2',
      dedupMinutes: 15,
    });

    const second = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:2',
      dedupMinutes: 15,
    });

    expect(second.fired).toBe(false);
    expect(second.reason).toBe('deduped');
    expect(second.eventId).toBeNull();
    expect(sqlite.events.length).toBe(1); // 첫 발화 1건만
  });

  it('recordOnDedup=true 이면 dedup 중에도 이벤트는 저장되나 Telegram 미호출', async () => {
    // 첫 발화 — fired
    engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'critical',
      title: 't',
      detail: 'd',
      dedupKey: 'key:3',
      dedupMinutes: 15,
      recordOnDedup: true,
    });
    await Promise.resolve();

    const telegramBefore = telegram.sendCount;

    const second = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'critical',
      title: 't',
      detail: 'd',
      dedupKey: 'key:3',
      dedupMinutes: 15,
      recordOnDedup: true,
    });

    expect(second.fired).toBe(false);
    expect(second.reason).toBe('deduped_recorded');
    expect(second.eventId).toBe(2); // 이벤트는 저장됨
    expect(sqlite.events.length).toBe(2);
    expect(telegram.sendCount).toBe(telegramBefore); // 추가 송신 없음
  });

  it('Telegram 송신 실패 시 notified_at 미갱신', async () => {
    telegram.shouldSucceed = false;

    const result = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:4',
      dedupMinutes: 15,
    });

    // Promise flush
    await Promise.resolve();
    await Promise.resolve();

    expect(result.fired).toBe(true);
    expect(sqlite.events.length).toBe(1);
    expect(telegram.sendCount).toBe(1);
    expect(sqlite.notified).not.toContain(result.eventId);
  });

  it('서로 다른 dedupKey 는 독립 발화', () => {
    const a = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:A',
      dedupMinutes: 15,
    });
    const b = engine.fire({
      ruleId: 'RULE-TEST',
      severity: 'warn',
      title: 't',
      detail: 'd',
      dedupKey: 'key:B',
      dedupMinutes: 15,
    });

    expect(a.fired).toBe(true);
    expect(b.fired).toBe(true);
    expect(sqlite.events.length).toBe(2);
  });
});
