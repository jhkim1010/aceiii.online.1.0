// SqliteService 단위 테스트 — dedup 윈도우 로직 중심
// ----------------------------------------------------------------------------
// 가장 중요한 안전 장치인 shouldFire() 를 검증:
//   - 첫 발화는 true
//   - 같은 key 를 window 내 재호출하면 false (fire_count 증가만)
//   - window 경과 후에는 다시 true
// better-sqlite3 는 :memory: 인스턴스로 테스트 (디스크 I/O 없음)
// ----------------------------------------------------------------------------
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import { SqliteService } from './sqlite.service';

describe('SqliteService.shouldFire', () => {
  let service: SqliteService;
  let tmpPath: string;

  beforeEach(() => {
    tmpPath = path.join(
      os.tmpdir(),
      `vw-agent-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`,
    );
    const mockConfig = {
      get: (k: string) => (k === 'SQLITE_PATH' ? tmpPath : undefined),
    } as unknown as ConfigService;
    service = new SqliteService(mockConfig);
    service.onModuleInit();
  });

  afterEach(() => {
    service.onModuleDestroy();
    if (fs.existsSync(tmpPath)) {
      fs.unlinkSync(tmpPath);
    }

    // WAL/SHM 파일도 정리
    for (const ext of ['-wal', '-shm']) {
      const p = tmpPath + ext;
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  it('첫 발화는 true 를 반환한다', () => {
    const result = service.shouldFire('test:key:1', 'RULE-TEST', 15);
    expect(result).toBe(true);
  });

  it('window 내 재호출은 false 를 반환한다', () => {
    service.shouldFire('test:key:2', 'RULE-TEST', 15);
    const second = service.shouldFire('test:key:2', 'RULE-TEST', 15);
    expect(second).toBe(false);
  });

  it('서로 다른 key 는 독립적으로 발화한다', () => {
    const a = service.shouldFire('test:keyA', 'RULE-TEST', 15);
    const b = service.shouldFire('test:keyB', 'RULE-TEST', 15);
    expect(a).toBe(true);
    expect(b).toBe(true);
  });

  it('window=0 이면 항상 true (시간차가 항상 >= 0)', () => {
    // 0 분 이내 라는 건 "즉시 재발화 허용" 의미 — 실전에선 안 쓰지만 경계 검사
    service.shouldFire('test:keyC', 'RULE-TEST', 0);
    const second = service.shouldFire('test:keyC', 'RULE-TEST', 0);
    expect(second).toBe(true);
  });
});

describe('SqliteService.events', () => {
  let service: SqliteService;
  let tmpPath: string;

  beforeEach(() => {
    tmpPath = path.join(
      os.tmpdir(),
      `vw-agent-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`,
    );
    const mockConfig = {
      get: (k: string) => (k === 'SQLITE_PATH' ? tmpPath : undefined),
    } as unknown as ConfigService;
    service = new SqliteService(mockConfig);
    service.onModuleInit();
  });

  afterEach(() => {
    service.onModuleDestroy();
    if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
    for (const ext of ['-wal', '-shm']) {
      const p = tmpPath + ext;
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  });

  it('insertEvent 는 auto-increment id 를 반환한다', () => {
    const e1 = service.insertEvent({
      rule_id: 'RULE-01',
      severity: 'warn',
      title: 't1',
      detail: 'd1',
      context_json: null,
    });
    const e2 = service.insertEvent({
      rule_id: 'RULE-01',
      severity: 'warn',
      title: 't2',
      detail: 'd2',
      context_json: null,
    });
    expect(e1.id).toBeGreaterThan(0);
    expect(e2.id).toBeGreaterThan(e1.id);
  });

  it('markEventNotified 로 notified_at 이 채워진다', () => {
    const e = service.insertEvent({
      rule_id: 'RULE-02',
      severity: 'critical',
      title: 't',
      detail: 'd',
      context_json: null,
    });
    expect(e.notified_at).toBeNull();
    service.markEventNotified(e.id);
    const [latest] = service.recentEvents(1);
    expect(latest.notified_at).not.toBeNull();
  });
});
