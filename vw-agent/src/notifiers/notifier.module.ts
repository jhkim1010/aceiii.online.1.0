// Notifier 모듈 — Telegram 송신만 (M2 에서 LLM advisor 추가 예정)
import { Global, Module } from '@nestjs/common';

import { TelegramService } from './telegram.service';

@Global()
@Module({
  providers: [TelegramService],
  exports: [TelegramService],
})
export class NotifierModule {}
