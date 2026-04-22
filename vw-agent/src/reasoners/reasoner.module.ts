// Reasoner 모듈 — 신호 → 판단 계층
// M1: LogRulesService (RULE-05/06), PgRulesService (RULE-01/02/03),
//     DockerRulesService (RULE-04), AgentRulesService (RULE-07),
//     HeartbeatService (RULE-08)
import { Module } from '@nestjs/common';

import { ObserverModule } from '../observers/observer.module';

import { AgentRulesService } from './agent-rules.service';
import { DockerRulesService } from './docker-rules.service';
import { HeartbeatService } from './heartbeat.service';
import { LogRulesService } from './log-rules.service';
import { PgRulesService } from './pg-rules.service';
import { RuleEngineService } from './rule-engine.service';

@Module({
  imports: [ObserverModule],
  providers: [
    RuleEngineService,
    LogRulesService,
    PgRulesService,
    DockerRulesService,
    AgentRulesService,
    HeartbeatService,
  ],
  exports: [
    RuleEngineService,
    LogRulesService,
    PgRulesService,
    DockerRulesService,
    AgentRulesService,
    HeartbeatService,
  ],
})
export class ReasonerModule {}
