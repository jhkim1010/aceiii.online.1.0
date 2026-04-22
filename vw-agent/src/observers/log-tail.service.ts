// api-ventago/logs/error-YYYY-MM-DD.log 파일 tail 서비스
// ----------------------------------------------------------------------------
// 동작:
// - 30초 간격으로 "오늘 날짜" 파일을 polling (chokidar inotify 보다 안정적)
// - 마지막 read offset 을 SQLite log_offsets 에 보관 — 재기동 시 이어서 read
// - 파일이 rotate(다음 날짜) 되면 새 파일로 자동 전환
// - 새로운 라인을 한 줄씩 RuleEngine 에 emit (M1 에서는 직접 RULE-05/06 매칭)
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EventEmitter } from 'events';
import * as fs from 'fs';
import * as path from 'path';

import type { Env } from '../config/env.schema';
import { SqliteService } from '../db/sqlite.service';

export interface LogLineEvent {
  filePath: string;
  line: string;
  ts: number;
}

@Injectable()
export class LogTailService extends EventEmitter implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(LogTailService.name);
  private timer: NodeJS.Timeout | null = null;
  private currentFile: string | null = null;
  private logDir = '';

  constructor(
    @Inject(ConfigService) private readonly config: ConfigService<Env, true>,
    private readonly sqlite: SqliteService,
  ) {
    super();
  }

  onModuleInit(): void {
    this.logDir = this.config.get('API_LOG_DIR', { infer: true });

    if (!fs.existsSync(this.logDir)) {
      this.logger.warn(`API_LOG_DIR 가 존재하지 않습니다: ${this.logDir} — tail 비활성`);

      return;
    }

    // 즉시 1회 + 30초 간격
    this.tick();
    this.timer = setInterval(() => this.tick(), 30_000);
    this.logger.log(`로그 tail 시작 (dir=${this.logDir}, interval=30s)`);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private todayFilename(): string {
    const d = new Date();
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');

    return `error-${y}-${m}-${day}.log`;
  }

  private tick(): void {
    try {
      const filename = this.todayFilename();
      const filePath = path.join(this.logDir, filename);

      if (!fs.existsSync(filePath)) {
        // 오늘 파일 미존재 — 정상 (에러 없음)
        return;
      }

      // 파일 rotate 감지
      if (this.currentFile && this.currentFile !== filePath) {
        this.logger.log(`로그 파일 rotate 감지: ${this.currentFile} → ${filePath}`);
      }
      this.currentFile = filePath;

      const stat = fs.statSync(filePath);
      const saved = this.sqlite.getLogOffset(filePath);

      // inode 변경 = 파일 재생성 → offset 리셋
      let startOffset = saved.offset;
      if (saved.inode !== null && saved.inode !== stat.ino) {
        this.logger.log(`inode 변경 감지 — offset 리셋 (file=${filename})`);
        startOffset = 0;
      }

      // 새 데이터 없음
      if (stat.size <= startOffset) {
        return;
      }

      const fd = fs.openSync(filePath, 'r');
      try {
        const length = stat.size - startOffset;
        const buf = Buffer.alloc(length);
        fs.readSync(fd, buf, 0, length, startOffset);

        // 마지막 \n 까지만 읽고, 미완성 라인은 다음 tick 으로
        const text = buf.toString('utf8');
        const lastNl = text.lastIndexOf('\n');
        if (lastNl < 0) return;

        const consumed = text.slice(0, lastNl);
        const lines = consumed.split('\n').filter((l) => l.length > 0);

        for (const line of lines) {
          this.emit('line', {
            filePath,
            line,
            ts: Date.now(),
          } satisfies LogLineEvent);
        }

        const newOffset = startOffset + Buffer.byteLength(consumed, 'utf8') + 1;
        this.sqlite.saveLogOffset(filePath, newOffset, stat.ino);
      } finally {
        fs.closeSync(fd);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`tail tick 오류: ${msg}`);
    }
  }
}
