# Phase 94 — CUIT 자동 채움 · 실측 후 범위 정정 (2026-09-25)

계획서: `.planning/PLAN-2026-09-25-cuit-autocompletar.md`
이 문서는 그 계획을 **코드에 대조한 결과**다. 계획서의 단계 번호를 그대로 쓴다.

---

## 1. ★★ 계획서가 전제한 것과 코드가 다르다 — 「DB 우선」은 **이미 배포돼 돌고 있다**

계획서 §5 의 **단계 2(DB 조회)를 새로 만들면 안 된다.** 이미 있다.

| 자리 | 하는 일 |
|---|---|
| `ventago-app/src/views/homes/components/InfoClient.tsx:283-351` | document 가 8자리(DNI) 또는 11자리(CUIT)가 되면 400ms 뒤 자동 조회. **① 이 매장 `clients` → ② `global-clients/by-document`** 순. 매치되면 `setSelectedClient` 또는 폼 자동 채움 + toast |
| `api-ventago/src/app/global-clients/global-clients.service.ts:106` `findByDocumentWithStoreLink` | `global_clients` → 없으면 **legacy `clients`(호출 매장 → 같은 owner group)** 까지 폴백하고 lazy backfill 까지 한다 |

⤷ 계획서 §3 의 조회 순서(clients → global_clients)는 **이미 구현돼 있다.**
  새 엔드포인트 `GET /clients/por-documento/:doc` 를 만들면 **두 개의 진실**이 된다.

운영 실측(2026-09-25, 계획서 §0-b 와 일치):

| `clients.document` 숫자 길이 | 건수 | 주소 보유 |
|---|---|---|
| **11 (CUIT)** | **546** | **545** |
| 8 (DNI) | 26 | 2 |
| 6 | 24 | 1 |
| 나머지(7·9·12·14) | 8 | 5 |

---

## 2. ★★★ 남은 것은 **ARCA 폴백 하나**이고, 그것은 **막혀 있다**

```
ventago-app 전체에서 `padron` grep → 0건.  (조회 서비스는 api 에 있지만 화면이 안 부른다)
저장소 전체에서 CUIT 검증숫자 판정 → 없음.
```

### 막는 것은 인증서가 아니라 **인증서에 붙은 「서비스별」 권한**이다 (2026-09-25 확인)

사용자 질문: 「우선 coolsistema 에 대한 인증서를 사용하면 안 되나?」
**이미 그걸 쓰고 있다.** `padron-a5.service.ts:100` 의 기본 slug 가 `'coolsistema'` 이고,
그 폴더의 `cert`/`key` 는 **wsfe(CAE 발급)가 쓰는 바로 그 인증서**다(`CNCOOLSISTEMA2024`,
대표 CUIT `20950928434`).

WSAA 는 티켓을 **`(인증서, 서비스)` 쌍**으로 발급한다 —
[[afip-ta-is-per-certificate-not-per-cuit]]. 그 인증서는 `wsfe` 에만 위임돼 있다.
운영 실측: `/app/certificates/coolsistema/token/` 에 `TA-20950928434-wsfe.xml` **하나뿐**.

★ 인증서 없는 우회로는 **없다.** 2026-09-25 에 공개 REST 3경로를 운영 서버에서 직접 쳤고
  **전부 404** 였다:
  `soa.afip.gob.ar/sr-padron/v2/persona/{cuit}` · `…/v1/persona/{cuit}` · `…/v2/constancia/{cuit}`

---

## 3. ★ 잠금을 푸는 길 — 2026-10-20 갱신과 **한 번에** 끝난다

운영 인증서 `CN=CNCOOLSISTEMA2024` 는 **2026-10-20 만료**다. 어차피 갱신해야 하고,
갱신 경로가 곧 위임을 다시 거는 자리다.

**기계 장치는 이미 다 있다** (`afip.controller.ts`):
`POST /afip/cert/csr` → `cert/upload` → `cert/activar` → (되돌리기) `cert/revertir`.
화면도 있다: **Configuración › Facturación › `CertificadoCard.tsx`**.

**2026-09-25 에 한 것** (커밋 `56a89c63`): 그 화면의 **3단계가 `wsfe` 하나만 안내**하고
있었다. 그 안내가 comerciante 가 받는 **유일한 지시**이므로, 거기 없는 것은 영영 위임되지
않는다. `ws_sr_constancia_inscripcion`(Padrón A5)을 **선택 서비스**로 추가했다.

**사람이 해야 하는 것** (포털, 코드 아님):
1. afip.gob.ar → 클라베 피스칼(3등급 이상) → **«Administrador de Relaciones de Clave Fiscal»**
2. **Nueva Relación** → 서비스 검색 → `ws_sr_constancia_inscripcion` (Consulta al Padrón)
3. **Representante** = 인증서 별칭 `CNCOOLSISTEMA2024` (갱신 시에는 새 별칭)

**확인 방법 (확정적)**: `GET /afip/padron/diagnose` (superadmin) → `ticketObtained`.
이게 `true` 가 되기 전에는 계획서 단계 3~5 를 **시작하지 않는다.**

---

## 4. 위임이 끝나면 할 것 (범위 정정본)

| # | 무엇 | 계획서 대비 |
|---|---|---|
| 1 | `cuit.ts` — 11자리 + 검증숫자 판정 (순수 `.ts`) | 그대로 |
| 2 | ~~`GET /clients/por-documento/:doc`~~ | **취소** — §1 대로 이미 있다 |
| 3 | `global-clients/by-document` 가 **못 찾았을 때만** Padrón 호출 + CUIT별 캐시(24h) + 짧은 타임아웃 | 자리가 바뀜(새 엔드포인트가 아니라 기존 것의 꼬리) |
| 4 | `InfoClient` — ARCA 만 **onBlur + 11자리 + 검증숫자 + DB 미발견**일 때. DB 조회의 기존 디바운스는 **그대로 둔다** | 사용자 결정 2026-09-25 |
| 5 | 순수 판정 시험 · 배선 시험 · 돌연변이 | 그대로 |

★ **DB 조회를 Tab 으로 바꾸지 않는다** (사용자 결정 2026-09-25):
  지금 동작이 회귀하면 DNI 8자리 자동 채움까지 죽고 계산원이 Tab 을 눌러야 한다.
  사용자 지시 「11글자 + tab 일 때 그 때만」은 **ARCA 에 대한 것**이다.

★ **매장별 인증서 문제가 남아 있다**: `padron-a5.service.ts` 의 slug 는 환경변수
  (`AFIP_PADRON_CERT_SLUG`, 기본 `coolsistema`) — 곧 **단일 테넌트**다. 자기 인증서를 가진
  매장이 생겨도 padron 조회는 coolsistema 인증서로 나간다. 단계 3 에서 `afip_issuers` 의
  매장 인증서를 쓰도록 같이 고쳐야 한다. (지금 고치면 실행해 볼 수 없다.)

---

## 5. 이 세션에서 실제로 배포한 것

| 저장소 | 커밋 | 내용 |
|---|---|---|
| api | `bd5779c3` | Historial del día 정렬 = 그날 **마지막 입고 시각** (핸드오프 4-2) |
| app | `56a89c63` | 인증서 3단계에 Padrón 서비스 추가 (위 §3) |

★ 정렬은 Phase 94 가 아니라 `HANDOFF-2026-09-25-c` §4-2 의 이월 건이다.
  운영 실측으로 증상 재현: 2026-09-25 madre **337**(21:40) 이 madre **732**(14:34) 보다
  id 가 작아 **옛 규칙에서는 아래로** 갔다.
