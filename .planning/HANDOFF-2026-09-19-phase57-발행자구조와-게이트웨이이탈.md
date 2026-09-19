# 핸드오프 2026-09-19 — Phase 57 보강 (발행자 구조 · 게이트웨이 이탈)

## 무엇을 하고 있나

Phase 57 을 사용자 요건 **7개**로 보강 중. 계획서가 권위다:
`.planning/phases/57-*/57-SPEC-ADDENDUM-2026-09-18.md`

| # | 요건 |
|---|---|
| U1 | 매장마다 다른 CUIT (예외는 명시) |
| U2 | 한 매장이 여러 CUIT |
| U3 | 환경 선택 + 시험 7일 상한 |
| U4 | admin/Configuración 셋업 화면 |
| U5 | **cool-invoice 게이트웨이 이탈** (soap+prod 에서 결합 0) |
| U6 | 한 지점에서 여러 CUIT 중 **골라** 발급 |
| U7 | superadmin 이 매장을 ws → soap 으로 돌린다 |
| (추가) | 운영 인증서 만료 1개월 전 알림 — soap 매장만 |

**결정 15건 전부 확정** (D-09 ~ D-20). 계획서 §6 표에 ✅ 로 표시돼 있다.

## 끝난 것 (전부 운영 배포 완료)

| 덩어리 | 내용 |
|---|---|
| **W-A** | 발행자 구조 expand — 동작 변경 0. 마이그레이션 3개(로컬 5432 + 운영 5434 양쪽) |
| **R13** | superadmin ws ↔ soap 전환 스위치 (API + admin 화면) |
| **D6** | 환경 읽기를 발행자 기준으로 + 전표에 발급 당시 환경 |
| **W-B** | **고른 CUIT 이 이긴다** — 선택 우선순위 뒤집기 (U6 서버) |
| **W-E** | 화면 3종 — 발급 모달 선택기 · Emisores por sucursal · Modo AFIP |
| **W-C** | 가드 — 교차 매장 CUIT(U1) · 전표 있는 발행자 삭제 금지 |
| **W-D3** | 시험 7일 상한 — 자동 prod 전환(D-09), 안 되면 차단(D-09b) |
| **R15** | 인증서 만료 1개월 전 알림 + admin 대시보드 카드 |

검증: api `afip` **48 suites / 761 tests** · tsc exit 0.

## 남은 것

| | 내용 | 막는 것 |
|---|---|---|
| **W-D4** | 화면 배너(D-3·D-1) — 서버는 이미 `homoEstado.avisar`·`diasRestantes` 를 준다 | 없음 |
| **W-E4** | Emisores 카드에 인증서 상태(만료일·CA 구분·공유폴더 경고) | 없음 |
| **W-E5** | admin ModalBranch — 그 CUIT 을 쓰는 다른 매장 + 공유 허용 체크 | 없음 |
| **W-E8** | 미리보기(F10)가 보여 준 발행자를 되돌려 보내 서버가 대조 | 없음 |
| **W-F1~F5** | 게이트웨이 이탈 — `57-05` 폐기 · `cool_user`→`cert_slug` · 인증서 전용 디렉터리 · TA 캐시 분리 · 공유 slug 가드 | 없음 |
| **W-F6** | **전용 PV 이전** | ★ **사용자가 ARCA 에 새 PV 등록해야 시작** |

### W-F6 을 시작하려면 사용자에게 받아야 할 것 셋
1. 새 punto de venta 번호
2. 어느 CUIT 의 것인지
3. 언제부터 그것으로 발급할지

★ 순서를 지킬 것: ARCA 등록 → **AFIP 최종번호 조회** → `punto_venta` 변경 +
  `pv_migrado_en` 기록 → 연속성 검증이 전환 이전은 옛 PV 기준으로 보게.
  ④ 를 ③ 보다 먼저 하면 번호열이 끊긴 것으로 보인다(새 PV 는 1번부터 시작한다).

## 지금 운영 데이터 (2026-09-19)

```
afip_issuers  2행 — 둘 다 CUIT 20950928434 (cuit_compartido=true 로 표시됨)
  id 1 · store 6 (cool)  · PV 4 · entorno=prod · cert_slug=coolsistema     · 지점 6·16·25
  id 2 · store 9 (ACE)   · PV 1 · entorno=homo · cert_slug=coolsyncrohomo1 · 지점 14·15
afip_vouchers 21건 — store 6 prod 19 · store 9 homo 2 (전부 issuer_id·entorno 채워짐)
store_configs 둘 다 afip_provider='soap'  ← 기본값은 'ws' 이고 이 둘만 soap 이다
```

★ **시험 7일 시계는 지금 아무 매장에서도 안 돈다.** W-A 백필이 `homo_desde` 를
  일부러 NULL 로 뒀다. 누군가 전환 스위치로 homo 를 **새로 고르는 순간**부터 돈다.

## 이 phase 에서 반복해 확인된 것 (다음 세션도 같은 함정을 만난다)

1. **호출부 시험이 빠진다.** 판정기만 시험하면 호출부가 결과를 버려도 아무것도 안 깨진다.
   W-D6 과 W-D3 에서 **두 번** 같은 구멍에 빠졌다. 돌연변이가 살아남으면 그 신호다.
2. **돌연변이가 「Tests: 0」 이면 무효다** — 컴파일이 깨져 안 돈 것이다. 이번에 4건.
   컴파일되는 변종으로 다시 재야 한다.
3. **대조군이 같이 통과하면 검사가 없는 것.** 「고른 것 ≠ 지점 기본값」처럼 **일부러
   갈라 놓은** 상태로만 검증이 성립한다.
4. **생성자 인자는 맨 뒤에.** spec 이 손으로 `new` 하므로 중간에 끼우면 인자가 밀린다
   (10개 시험이 깨졌고, 그 파일 주석이 이미 경고하고 있었다).
5. **`git add` 와 `git commit` 을 한 명령에 쓰지 말 것.** 훅이 add 이전 index 를 본다.

## 참고 — 게이트웨이 결합 전수 (U5 의 작업 목록)

| | 결합 | 상태 |
|---|---|---|
| G1 | 인증서 폴더가 cool-invoice 테넌트 폴더에 중첩 마운트 | 살아 있음 (W-F3) |
| G2 | WSAA TA 캐시 `.lastTokens` 공유 | 살아 있음 (W-F4) |
| G3 | PV 4 번호열 공유 | 살아 있음 (W-F6, 사용자 대기) |
| G4 | `cool_user` 가 인증서 slug 의 출처 | 살아 있음 (W-F2) |
| G5 | manager PV 해석 | **폐기 확정** — 만들지 않는다 |
| G6 | `invoice.coolsistema.com` 릴레이 | ws 전용, 남긴다 |
| G7 | 외부 발급 원장 | G3 의 대증요법, 과거분 유지 |
