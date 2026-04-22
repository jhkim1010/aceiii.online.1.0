// Reasoner 모듈 — 신호 → 판단 계층
// M1: LogRulesService (RULE-05/06), PgRulesService (RULE-01/02/03),
//     DockerRulesService (RULE-04)
// 후속 T21: AgentRules (RULE-07), HeartbeatService (RULE-08)
import { Module } from '@nestjs/common';

import { ObserverModule } from '../observers/observer.module';

import { DockerRulesService } from './docker-rules.service';
import { LogRulesService } from './log-rules.service';
import { PgRulesService } from './pg-rules.service';

@Module({
  imports: [ObserverModule],
  providers: [LogRulesService, PgRulesService, DockerRulesService],
  exports: [LogRulesService, PgRulesService, DockerRulesService],
})
export class ReasonerModule {}
