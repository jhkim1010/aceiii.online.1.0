// vw-agent 루트 모듈 — T16 스캐폴딩 단계에서는 Config + Schedule 만 등록
// 후속 T17~ 에서 DB / Observer / Reasoner / Notifier 모듈을 이 곳에 추가한다.
import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';

import { CommonModule } from './common/common.module';
import { ConfigModule } from './config/config.module';
import { DbModule } from './db/db.module';
import { HealthController } from './health/health.controller';
import { NotifierModule } from './notifiers/notifier.module';
import { ObserverModule } from './observers/observer.module';
import { ReasonerModule } from './reasoners/reasoner.module';

@Module({
  imports: [
    ConfigModule,
    ScheduleModule.forRoot(),
    CommonModule,
    DbModule,
    NotifierModule,
    ObserverModule,
    ReasonerModule,
  ],
  controllers: [HealthController],
  providers: [],
})
export class AppModule {}
