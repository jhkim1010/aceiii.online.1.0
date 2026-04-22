// vw-agent 엔트리포인트
// - Winston 로거 초기화 (DailyRotate)
// - NestJS 부트스트랩
// - PORT 환경변수로 /health 제공 (기본 5999)
// - SIGTERM/SIGINT 시 graceful shutdown (pool 누수 방지)
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { WinstonModule } from 'nest-winston';

import { AppModule } from './app.module';
import { winstonConfig } from './common/logger/logger.config';

async function bootstrap(): Promise<void> {
  const logger = WinstonModule.createLogger(winstonConfig);

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    logger,
    bodyParser: true,
  });

  // graceful shutdown — PG pool/SQLite/TelegramBot 해제 훅
  app.enableShutdownHooks();

  const port = parseInt(process.env.PORT ?? '5999', 10);

  await app.listen(port, '0.0.0.0');

  logger.log(`vw-agent 기동 완료 (port=${port}, node=${process.version})`, 'Bootstrap');
}

bootstrap().catch((err) => {
  console.error('[vw-agent] 기동 실패:', err);
  process.exit(1);
});
