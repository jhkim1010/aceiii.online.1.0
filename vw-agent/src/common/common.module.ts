// 공용 모듈 — 전역 이벤트 버스 export
import { Global, Module } from '@nestjs/common';

import { EventBusService } from './event-bus.service';

@Global()
@Module({
  providers: [EventBusService],
  exports: [EventBusService],
})
export class CommonModule {}
