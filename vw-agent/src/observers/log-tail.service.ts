// api_ventago 컨테이너의 Winston 로그를 `docker exec tail -F` 로 실시간 스트리밍
// ----------------------------------------------------------------------------
// 배경:
//   운영 서버(srv803182)의 api_ventago 컨테이너는 Jenkins 로 빌드되며, host
//   bind-mount 나 named volume 없이 /app/logs/ 내부에만 로그를 기록한다.
//   따라서 호스트 파일시스템 tail 이 불가능 → docker.sock 을 통한 `docker exec`
//   stream 방식으로 로그 라인을 구독한다.
//
// 동작:
//   - dockerode.getContainer(name).exec({Cmd:['tail','-F','/app/logs/combined-YYYY-MM-DD.log']})
//   - 시작 시 `tail -n 0 -F ...` 로 historical 라인 skip (재기동 폭주 방지)
//   - daily rotate 대응: 자정에 파일명이 바뀌므로 타이머로 새 파일 재탐지
//   - BusyBox tail 도 `-F` 지원 (inode 변경 시 자동 재오픈)
//   - stream 끊김 / 컨테이너 재시작 시 지수 백오프로 재연결
//
// 안전 원칙:
//   - exec 은 1개만 유지 (중복 방지), 재연결도 직렬화
//   - API_VENTAGO_CONTAINER 빈값 → 완전 비활성 (dev 환경 배려)
//   - Docker 소켓 미존재 → 경고만, 나머지 서비스는 계속 동작
//   - line 처리 중 예외는 격리 (reasoner 에서 throw 해도 stream 유지)
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Docker from 'dockerode';
import { EventEmitter } from 'events';
import * as fs from 'fs';
import { Writable, type Readable } from 'stream';

import type { Env } from '../config/env.schema';

export interface LogLineEvent {
  containerName: string;
  filePath: string;
  line: string;
  ts: number;
}

type ExecStream = Readable & { destroy?: (err?: Error) => void };

@Injectable()
export class LogTailService extends EventEmitter implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(LogTailService.name);
  private docker: Docker | null = null;
  private containerName = '';
  private logPathPattern = '/app/logs/combined-YYYY-MM-DD.log';
  private currentFile: string | null = null;
  private stream: ExecStream | null = null;
  private rotateTimer: NodeJS.Timeout | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private reconnectAttempts = 0;
  private disabled = false;
  private shuttingDown = false;
  private lineBuffer = '';

  constructor(@Inject(ConfigService) private readonly config: ConfigService<Env, true>) {
    super();
  }

  onModuleInit(): void {
    this.containerName = this.config.get('API_VENTAGO_CONTAINER', { infer: true });
    this.logPathPattern = this.config.get('API_VENTAGO_LOG_PATTERN', { infer: true });
    const socketPath = this.config.get('DOCKER_SOCKET_PATH', { infer: true });

    if (!this.containerName) {
      this.logger.warn('API_VENTAGO_CONTAINER 미설정 — 로그 tail 비활성화');
      this.disabled = true;

      return;
    }

    if (!fs.existsSync(socketPath)) {
      this.logger.warn(`Docker socket 미존재(${socketPath}) — 로그 tail 비활성화`);
      this.disabled = true;

      return;
    }

    this.docker = new Docker({ socketPath });
    this.logger.log(
      `로그 tail 시작 (container=${this.containerName}, pattern=${this.logPathPattern})`,
    );

    // 즉시 연결 시도
    void this.openStream();

    // 매 분마다 "오늘 파일" 경로 재계산 → 자정 rotate 감지
    this.rotateTimer = setInterval(() => this.checkRotate(), 60_000);
  }

  onModuleDestroy(): void {
    this.shuttingDown = true;
    if (this.rotateTimer) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = null;
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.closeStream();
    this.docker = null;
    this.logger.log('로그 tail 종료');
  }

  /** YYYY-MM-DD 를 오늘 날짜로 치환한 실제 로그 파일 경로 */
  private resolveFilePath(): string {
    const d = new Date();
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const today = `${y}-${m}-${day}`;

    return this.logPathPattern.replace('YYYY-MM-DD', today);
  }

  /** 자정 rotate 감지 — 파일명이 바뀌면 stream 재연결 */
  private checkRotate(): void {
    if (this.disabled || this.shuttingDown) return;
    const expected = this.resolveFilePath();
    if (this.currentFile && expected !== this.currentFile) {
      this.logger.log(`일일 rotate 감지: ${this.currentFile} → ${expected} — stream 재연결`);
      this.closeStream();

      // 약간 여유를 두고 재연결 (새 파일 생성 대기)
      setTimeout(() => void this.openStream(), 2_000);
    }
  }

  /** exec stream 열기 — tail -n 0 -F 로 시작 이후 라인만 수신 */
  private async openStream(): Promise<void> {
    if (this.disabled || this.shuttingDown || !this.docker) return;
    if (this.stream) {
      this.logger.warn('이미 stream 열려있음 — openStream 무시');

      return;
    }

    const filePath = this.resolveFilePath();
    this.currentFile = filePath;

    try {
      const container = this.docker.getContainer(this.containerName);

      // 컨테이너 존재/실행 여부 확인 — 없으면 재연결 루프
      const info = await container.inspect();
      if (!info.State?.Running) {
        throw new Error(
          `컨테이너 ${this.containerName} 가 실행 중이 아님 (state=${info.State?.Status})`,
        );
      }

      const exec = await container.exec({
        Cmd: ['tail', '-n', '0', '-F', filePath],
        AttachStdout: true,
        AttachStderr: true,
        Tty: false,
      });

      const stream = (await exec.start({ hijack: true, stdin: false })) as ExecStream;
      this.stream = stream;
      this.reconnectAttempts = 0;

      // dockerode 는 multiplexed stream 이지만 Tty:false + demuxStream 미사용 시
      // stdout 와 stderr 가 8바이트 header 단위로 섞여 들어옴. demuxStream 사용.
      const stdoutSink = new Writable({
        write: (chunk: Buffer, _enc: string, cb: () => void) => {
          this.onChunk(chunk, filePath);
          cb();
        },
      });
      const stderrSink = new Writable({
        write: (chunk: Buffer, _enc: string, cb: () => void) => {
          const msg = chunk.toString('utf8').trim();
          if (msg) this.logger.warn(`tail stderr: ${msg}`);
          cb();
        },
      });
      this.docker.modem.demuxStream(stream, stdoutSink, stderrSink);

      stream.on('end', () => {
        this.logger.warn(`tail stream 종료 (file=${filePath}) — 재연결 예약`);
        this.stream = null;
        this.scheduleReconnect();
      });
      stream.on('error', (err: Error) => {
        this.logger.warn(`tail stream 오류: ${err.message}`);
        this.stream = null;
        this.scheduleReconnect();
      });

      this.logger.log(`tail stream 연결 완료 (file=${filePath})`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`tail stream 연결 실패 (file=${filePath}): ${msg}`);
      this.stream = null;
      this.scheduleReconnect();
    }
  }

  /** stream chunk 를 라인 단위로 분해 → 'line' 이벤트 방출 */
  private onChunk(chunk: Buffer, filePath: string): void {
    try {
      this.lineBuffer += chunk.toString('utf8');
      let idx: number;
      while ((idx = this.lineBuffer.indexOf('\n')) >= 0) {
        const line = this.lineBuffer.slice(0, idx).replace(/\r$/, '');
        this.lineBuffer = this.lineBuffer.slice(idx + 1);
        if (!line) continue;

        // Reasoner 가 throw 해도 stream 유지
        try {
          this.emit('line', {
            containerName: this.containerName,
            filePath,
            line,
            ts: Date.now(),
          } satisfies LogLineEvent);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          this.logger.warn(`line 처리 중 예외: ${msg}`);
        }
      }

      // 라인 버퍼가 비정상적으로 크면 잘라냄 (10MB 넘는 단일 라인 방어)
      if (this.lineBuffer.length > 10 * 1024 * 1024) {
        this.logger.warn(`lineBuffer overflow(${this.lineBuffer.length}) — 리셋`);
        this.lineBuffer = '';
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`onChunk 예외: ${msg}`);
    }
  }

  /** 지수 백오프 재연결 (1s → 2s → 4s → ... 최대 60s) */
  private scheduleReconnect(): void {
    if (this.disabled || this.shuttingDown) return;
    if (this.reconnectTimer) return; // 이미 예약됨

    this.reconnectAttempts += 1;
    const delay = Math.min(60_000, 1_000 * 2 ** Math.min(this.reconnectAttempts - 1, 6));
    this.logger.log(`tail stream 재연결 예약 (${delay}ms, 시도=${this.reconnectAttempts})`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.openStream();
    }, delay);
  }

  private closeStream(): void {
    if (!this.stream) return;
    try {
      this.stream.destroy?.();
    } catch {
      /* noop */
    }
    this.stream = null;
    this.lineBuffer = '';
  }
}
