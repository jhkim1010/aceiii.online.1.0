# Phase 69 — UAT (운영 검증)

**측정:** 2026-08-01 (UTC 기준 표기)
**대상:** 운영 `api_ventago` (빌드 #593, `89195af` 이전 코드 = `b1147b5` 반영) / `ventagoapp` (21:04 UTC 생성)
**검증 방법:** 운영 API 직접 호출 + 운영 로그 (사용자 선택: 브라우저 UAT 는 체크리스트로 남김)

---

## 요약

| 결함 | 봉쇄 확인 | 방법 |
|---|---|---|
| R1 `/realtime` 무인증 room 가입 | ✅ PASS | 운영 소켓 프로브 |
| R2 `correct-today` 타 매장 원장 변경 | ⚠️ 코드/테스트 확인 (운영 실증은 인증 필요) | 회귀 스위트 + 코드 |
| R3 벤더 PIN 교차 매장 권한 | ✅ PASS(부분) | 운영 API 401 확인 + 회귀 스위트 |
| R4 파생 스코프 미강제 | ✅ PASS | 운영 부팅 로그 `derivedMode=enforce 대상=39` |
| R5 컨텍스트 fail-open | ✅ PASS | 운영 API 401 + `TENANT-CTX` 차단 로그 0건 |
| 무회귀 (에러·차단 급증 없음) | ✅ PASS | 운영 로그 `[error]` 0 / 403 0 / 소켓 거부 0 |

---

## R1 — `/realtime` 게이트웨이 (운영 실증)

인증 자격증명 없이 운영 소켓에 붙어 room 가입 3종을 시도했다.

```
$ node probe-r1.js            # socket.io-client → https://newapi.coolsistema.com/realtime
connect id=WEZxrleho5sWiwuyAAAB
join_error {"message":"No autenticado"}          ← register_user
join_error {"message":"No autenticado"}          ← register_terminal
join_error {"message":"Sucursal no autorizada"}  ← register_branch
auth_error {"message":"Auth timeout"}
disconnect io server disconnect
connected_at_end=false
```

- 무인증 소켓은 **어느 room 에도 들어가지 못했고**, 유예 시간 후 서버가 **끊었다.**
- 결함 당시라면 `register_user{userId,storeId}` 가 클라이언트 값 그대로 통과해 팀 채팅 본문·MP 결제 승인
  (`intentId`/`paymentId`/금액/판매ID)·매장 공지를 수신했을 자리다.

## R2 — `correct-today` 원장 교차 변경

운영 실증에는 매장 A 사용자 토큰이 필요해 **이번 검증 범위 밖**(사용자 선택: 브라우저/계정 UAT 제외).
대신 두 층에서 확인:

- **코드:** `productStock.service.ts` 가 `scope` 를 **필수 인자**로 받고, `branchIds` 전량 · `variantId` 의
  부모/매장 일치를 검증한 뒤 원장을 만든다. 조회에도 `product`/`branch` 양쪽 `required:true` + `storeId` where 가 걸린다(2중 방어).
- **회귀 스위트:** `npm run test:tenant` R2 4종 통과. 같은 스위트가 구코드(`81474ab`)에서는 실패한다.

→ **잔여 체크리스트(브라우저):** 매장 A 계정으로 상품 → 오늘 입고 정정 저장 시 정상 저장되는지(무회귀) 1회 확인.

## R3 — 벤더 포털 토큰 매장 scope

운영 API (인증 불요 경로만):

```
POST /api/vendor-portal/auth/login  {"phone":"000000000000","pin":"0000"}   → 401
GET  /api/vendor-portal/auth/me     (토큰 없음)                              → 401
GET  /api/vendor-portal/auth/me     (구 토큰 형태: type=vendor + vendorIds[]) → 401
```

구 토큰 형태가 거부되는 것까지 확인했다(서명 불량이라 서명 검증 단계에서 먼저 걸린다 — `TOKEN_LEGACY_REAUTH`
분기 자체는 회귀 스위트 R3 에서 검증).

→ **잔여 체크리스트(벤더 앱):** 실제 벤더 1명 재로그인 → 자기 매장 envío/정산만 보이는지 1회 확인.
동일 전화번호가 2개 매장에 있는 벤더는 매장 선택 화면이 뜬다.

## R4 — 파생 스코프 enforce

운영 부팅 로그(빌드 #593, 23:23 UTC):

```
[TenantGuard] 격리 훅 설치 완료 — mode=enforce 보호모델=114 (글로벌행 허용 8) 제외=30
              | 파생스코프 derivedMode=enforce 대상=39
```

- `derived observe` 라인 **0건** (enforce 이므로 정상).
- 코드 기본값도 `enforce` 로 승격돼 있어 env 유실 시에도 방어막이 유지된다(69-07).
- 상세 증거: `69-OBSERVE-HITS.md`.

## R5 — TenantContext fail-closed

```
GET /api/products?page=1&limit=1  (토큰 없음)  → 401
```

운영 로그(당일 6,240줄 기준):

| 지표 | 값 |
|---|---|
| `[error]` | 0 |
| `TENANT-CTX` (fail-closed 차단) | 0 |
| `403` / `Forbidden` | 0 |
| 소켓 거부(`No autenticado` 등) | 0 (프로브 이전 집계) |
| `격리 누수 감지` 경고 | 1 (`Branch ... store=undefined`, 22:46 UTC) |

`TENANT-CTX` 0건 = **정상 사용자가 fail-closed 에 걸리지 않았다.** 실측상 `store_id IS NULL` 인 계정은
superadmin 1명뿐이고 가드가 먼저 통과시킨다(`69-NULL-STORE-SURVEY.md`).

## 무회귀

| 항목 | 결과 |
|---|---|
| api 컨테이너 | `Up ... (healthy)` — 빌드 #592/#593 모두 SUCCESS |
| 프론트 배포 순서 | app(21:04) → api(22:46/23:23) — 런북 순서 준수 |
| 운영 에러 | 0건 |
| 회귀 스위트 | `npm run test:tenant` 20/20, `npm run test:concurrency` 8/8 |

---

## 남은 확인 (사용자 / 브라우저 · 실계정 필요)

enforce 회귀는 **에러가 아니라 빈 목록**으로 나타나므로 로그만으로는 잡히지 않는다. 다음 1회 순회를 권한다:

- [ ] POS 판매(nueva-venta) — 상품 목록·재고 표시·판매 완료
- [ ] 상품 목록/가격 화면 — 변형·가격 행이 비어 있지 않은지
- [ ] 오늘 입고 정정(`correct-today`) 저장 (R2 무회귀)
- [ ] 팀 채팅 수신 · MP QR 결제 승인 알림 (R1 배선 후 소켓 정상 동작)
- [ ] 프린터(comandera/zebra) 상태 온라인 표시 · 출력 1건
- [ ] 벤더 앱 재로그인 후 자기 매장 데이터만 노출 (R3)
- [ ] 다지점 매장에서 지점 전환 시 목록 갱신 (파생 스코프 enforce 영향 지점)

이상 발견 시 런북 4-1(`TENANT_DERIVED_MODE=observe`) 로 먼저 완화한다.
