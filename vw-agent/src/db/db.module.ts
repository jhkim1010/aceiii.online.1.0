// DB 모듈 — PG read-only pool + SQLite 를 글로벌로 등록
import { Global, Module } from '@nestjs/common';

import { PgReadonlyService } from './pg-readonly.service';
import { SqliteService } from './sqlite.service';

@Global()
@Module({
  providers: [PgReadonlyService, SqliteService],
  exports: [PgReadonlyService, SqliteService],
})
export class DbModule {}
