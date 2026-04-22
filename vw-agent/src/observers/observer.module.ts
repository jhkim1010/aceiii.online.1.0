// Observer 모듈 — 외부 신호 수집 계층
// M1: LogTailService, PgPollerService, DockerPollerService, AgentPollerService
import { Module } from '@nestjs/common';

import { AgentPollerService } from './agent-poller.service';
import { DockerPollerService } from './docker-poller.service';
import { LogTailService } from './log-tail.service';
import { PgPollerService } from './pg-poller.service';

@Module({
  providers: [LogTailService, PgPollerService, DockerPollerService, AgentPollerService],
  exports: [LogTailService, PgPollerService, DockerPollerService, AgentPollerService],
})
export class ObserverModule {}
