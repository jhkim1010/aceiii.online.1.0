// 전역 이벤트 버스 — Observer → Reasoner 간 단순 pub/sub
// ----------------------------------------------------------------------------
// NestJS 의 @nestjs/event-emitter 를 안 쓰고 Node 기본 EventEmitter 를 감싼다.
//   - 외부 의존성 최소화 (M1 목표: 가볍고 안정적)
//   - 메모리 누수 방지: setMaxListeners(50), 명시적 removeAllListeners() on destroy
// ----------------------------------------------------------------------------
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { EventEmitter } from 'events';

@Injectable()
export class EventBusService extends EventEmitter implements OnModuleDestroy {
  private readonly busLogger = new Logger(EventBusService.name);

  constructor() {
    super();
    this.setMaxListeners(50);
  }

  onModuleDestroy(): void {
    this.removeAllListeners();
    this.busLogger.log('EventBus 종료 — 모든 리스너 해제');
  }
}
