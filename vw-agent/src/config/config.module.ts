// 전역 ConfigModule — zod 로 검증된 Env 를 DI 에 등록
import { Global, Module } from '@nestjs/common';
import { ConfigModule as NestConfigModule } from '@nestjs/config';

import { loadEnv } from './env.schema';

// 환경변수 검증 후 값을 반환하는 factory
const validatedConfig = () => loadEnv();

@Global()
@Module({
  imports: [
    NestConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      load: [validatedConfig],
    }),
  ],
  exports: [NestConfigModule],
})
export class ConfigModule {}
