// Observer 모듈 — 외부 신호 수집 계층
// M1: LogTailService, PgPollerService, DockerPollerService
// 후속에서 AgentPoller (T21) 추가 예정
import { Module } from '@nestjs/common';

import { DockerPollerService } from './docker-poller.service';
import { LogTailService } from './log-tail.service';
import { PgPollerService } from './pg-poller.service';

@Module({
  providers: [LogTailService, PgPollerService, DockerPollerService],
  exports: [LogTailService, PgPollerService, DockerPollerService],
})
export class ObserverModule {}
