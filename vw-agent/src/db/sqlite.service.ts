// vw-agent 내부 상태 저장소 (SQLite, better-sqlite3 동기 API)
// ----------------------------------------------------------------------------
// 저장 항목:
// - events            : 모든 감지 이벤트 (RULE-XX 별 발화 이력)
// - dedup_keys        : 중복 알림 억제용 (key + 마지막 발화 시각)
// - log_offsets       : 로그 파일별 마지막 read offset (재기동 시 이어서 tail)
// - heartbeats        : self-heartbeat 송신 이력
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Database from 'better-sqlite3';
import * as fs from 'fs';
import * as path from 'path';

import type { Env } from '../config/env.schema';

export interface EventRow {
  id: number;
  rule_id: string;
  severity: 'info' | 'warn' | 'critical';
  title: string;
  detail: string;
  context_json: string | null;
  created_at: string;
  notified_at: string | null;
}

export type EventInsert = Omit<EventRow, 'id' | 'created_at' | 'notified_at'>;

@Injectable()
export class SqliteService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SqliteService.name);
  private db: Database.Database | null = null;

  constructor(@Inject(ConfigService) private readonly config: ConfigService<Env, true>) {}

  onModuleInit(): void {
    const dbPath = this.config.get('SQLITE_PATH', { infer: true });
    const dir = path.dirname(dbPath);

    // 디렉토리 보장
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    this.db = new Database(dbPath);

    // WAL 모드 — 동시 read/write 안전성 + 성능
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('synchronous = NORMAL');
    this.db.pragma('foreign_keys = ON');

    this.runMigrations();
    this.logger.log(`SQLite 초기화 완료 (path=${dbPath}, mode=WAL)`);
  }

  onModuleDestroy(): void {
    if (this.db) {
      this.db.close();
      this.db = null;
      this.logger.log('SQLite 종료');
    }
  }

  // ---------- 스키마 ----------
  private runMigrations(): void {
    if (!this.db) return;

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS events (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id       TEXT    NOT NULL,
        severity      TEXT    NOT NULL CHECK (severity IN ('info','warn','critical')),
        title         TEXT    NOT NULL,
        detail        TEXT    NOT NULL,
        context_json  TEXT,
        created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
        notified_at   TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_events_created ON events(created_at);
      CREATE INDEX IF NOT EXISTS idx_events_rule    ON events(rule_id);

      CREATE TABLE IF NOT EXISTS dedup_keys (
        dedup_key   TEXT PRIMARY KEY,
        rule_id     TEXT NOT NULL,
        last_fired  TEXT NOT NULL,
        fire_count  INTEGER NOT NULL DEFAULT 1
      );

      CREATE TABLE IF NOT EXISTS log_offsets (
        file_path   TEXT PRIMARY KEY,
        last_offset INTEGER NOT NULL DEFAULT 0,
        last_inode  INTEGER,
        updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS heartbeats (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        sent_at     TEXT NOT NULL DEFAULT (datetime('now')),
        ok          INTEGER NOT NULL,
        message     TEXT
      );
    `);
  }

  // ---------- events ----------
  insertEvent(event: EventInsert): EventRow {
    if (!this.db) throw new Error('SQLite 미초기화');

    const stmt = this.db.prepare(`
      INSERT INTO events (rule_id, severity, title, detail, context_json)
      VALUES (@rule_id, @severity, @title, @detail, @context_json)
    `);
    const info = stmt.run(event);
    const row = this.db
      .prepare<{ id: number | bigint }, EventRow>('SELECT * FROM events WHERE id = @id')
      .get({ id: info.lastInsertRowid });

    if (!row) throw new Error('이벤트 조회 실패');

    return row;
  }

  markEventNotified(id: number): void {
    if (!this.db) return;
    this.db.prepare(`UPDATE events SET notified_at = datetime('now') WHERE id = ?`).run(id);
  }

  recentEvents(limit = 50): EventRow[] {
    if (!this.db) return [];

    return this.db
      .prepare<[number], EventRow>(`SELECT * FROM events ORDER BY id DESC LIMIT ?`)
      .all(limit);
  }

  // ---------- dedup ----------
  /**
   * 중복 알림 억제 — windowMinutes 내에 같은 dedup_key 가 발화했으면 false.
   * 발화 가능하면 true 반환 + 키 갱신.
   */
  shouldFire(dedupKey: string, ruleId: string, windowMinutes: number): boolean {
    if (!this.db) return true;

    const row = this.db
      .prepare<
        [string],
        { last_fired: string }
      >(`SELECT last_fired FROM dedup_keys WHERE dedup_key = ?`)
      .get(dedupKey);

    const now = Date.now();

    if (row) {
      const lastMs = Date.parse(`${row.last_fired}Z`);
      const diffMin = (now - lastMs) / 60_000;

      if (diffMin < windowMinutes) {
        // 카운트만 증가 — 알림은 보내지 않음
        this.db
          .prepare(`UPDATE dedup_keys SET fire_count = fire_count + 1 WHERE dedup_key = ?`)
          .run(dedupKey);

        return false;
      }
    }

    // upsert
    this.db
      .prepare(
        `INSERT INTO dedup_keys (dedup_key, rule_id, last_fired, fire_count)
         VALUES (?, ?, datetime('now'), 1)
         ON CONFLICT(dedup_key) DO UPDATE SET
           last_fired = datetime('now'),
           fire_count = fire_count + 1`,
      )
      .run(dedupKey, ruleId);

    return true;
  }

  // ---------- log offsets ----------
  getLogOffset(filePath: string): { offset: number; inode: number | null } {
    if (!this.db) return { offset: 0, inode: null };

    const row = this.db
      .prepare<
        [string],
        { last_offset: number; last_inode: number | null }
      >(`SELECT last_offset, last_inode FROM log_offsets WHERE file_path = ?`)
      .get(filePath);

    return row ? { offset: row.last_offset, inode: row.last_inode } : { offset: 0, inode: null };
  }

  saveLogOffset(filePath: string, offset: number, inode: number): void {
    if (!this.db) return;
    this.db
      .prepare(
        `INSERT INTO log_offsets (file_path, last_offset, last_inode, updated_at)
         VALUES (?, ?, ?, datetime('now'))
         ON CONFLICT(file_path) DO UPDATE SET
           last_offset = excluded.last_offset,
           last_inode  = excluded.last_inode,
           updated_at  = datetime('now')`,
      )
      .run(filePath, offset, inode);
  }

  // ---------- heartbeats ----------
  recordHeartbeat(ok: boolean, message?: string): void {
    if (!this.db) return;
    this.db
      .prepare(`INSERT INTO heartbeats (ok, message) VALUES (?, ?)`)
      .run(ok ? 1 : 0, message ?? null);
  }

  /**
   * 가장 최근 heartbeat 송신 시각 (ISO 문자열).
   * /health 엔드포인트에서 agent liveness 판정에 사용.
   */
  lastHeartbeat(): string | null {
    if (!this.db) return null;

    const row = this.db
      .prepare<[], { sent_at: string }>(`SELECT sent_at FROM heartbeats ORDER BY id DESC LIMIT 1`)
      .get();

    return row ? `${row.sent_at}Z` : null;
  }

  // ---------- dedup 통계 ----------
  /**
   * dedup_keys 테이블 통계 — /health 및 운영 진단용.
   * 발화 빈도가 비정상적으로 높은 key 를 노출해 rule 튜닝을 돕는다.
   */
  dedupStats(): { total_keys: number; total_fires: number } {
    if (!this.db) return { total_keys: 0, total_fires: 0 };

    const row = this.db
      .prepare<[], { total_keys: number; total_fires: number | null }>(
        `SELECT COUNT(*) AS total_keys, COALESCE(SUM(fire_count), 0) AS total_fires
         FROM dedup_keys`,
      )
      .get();

    return {
      total_keys: row?.total_keys ?? 0,
      total_fires: row?.total_fires ?? 0,
    };
  }
}
