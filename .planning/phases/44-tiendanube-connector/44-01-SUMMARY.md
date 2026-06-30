# 44-01 SUMMARY — OAuth2 인증 + 채널 설정

> Wave: 44-01 · 상태: ✅ 코드 완료 (정적 검증 PASS, 빌드/lint 는 사용자 Mac)
> 일자: 2026-06-27

## 완료된 태스크

- [x] TASK-1: `tiendanube.client.ts` — axios 클라이언트 (bearer + User-Agent + x-rate-limit 파싱 + 429 판별)
- [x] TASK-2: `tiendanube-oauth.service.ts` — authorization_code 토큰 교환 + external_meta 저장
- [x] TASK-3: ensureAuth 토대(readAuthMeta) + app/uninstalled 처리(handleUninstall → 채널 비활성·토큰 제거)
- [x] TASK-4: 채널 컨트롤러/서비스 + location 매핑(listLocations/saveLocationMap)

## 생성 파일

| 파일 | 내용 |
|---|---|
| `adapters/tiendanube/tiendanube.client.ts` | TN REST 2025-03 클라이언트. ping/getOrder/findProductIdBySku/createProduct/updateProduct/putVariants/patchStockPrice(벌크)/listLocations. rate-limit 인터셉터 |
| `adapters/tiendanube/tiendanube-oauth.service.ts` | OAuth2 교환(exchangeCode), external_meta 저장(saveAuthMeta), uninstall(handleUninstall), 토큰 로드(readAuthMeta). TnAuthMeta 타입 |
| `adapters/tiendanube/tiendanube-channel.service.ts` | 채널 생성(channelKey/secret 발급)/목록/location 매핑 |
| `adapters/tiendanube/tiendanube-channel.controller.ts` | admin 엔드포인트 — create/exchange-code/locations/location-map |
| `adapters/tiendanube/dto/tiendanube.dto.ts` | Create/ExchangeCode/LocationMap/Upsert DTO |
| `adapters/tiendanube/tiendanube.module.ts` | 모듈 골격 (어댑터 본체·webhook 은 44-02/03) |

## 변경 파일
- `app.module.ts` — TiendaNubeModule 등록

## 핵심 설계 반영

- **OAuth 토큰은 external_meta(jsonb)** 에 저장(D-44-3) — accessToken·tnStoreId·scope·locationMap
- **uninstall 시 채널 비활성 + accessToken 제거**(토큰 무효 수명주기)
- **rate-limit 인터셉터** — x-rate-limit-* 파싱, isRateLimited(429) 정적 헬퍼 → 44-04 백오프 토대
- **벌크 patchStockPrice** 클라이언트 메서드 준비 (D-44-4, push 는 44-02)
- 코어 패턴 준수: catch(e:unknown)+errMessage, declare id(CommerceChannel 재사용), no-unused 0

## 정적 검증 (샌드박스)

- ✅ import 경로 실재 (auth/users/core 전부)
- ✅ catch(e:any)/:any 잔존 0
- ✅ errMessage import 전부 연결
- ✅ newline-before-return 위반 0 (1건 수정)
- ✅ require-await: exchangeCode 위임 메서드 async 제거. 컨트롤러 패턴은 기존 wp 전례와 동일(허용)
- ✅ no-unused-vars: 모든 import 사용, DTO 데코레이터 일치

## 환경변수 (운영 설정 필요)

- `TN_APP_ID` — TN 앱 ID (설치 URL)
- `TN_CLIENT_ID` / `TN_CLIENT_SECRET` — OAuth 토큰 교환
- `TN_USER_AGENT` (선택) — 기본 'Ventago ERP (soporte@coolsistema.com)'

## 사용자 Mac 검증 (2026-06-27)

- ✅ `npm run build` (nest build) — **0 에러**
- ✅ ESLint — **no-unsafe/타입 에러 0**. prettier 포맷 6건만 발생 → 전부 수정(import 한 줄/긴 리터럴 줄바꿈/lastRate 객체 줄바꿈/단일 return 블록화). 80자 초과 라인 0 재확인.

→ Wave 44-01 닫힘. 타입 안전성은 처음부터 깨끗(Phase 43 패턴 선적용 효과).

## 후속

- Wave 44-02: TiendaNubeAdapter(CommerceConnector) — pushProduct/pushStock/pushPrice + registry 등록 + ensureAuth
- ⏳ TN 파트너 homologation 신청 병행 시작 권장
