# SPEC: Importar Legacy(ACE) — 백업 파일(custom/tar/gzip) 지원
생성일: 2026-07-22

## 목표
Importar Legacy 업로드가 plain `.sql` 뿐 아니라 pg_dump/pgAdmin **백업 파일**(custom `-Fc`, tar `-Ft`, gzip `.sql.gz`)도 받아 처리하도록 확장한다. 기존 `SqlParserService`/`ace-mapping`/`LegacyImportService`는 손대지 않고, 업로드 → plain SQL 텍스트로 **정규화하는 변환 레이어**만 앞단에 추가한다.

## 배경 및 컨텍스트
- 진입점: `LegacyImportController.readSqlFile()` → `service.preview()/runImport()` 에 `sqlText: string` 전달.
- 현재 제약: controller 와 프론트(`accept=".sql,.txt"`) 모두 plain text 만 허용. 파서는 순수 문자열(COPY/INSERT/CREATE) 전용.
- "backup 파일" = 보통 pgAdmin "Backup" 기본값 custom(`PGDMP` 매직) 또는 tar. 바이너리라 파서에 직접 못 넣음.
- 운영: api-ventago = `node:20-alpine` Dockerfile 빌드(Jenkins). PM2 클러스터. **pg_restore 미설치**.
- 로그(`combined-2026-07-20.log`) 확인: legacy-import 관련 에러 없음(라우트 정상 매핑).

## 기술 스택
- 언어/프레임워크: NestJS(TypeScript 5.7), Node 20.
- DB: PostgreSQL — 본 작업은 **DB 미접속**(파서=문자열, pg_restore=`-f` 파일 변환). **connection pool 영향 0**.
- ESLint: `api-ventago/eslint.config.mjs` (typescript-eslint recommendedTypeChecked + prettier). 프론트: ventago-app 자체 설정.

## 핵심 설계 결정
1. **포맷 감지는 매직바이트 우선**: gzip(`1f 8b`), custom(`PGDMP`), tar(offset257 `ustar`), 그 외 plain. (pgAdmin 이 custom 을 `.sql` 로 저장하기도 해 확장자 신뢰 불가.)
2. **plain/gzip 은 프로세스 내 처리**(zlib) — 외부 의존 0, 가장 안전·빠름.
3. **custom/tar 만 `pg_restore` 서브프로세스** — `execFile`(배열 인자, 셸 인젝션 차단), `-f` 출력 모드라 **DB 미접속 → pool 무영향**. 임시파일은 `finally`에서 항상 삭제.
4. **Docker**: runner 스테이지에 `apk add --no-cache postgresql-client` 1줄(코히런트 lib 세트, 빌드 안전). pg_restore 없거나 버전 불일치 시 **친절한 에러로 degrade**(500 금지).
5. 변환 후 크기 상한 가드(200MB)로 메모리 폭주 방지. 업로드 상한 25MB 유지.

## 태스크 목록
- [ ] TASK-1: 신규 `dump-converter.service.ts` — 포맷 감지 + plain SQL 정규화(zlib/pg_restore)
- [ ] TASK-2: `legacy-import.controller.ts` — `readSqlFile`→`prepareSqlText`(async, 확장자+매직 검증, 변환 위임), preview/upload 양쪽 적용
- [ ] TASK-3: `legacy-import.module.ts` — `DumpConverterService` provider 등록
- [ ] TASK-4: `api-ventago/Dockerfile` — runner 에 postgresql-client 추가
- [ ] TASK-5: `ImportLegacyView.tsx` — `accept` 확장자 + 검증 + 안내 문구 갱신
- [ ] TASK-6: ESLint 검증(api 변경 파일) — 오류 0
- [ ] TASK-7: PostgreSQL pool 안전 점검(본 변경 DB 미접속 확인) + 최종 리뷰

## 완료 기준
- ESLint 오류 0개(변경 파일)
- plain `.sql`/`.txt` 기존 동작 불변
- `.sql.gz`(gzip) 프로세스 내 해제 후 파싱
- custom/tar 백업 → pg_restore 변환 후 파싱, pg_restore 부재/버전불일치 시 친절 에러
- DB connection pool 미사용(파서/서브프로세스만)

## 금지사항 / 주의사항
- `SqlParserService`/`ace-mapping.ts`/`LegacyImportService` 로직 변경 금지(정규화만 앞단 추가).
- storeId 격리·admin 가드 등 기존 보안 불변.
- 업로드 25MB 상한 유지.
- Mac 작업트리 미커밋 WIP(afip-issuer.service.ts) 건드리지 말 것.
