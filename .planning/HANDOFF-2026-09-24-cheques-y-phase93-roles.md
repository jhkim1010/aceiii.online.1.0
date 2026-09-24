# 핸드오프 2026-09-24 — 수표 여러 장 배포 · Phase 93 **2단계까지** 완료

다음 세션은 §3 부터 읽으면 된다. **다음 일은 Phase 93 4단계(contract)이고, 그 전에
3단계 「관찰」이 필요하다** — 오늘 넘어가면 안 된다(§3).

---

## 1. 이 세션에 배포된 것 — 전부 SUCCESS

| Jenkins | 커밋 | 내용 |
|---|---|---|
| front **#782** | `229f58d9` | 수표 여러 장 + 「Agregar cheques」 버튼 |
| front **#783** | `72afeba3` | 수표 지우기 확인창 (기본 포커스 「아니요」) |
| api **#944** | `9a372b87` | Phase 93 1단계 + 백업 `afip_issuer_branches` |

컨테이너 재생성 확인함. nginx → 5003, `/api/health` 200, 오류 로그 0.

**마이그레이션**: `2026-09-24-phase93-p2-migrar-roles-viejos.sql` —
**운영(5434)·로컬(5432) 양쪽 적용 완료**. 둘 다 ROLLBACK 시험 선행.
커밋 `2135e271` 은 **아직 push 안 됨**(SQL 파일뿐이라 배포 불필요).

★ 사용자가 **이전된 계정으로 운영 로그인 성공을 확인**했다(2026-09-24).

---

## 2. 수표 여러 장 — 완료

**설계**: 수표 한 장 = 결제줄 하나. 백엔드가 줄마다 수표를 만들고 그 줄의 금액을 쓴다
(`sales-create.service.ts:2578`). 합쳐 보내면 어느 종이에도 없는 금액의 수표가 카르테라에 남는다.

- `cheques-pago.ts` — 검증·중복판정·목록 조립 (순수)
- `ChequeCampos.tsx` — 6개 필드 **한 곳**. 카하 대화상자와 결제 모달이 공유
- `ChequesDialog.tsx` — 닫히지 않고 쌓인다. **복사본** 위에서 일해 Cancelar 가 진짜 취소
- `PagoInline.tsx` — cheque 줄엔 금액칸이 **없다**. 「Agregar cheques」 버튼 + 목록 + 바닥줄 합계
- `ConfirmarQuitarCheques.tsx` — F9/RePág/AvPág·MP QR 이 수표를 지울 때. **기본 포커스가 「No」**

★ 착수 전 대조에서 찾은 결함: AutoEfectivo 의 「단일 결제」 분기가 수표 줄도 총액으로
  덮어썼다 — 12.000 짜리 수표로 다 내고 상품 하나 추가하면 20.000 으로 저장됐다.

★ CODEX 6건 전부 반영. 가장 무거운 것: **같은 수단 줄이 둘일 때** 총액 변경·derrame 이
  둘을 하나로 뭉개 금액과 `optionId` 를 잃었다(모달이 같은 카드의 다른 cuota 를 두 줄로
  만들 수 있다). `sumarEnUltimaLineaDeSlug` 로 그 줄만 고친다. **이건 원래 있던 결함이다.**

### 남은 것 (안 했음)
- 서버에 **수표 중복 거절이 없다**. 지금은 프론트 두 경로에서만 막는다.
  `(store, bank, number)` 유일성은 마이그레이션이 필요해 따로 물어야 한다.

---

## 3. ★ Phase 93 — 다음 일은 **3단계 관찰**, 그다음 4단계

계획서: `.planning/phases/93-permisos-4-niveles/93-PLAN.md`. ROADMAP 2185행 갱신함.

| 단계 | 상태 |
|---|---|
| 0 선행 결함 5건 | ✅ #943 |
| 1 구 역할 생성 중단 (expand) | ✅ #944 |
| 2 역할 데이터 이전 (migrate) | ✅ 양쪽 DB |
| **3 관찰** | ⏳ **여기** |
| 4 contract — alias 제거 + 구 역할 DELETE | 다음 |
| 5·6·7 UI | 미착수 |

### 3단계에 무엇을 보나

**최소 JWT 최대 수명 이상** 기다린다. 오늘 4단계로 넘어가면 아직 살아 있는 토큰이
없는 역할을 찾는다.

- `docker logs api_ventago | grep '\[perm\]'` — 이름을 대고 막힌 것
- 403 · `/unauthorized` 도달
- 이전된 12명이 실제로 일하는가 (1명은 확인됨)

### 4단계에서 지울 것 (지금은 살아 있다)

- `roles` 의 `store_owner`·`store_admin`·`branch_manager` 행 (매장마다 3개)
- 그에 매달린 `role_functions` **8,155행**
- `user-role.guard.ts`·`branch-scope.util.ts` 의 alias
- `admin-role.guard.ts` 의 `ADMIN_ROLES` 에서 구 slug 2개
- `folder-access-resolver.service.ts` 의 `ELEVATED_ROLE_SLUGS` 에서 `store_owner`
- `setup-guide.rules.ts` 의 `SETUP_GUIDE_ROLES` 에서 `branch_manager`
- `storeTemplate.service.ts` 의 `FULL_ACCESS_ROLES` 에서 `store_owner`
- `auth.service.ts` `BACKFILL_FULL_ROLES` 에서 구 slug 2개
- `rol-administrador.ts` 의 `store_owner` 폴백
- 소스 전체 구 slug **130곳 · 파일 33개**(비-spec 26개)

★ `seed-roles-retirados.spec.ts` 가 「구 slug 는 계속 **인식**돼야 한다」를 단언하고 있다.
  4단계는 그 단언을 **뒤집는 것**이 일의 일부다.

---

## 4. 2단계에서 판단이 바뀐 것 — 다음 단계에도 적용된다

### ★★ 「권한 합집합」을 실측이 뒤집었다

계획서는 admin ∪ store_owner ∪ store_admin 이었다. 실측:
매장 3(CART)·8(genius) 의 기존 `admin` 이 `store_owner` 보다 **3개 적은데** 그게
**「카하 영구 삭제 · 터미널 영구 삭제 · 사용자 삭제」**다. 그 매장들의 `store_owner` 는
**사용자 0명**이라, 합집합은 **아무도 안 쓰던 파괴 권한을 실제 admin 에게 새로 주는 일**.

⤷ 규칙: **사용자가 실제로 옮겨 가는 곳에서만** 권한을 보장한다. 이미 있는 역할은
  한 칸도 안 넓힌다. 결과로 매장마다 admin 기능 수가 다르다(179·180·182) — 그게 사실이다.
⤷ 사용자 확인: 「맞다 — 안 주는 게 맞다」

### ★★ 검증이 자기 책임 밖을 보면 옳은 작업이 막힌다

첫 검증은 「사용자가 있는 매장은 전부 관리자 ≥1」이었다. 로컬에서 **3개가 걸렸는데**
전부 Phase 86 시험용 `ZZ-P86-*` 로, 사용자에게 `user_roles` 가 아예 없어 **이전 전부터**
관리자가 0명이었다. 이 마이그레이션이 만든 상태가 아니다.

⤷ 불변식을 **「관리자가 있던 매장은 잃지 않는다」**로 좁혔다.
⤷ 시험용 매장은 **지우지 않았다**. 남아서 생기는 영향은 SQL 파일에 적었다 —
  전 매장을 훑는 검사가 「관리자 0명」으로 걸린다. 그 검사들이 범위를 좁혀야 한다.

---

## 5. 미결 (사용자가 아직 정하지 않음)

1. **프로비저닝 경로 결함 2건** (codex, 전부터 있던 것)
   - `provisionStoreAndOwner` 전체가 **단일 트랜잭션이 아니다** → 중간 실패 시 매장·사용자가
     고아로 남고 재시도는 alias/email 중복에 걸려 복구 불가.
     ★ 이번에 「역할 못 찾으면 throw」로 바꿔 **더 잘 보이게** 됐다. 고아는 그대로.
   - `POST /store/new`(superadmin 콘솔)는 역할만 시드하고 **관리자 사용자를 안 만든다** →
     관리자 0명 매장을 `success: true` 로 반환.
   ★ 2단계 검증이 **실제로 그런 매장 3개를 찾아냈다**(시험용이지만 형태가 같다).
     이제 숫자를 알고 고칠 수 있다 — 추측으로 짓지 않아도 된다.

2. **서버 수표 중복 거절** (§2)

3. 같은 이름 descuento 를 말없이 거부 (`InvoiceAditional.tsx` 의 `discounts.some(...) return`)

4. **push 안 한 커밋**: api `2135e271`(마이그레이션 SQL) · 루트 포인터 커밋들

---

## 6. 도구 메모 (이 세션에서 또 겪음)

- **`codex exec` 가 조용히 죽는다** — exit 0, 빈 출력. 이번에도 1회. 파일 목록이 긴
  프롬프트에서 났다. **짧게 쓰고 `-o` 로 받고 `< /dev/null`**. 두 번째 시도는 성공.
- **커밋 게이트가 남의 빨간불에 걸린다** — `store-backup-coverage` 가 **사전에** 깨져
  있어 내 커밋이 막혔다. `SKIP_VERIFY` 대신 그 결함을 고쳤고, 고치니 **기준선 네 개가
  전부 낡아 있던 것**이 연쇄로 드러났다(재생성 스크립트가 `scripts/regen-*.sh` 에 있다).
- **`git add X && git commit` 은 훅이 거부한다** — add 를 먼저 따로.
- 운영 마이그레이션은 **`sed 's/^COMMIT;$/ROLLBACK;/'` 으로 먼저 돌려 본다.** 이번에
  실제 행 수와 검증 결과를 COMMIT 전에 전부 봤다.
