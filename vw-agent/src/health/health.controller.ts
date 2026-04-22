// /health 엔드포인트 — T22 에서 DB/Telegram 상태 추가 예정
// 현재는 프로세스 alive 여부만 반환 (Docker healthcheck 용)
import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  private readonly startedAt = Date.now();

  @Get()
  check(): { status: string; uptimeSec: number; version: string } {
    return {
      status: 'ok',
      uptimeSec: Math.floor((Date.now() - this.startedAt) / 1000),
      version: process.env.npm_package_version ?? '0.1.0',
    };
  }
}
