// Docker Poller — 운영 컨테이너 상태 수집 (RULE-04)
// ----------------------------------------------------------------------------
// 책임:
//   - dockerode 로 /var/run/docker.sock 에 접속
//   - 주기적으로 `docker ps -a` 상당의 목록 조회
//   - 컨테이너 state / healthcheck status / restart count 를 스냅샷으로 방출
// 안전 규칙:
//   - 소켓 미존재(로컬에서 Docker 없음) 시 warn 만 출력 후 자동 비활성화
//   - 예외 발생 시에도 서비스 중단 금지
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Docker = require('dockerode');
import * as fs from 'fs';

import { EventBusService } from '../common/event-bus.service';
import type { Env } from '../config/env.schema';

export interface ContainerSnapshot {
  id: string;
  name: string;
  image: string;
  state: string; // running | exited | restarting | paused | dead | created
  status: string; // 사람이 읽을 수 있는 상태 문자열
  health: 'healthy' | 'unhealthy' | 'starting' | 'none';
  restartCount: number;
  exitCode: number | null;
}

export interface DockerSnapshot {
  at: Date;
  ok: boolean;
  reason?: string;
  containers: ContainerSnapshot[];
}

export const DOCKER_SNAPSHOT_EVENT = 'docker.snapshot';

@Injectable()
export class DockerPollerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DockerPollerService.name);
  private docker: Docker | null = null;
  private timer: NodeJS.Timeout | null = null;
  private intervalSec = 60;
  private running = false;
  private disabled = false;

  constructor(
    private readonly config: ConfigService<Env, true>,
    private readonly bus: EventBusService,
  ) {}

  onModuleInit(): void {
    this.intervalSec = this.config.get('DOCKER_POLL_INTERVAL_SEC', { infer: true });
    const socketPath = this.config.get('DOCKER_SOCKET_PATH', { infer: true });

    if (!fs.existsSync(socketPath)) {
      this.logger.warn(
        `Docker socket 미존재 (${socketPath}) — DockerPoller 비활성화. 컨테이너 감시는 건너뜁니다.`,
      );
      this.disabled = true;

      return;
    }

    this.docker = new Docker({ socketPath });
    this.logger.log(`Docker Poller 시작 (socket=${socketPath}, 주기=${this.intervalSec}s)`);

    this.timer = setTimeout(() => {
      void this.tick();
      this.timer = setInterval(() => void this.tick(), this.intervalSec * 1000);
    }, 5_000);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
      clearTimeout(this.timer);
      this.timer = null;
    }

    // dockerode 는 명시적 close 없음 (요청마다 short-lived HTTP)
    this.docker = null;
    this.logger.log('Docker Poller 종료');
  }

  private async tick(): Promise<void> {
    if (this.disabled || !this.docker) return;

    if (this.running) {
      this.logger.warn('이전 tick 진행 중 — 이번 tick 건너뜁니다');

      return;
    }

    this.running = true;
    try {
      const snapshot = await this.collect();
      this.bus.emit(DOCKER_SNAPSHOT_EVENT, snapshot);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Docker 상태 수집 실패: ${msg}`);

      // 연결 끊겼을 때도 반드시 ok=false 로 방출 — Rule 에서 판단 가능
      this.bus.emit(DOCKER_SNAPSHOT_EVENT, {
        at: new Date(),
        ok: false,
        reason: msg,
        containers: [],
      } as DockerSnapshot);
    } finally {
      this.running = false;
    }
  }

  private async collect(): Promise<DockerSnapshot> {
    if (!this.docker) {
      return { at: new Date(), ok: false, reason: 'docker_not_initialized', containers: [] };
    }

    // all=true → 중지된 컨테이너도 포함 (exited/restarting 감지 필요)
    const list = await this.docker.listContainers({ all: true });
    const containers: ContainerSnapshot[] = [];

    for (const c of list) {
      // healthcheck status 는 Status 문자열에 "(healthy)" "(unhealthy)" "(health: starting)" 로 들어옴
      let health: ContainerSnapshot['health'] = 'none';
      if (/\(healthy\)/i.test(c.Status)) health = 'healthy';
      else if (/\(unhealthy\)/i.test(c.Status)) health = 'unhealthy';
      else if (/health:\s*starting/i.test(c.Status)) health = 'starting';

      // 개별 inspect 는 비용이 크므로 restart/exit 필요한 경우에만 조회
      let restartCount = 0;
      let exitCode: number | null = null;
      const needsInspect = c.State !== 'running' || health === 'unhealthy';
      if (needsInspect) {
        try {
          const info = await this.docker.getContainer(c.Id).inspect();
          restartCount = info.RestartCount ?? 0;
          exitCode = info.State?.ExitCode ?? null;
        } catch {
          // inspect 실패는 무시 — list 만으로도 기본 판단 가능
        }
      }

      containers.push({
        id: c.Id.slice(0, 12),
        name: c.Names?.[0]?.replace(/^\//, '') ?? 'unknown',
        image: c.Image,
        state: c.State,
        status: c.Status,
        health,
        restartCount,
        exitCode,
      });
    }

    return { at: new Date(), ok: true, containers };
  }
}
