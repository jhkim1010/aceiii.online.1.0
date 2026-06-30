# SPEC: Phase 44 — Tienda Nube Connector
생성일: 2026-06-27

## 목표

Phase 43 코어 위에 Tienda Nube 어댑터를 구현한다. OAuth2 인증 + 상품/재고/가격 push(벌크 우선) + webhook 주문 ingest(online_orders 백본) 를 `CommerceConnector` 계약으로 완성하고, 관리 UI 와 homologation 준비까지 한다.

## 배경 및 컨텍스트

상세는 `44-CONTEXT.md`. 핵심:
- 코어 계약: `integrations/core/commerce-connector.interface.ts`
- 어댑터 위치: `integrations/adapters/tiendanube/`
- 인증 저장: `commerce_channels.external_meta` jsonb
- 주문 경로: `online_orders` (Phase 27/28 hold+mirror)
- TN API: REST 2025-03, OAuth2, `PATCH /products/stock-price` 벌크, `x-linkedstore-hmac-sha256`, 3초 timeout

## 기술 스택

- NestJS 11 + TypeScript, Sequelize
- HTTP: axios (WcClient 패턴 참고한 TiendaNubeClient)
- 코어 패턴 준수: declare id, catch(e:unknown)+errMessage, raw `as unknown as T[]`

## 태스크 목록

### Wave 44-01 — OAuth2 인증 + 채널 설정
- [ ] TASK-1: `adapters/tiendanube/tiendanube.client.ts` — axios 클라이언트(base URL, bearer, User-Agent, x-rate-limit 파싱)
- [ ] TASK-2: OAuth2 authorization_code 플로우 — install redirect + `POST /apps/authorize/token` 토큰 교환. access_token + tn_store_id 를 `external_meta` 저장
- [ ] TASK-3: `ensureAuth(ctx)` 구현 — external_meta 토큰 유효성 확인, app/uninstalled 시 채널 비활성
- [ ] TASK-4: 채널 생성/연동 컨트롤러·서비스(platform='tiendanube'). location 매핑(branch↔location) external_meta 저장

### Wave 44-02 — 상품/재고/가격 push 어댑터
- [ ] TASK-5: `TiendaNubeAdapter implements CommerceConnector` 골격 + registry 등록
- [ ] TASK-6: `pushProduct` — 상품/변형 생성·갱신(`POST/PUT /products`, `PUT /products/{id}/variants`). ResolvedProduct → TN payload 변환(promotional_price, inventory_levels)
- [ ] TASK-7: `pushStock`/`pushPrice` — `PATCH /products/stock-price` 벌크 우선, single fallback. inventory_levels + location_id
- [ ] TASK-8: `testConnection` — `GET /products?per_page=1` ping

### Wave 44-03 — webhook 주문 ingest (3초 timeout 대응)
- [ ] TASK-9: `tiendanube.guard.ts` — `x-linkedstore-hmac-sha256` raw body HMAC 검증(NestJS rawBody 확보)
- [ ] TASK-10: webhook 컨트롤러 — order/created·paid·cancelled 수신. **즉시 200 ACK** 후 async enqueue(3초 timeout 대응)
- [ ] TASK-11: `parseOrder` + fetch-after-notify — minimal payload → `GET /orders/{id}` 재조회(트랜잭션 밖) → NormalizedOrder
- [ ] TASK-12: 주문 → `online_orders` ingest(D-44-1) — SkuMatcher 재사용 + Phase 28 hold + external_order_id 멱등 dedup

### Wave 44-04 — 관리 UI + UAT
- [ ] TASK-13: 프론트 — TN 채널 연결(OAuth 시작 버튼)·sync 토글·연결 테스트·location 매핑 UI
- [ ] TASK-14: rate limit 백오프 — 429/x-rate-limit 시 outbox 재시도. 벌크 PATCH 경로 검증
- [ ] TASK-15: UAT — 데모스토어(10상품)로 push(simple+variant)·webhook 주문·취소·멱등 시나리오

### Wave 44-05 — homologation 준비 (출시 게이트)
- [ ] TASK-16: 시퀀스 다이어그램(인증/push/webhook) + 데모 영상 스크립트
- [ ] TASK-17: 필수 webhook(app/uninstalled, LGPD redact 해당 시) 구현 점검
- [ ] TASK-18: TN 파트너 homologation 미팅 체크리스트

## 완료 기준

- ESLint 0 (core+adapters, declare id/unknown/raw 캐스팅 패턴)
- `npm run build` 통과
- Jest: parseOrder/HMAC 검증/payload 변환 단위 테스트 PASS
- 데모스토어에서 push(simple+variant) + webhook 주문 ingest + 취소 + 멱등 동작
- outbox 경로로 push, pool 안전(신규 pool 0, 외부 API 트랜잭션 밖)
- 코어 인터페이스 변경 없이 어댑터만으로 완성(인터페이스 충분성 검증)

## 금지사항 / 주의사항

- webhook 핸들러에서 동기 처리 금지(3초 timeout) — 즉시 ACK + async
- 외부 API(TN REST) 호출을 DB 트랜잭션 안에서 금지(pool)
- raw SQL 회피, Sequelize 모델 경유. 새 모델엔 `declare id`
- catch(e:unknown)+errMessage, raw 결과 `as unknown as T[]`
- 주석 한국어/함수·변수명 영어/모든 async try-catch
- 양방향 재고 pull 금지. stock deprecated 필드 금지(inventory_levels 사용)
- 코어(`integrations/core/`) 수정 최소화 — 어댑터로 해결 우선. 불가피한 인터페이스 변경은 사용자 확인

## Wave 의존성

```
44-01 (OAuth/채널) → 44-02 (push) → 44-03 (webhook ingest) → 44-04 (UI/UAT) → 44-05 (homologation)
```

homologation(44-05)은 코드와 분리된 출시 게이트 — 파트너 신청은 44-01 과 병행 시작 권장.
