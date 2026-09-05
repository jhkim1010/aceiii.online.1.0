# 핸드오프 2026-09-05 — 비용 매퍼 · 카하 시작금액 · 전자영수증 목록 · 이중발급 가드

앞 세션은 `HANDOFF-2026-09-03-b-arca-idor-y-cajas.md`.

```
api-ventago  e4d75bf → 6772be6   (#867~#871 전부 SUCCESS · SHA 로 대조 확인)
부모 저장소   a682826 → 18bc276   (Flutter 관리자앱 — APK 는 아직 안 빌드)
```

앞 핸드오프의 「미확인 3건」은 **전부 확인 끝**: 마지막 두 커밋 SUCCESS · 인증서 감시 크론
정상 발화(`telegram=sent mail=true`) · SSH 복구(`prod-ssh` MCP 는 여전히 타임아웃).

---

## ★★★ 지금 막혀 있는 것 — 명령 한 줄이면 풀린다

**`X-Store-Id` 매장 대행이 REST 에서 안 먹는다.** superadmin 은 `users.store_id` 가
NULL 이라 그 헤더로 매장을 빌려야 하는데, 8개 서랍 전부 400 이 났다:

```
"Usuario no tiene tienda asignada"
```

권한 확인(`/afip/soap-status`)은 200 이었으니 superadmin 판정은 맞다. 그래서
**헤더가 도달하지 않았을 가능성**이 크다(nginx 가 지웠거나).

★ 진단 모드를 만들어 뒀는데 **아직 안 돌렸다.** 이것부터 하면 갈린다:

```bash
/private/tmp/.../scratchpad/regularizar-cajas.sh --diag
```
`/auth/me` 를 헤더 없이/있이 두 번 불러 `storeId` 가 바뀌는지 잰다. 카하는 안 건드린다.
둘이 같으면 nginx 문제(서버에서 바로 고칠 수 있다), 다르면 400 은 다른 이유다.

★ 관리자앱(`dio_client.dart`)은 **이미 이 헤더로 대행을 한다** — 앱에서는 동작이
검증된 경로다. 그래서 「REST 에서만 안 된다」가 단서다.

---

## ★★ 카하 16개가 미마감 — 결정은 났는데 실행을 못 했다

**사용자 결정 2026-09-05: 전부 `countedCash: 0` 으로 구간만 닫는다** (돈은 안 움직인다).

| box | 매장 | 세션 | through | 장부 잔액 |
|---|---|---|---|---|
| **15** JuanaCaja | coolsistema | 6 | 2026-08-10 | **805,900** |
| 3 Caja 1 | CART | 1 | 2026-04-28 | 16,500 |
| 13 Caja de TEST | CART | 1 | 2026-04-10 | 14,500 |
| 22 Caja 1 | Asado | 2 | 2026-06-23 | 9,000 |
| 23 Caja 1 | Lencería naty | 2 | 2026-07-24 | 100 |
| 24 · 21 · 9 | naty · mana · genius | 4 | — | 0 |

★ **오늘/어제 열린 근무는 없다** — 가장 최근이 26일 전이라 일하는 사람을 끊을 위험은 없다.
  (어제 보이던 09-04 근무 2개는 그 뒤 정상 마감됐다.)

★★ **SQL 로 닫지 말 것.** 정식 마감은 `box_settlements` 에 정산행을 만들고 차액을
  `variance`(+`review_required`)로 남기며 감사 로그에 「contado/esperado/diferencia+사유」를
  적는다. `closing_time` 만 채우면 805,900 이 장부 없이 사라진다.

실행 스크립트: `scratchpad/regularizar-cajas.sh` (로그인 프롬프트 · 권한 사전확인 ·
throttle 3초 · 부분 실패 허용 · `--dry-run` · `--diag`). **위 헤더 문제만 풀리면 바로 된다.**

---

## 배포한 것 (전부 #SUCCESS · 운영 반영)

| 커밋 | 빌드 | 내용 |
|---|---|---|
| `a26b5aa` | #867 | **비용 매퍼** gastos/gasto_info → expenses |
| `0a47f3b` | #868 | nam2 **통합 대조 시험** (한 매장에 다섯 단위) |
| `520ec0a` | #869 | **카하 시작금액 이력** + 금고 기록 금지 가드 |
| `0c44b23` | #870 | **전자영수증 목록** + `/afip/soap-status` |
| `6772be6` | #871 | **ws provider 발행자 차단** (이중발급) |

마이그레이션 `2026-09-05-phase86-legacy-caja-aperturas.sql` —
**로컬 5432 + 운영 5434 양쪽 적용, 스키마 29줄 diff 0, owner/시퀀스 coolsistema 확인.**

---

## ① 비용 매퍼 — 실측이 전제를 다섯 번 뒤집었다

**`gasto_info.codigo` 가 유일하지 않다.** PK 가 `(id_gasto, codigo)` 라서.
aleida 는 89행에 codigo 82종 → 순진한 조인이 **10,272 → 11,072 (+800 유령 비용)**.

**`hora` 에 0 패딩이 없다** (`12: 6: 6` · ` 9:33: 3`). `::time` 은 던지고, 판매 매퍼의
엄격한 정규식을 재사용했다면 **32~45% 가 자정으로 밀렸다**(nam2 796/1167).

**`expenses` 에 소프트삭제가 없다** → `borrado=true` 는 넣지 않고 **센다**.

**`nencargado` 는 사람을 못 가리킨다** — `vendedores` 와 한 건도 안 붙는다.
`user_id` 는 임포트를 실행한 관리자로 둔다.

**카테고리는 계층이다** (사용자 확인). 마지막 글자를 뺀 코드가 카탈로그에 있으면 부모,
없으면 루트 — aleida 고아 23개(`ba`~`bk`·`fa`~`fl`)는 부모 `b`·`f` 가 원본에 아예 없다.

## ② 카하 시작금액 — `legacy_caja_aperturas` (이력 전용)

ACE 의 `<db>-<fecha>-CajaN` 은 **그날 그 카하의 시작금액**이고, 그 돈은 **jefe 가
챙겨가 사업 밖으로 나간다**(사용자 확인). 마감이라는 사건 자체가 없다(nam2 CierreZ 0).

→ `cash_registers` 아님(열림/마감/정산 전제가 없다) · `caja_fuerte_operations` 아님
  (금고로 안 간다) · **이력 표에만** 담는다. nam2 421건 · 순액 78,042,653.

★ **사용자 지시: legacy import 는 caja fuerte 에 아무것도 기록하지 않는다.**
  주석이 아니라 **테스트 두 축**으로 강제했다:
  `legacy-import-sin-tesoreria.spec.ts`(소스 훑기 + 대조군 2) ·
  `nam2-completo.itest.ts` ⑧(임포트 후 그 표들이 실제로 비었는지).

## ③ nam2 통합 — 차이를 **증명**한다

```
vcodes    14,536 → sales     14,115   -421 = `-CajaN`(카하 시작금) 정확히 일치
vdetalle  47,422 → sale_items 47,403   -19 = 그 421건에 붙은 품목 정확히 일치
gastos     1,167 → expenses   1,154   -13 = borrado 정확히 일치
재고·팩투라·카테고리·카하시작금            차이 0 을 **요구**한다
```
「차이가 있을 수 있다」로 끝내면 진짜 유실이 그 핑계 뒤에 숨는다.

## ④ 전자영수증 목록 + SOAP 진단

`GET /afip/facturacion-electronica` — 발행자별 매장·PV·CUIT·운영/homo·인증서 만료·
발급 실적·`estado`·`porRenovar`. **목록의 권위는 `afip_issuers`**(인증서 디렉터리는
다른 시스템과 공유 — 110여 개 중 우리 것 2개).

`GET /afip/soap-status` — FEDummy. ★ **토큰을 안 건드린다**(인증 불필요). 이 경로가
TA 를 새로 받으면 AFIP 이 "이미 유효한 TA 가 있다"로 다음 발급을 최대 12시간 막는다.

Flutter 관리자앱: **Fac. electrónica 탭**(9번째) + **대시보드 맨 위 경보 배너**.
판정은 서버 `necesitaAtencion` 한 곳에서만 온다. **APK 는 아직 안 빌드했다.**

## ⑤ 이중발급 — 사용자가 겪은 사고를 감사했다

「다른 앱에서 SOAP 발급 중 통신이 끊겨 중복 발급」 → **우리 코드는 그 창을 이미 막고 있다.**

```
sent = true;                    ← createBill() 바로 앞
await client.createBill(body);  ← 타임아웃/절단
  → catch → recoverAmbiguous()
     2초 대기(AFIP 서버측 커밋 흡수) → FECompConsultar
     CAE 있으면 **그것을 성공으로 반환** (두 번째 발급 안 함)
     602 → 미발급 확정 재시도 안전 · 조회 실패 → ambiguous → verificar 하드 차단
```
시험 4건이 이 경로를 덮는다. **운영 중복 0건.**

방어 층: 발급률 상한(invoicePct 합>100% 거부) · **DB 원자적 클레임**(워커 4개를 넘어
동작하는 유일한 장치) · `verificar` 하드 차단 · 잔재 재클레임 시 AFIP 대조 ·
`uq_afip_vouchers_serie`.

★ **구멍이었던 것 → 오늘 막음**: `ws` provider 는 `getLastVoucher()` 가 **항상 null** 이라
「프로세스가 죽은 뒤」 대조 층이 조용히 사라진다. 발행자 저장 3경로(생성·수정·지점별
upsert) **전부**에 가드를 넣고, 소스를 훑어 **전수를 세는 검사**를 붙였다.
★ 이것은 그물을 복구하는 게 아니다 — 위험한 구성에 **모르고 들어가는 것**을 막을 뿐이다.

---

## 인프라

- **디스크 12GB 회수** (138G→126G). `docker builder prune -af` — docker 보고는 21.44GB.
  ★ 다음 Jenkins 빌드는 캐시가 없어 느리고 무겁다(Jenkins 가 운영 서버 위, swap 0).
- **41시간 멈춰 있던 rclone 종료.** Dropbox 배치 커밋 오류 후 교착(14 스레드 전부
  `futex_wait_queue`, 소켓 없음). SIGTERM 하니 부모 스크립트가 「실패」를 남기고 종료 —
  **41시간 만의 첫 줄**이었다.
- `dropbox_sync.sh` 에 **flock + timeout + EXIT trap 하트비트** 추가. 시험 3종 통과
  (정상·시간초과·잠금겹침) + 실제 rclone 종단(286초, 9/5 백업 2.2GB 실제 업로드).

---

## 남은 것

| 우선 | 항목 |
|---|---|
| ★★★ | **`--diag` 실행** → X-Store-Id 원인 규명 → 카하 16개 정리 |
| ★★ | **superadmin 대시보드 = 전 매장 파노라마** (신규 요청). 카하 **개시 여부**와 **미마감 경과일**이 둘 다 경고여야 한다 — 148일짜리가 조용히 있었다 |
| ★ | 관리자앱 **APK 빌드**(`build-apk.sh`) — 안 하면 폰에서 새 탭이 안 보인다 |
| ★ | 인증서 만료 **2026-10-20 (44일)**. 감시 정상, 갱신 절차 동작 |
| 중 | 채번 뮤텍스 → **PG advisory lock** (워커 4개 · 10016 거부 방지. 중복발급 아님) |
| 중 | `ops-daily-check` 가 `todas`·Dropbox 업로드를 **안 본다** — 41시간 침묵의 원인 |
| 중 | `dropbox_sync.sh`·`pg_backup_todas.sh` 가 **git 에 없다** (서버에만 있다) |
| 중 | legacy import **배선** — 매퍼 6개가 화면에서 안 불린다(전부 시험에서만) |
| 하 | 외상/예약(⑤ 묶음) 매퍼 미구현 · `/configuracion?tab=productos` 1741ms |
| 하 | `by-slug/ecommerce` 404 폴러(매분) — 로그를 덮는다 |
| 하 | `AfipResponseError`=「발급 안 됨」 전제는 **ARCA 매뉴얼로 확인**해야 한다 |

★ **CODEX 자문을 못 돌렸다** — 이 세션에 도구가 없었다. 상시 지시사항이다.

---

## 다음 사람이 알아야 할 함정

1. **SQL 주석 안의 백틱** — 템플릿 리터럴이 그 자리에서 닫혀 엉뚱한 줄에서 TS 오류.
   이 세션에서도 **두 번** 당했다(핸드오프에 이미 「세 번 당했다」고 적혀 있었다).
   `sql-template.spec.ts` 가 디렉터리를 훑어 잡는다.
2. **바인드는 문장마다 개수도 순서도 다르다.** 많이 주면 PG 가 거부하고, 참조 안 되는
   `$n` 은 타입 추론이 안 돼 죽는다. **세는 쿼리가 죽으면 삽입 0건이 「거부 0건」처럼 보인다.**
3. **sequelize 오류를 그대로 던지면 jest 가 힙을 터뜨린다**(4GB). SQL·바인드·커넥션을
   물고 있어서다. 짧은 Error 로 감싸야 진짜 원인이 보인다.
4. **`information_schema.tables.table_name` 은 `sql_identifier`** — `::text` 안 붙이면
   문자열 비교가 안 돼 표 13개가 전부 「없음」으로 나온다.
5. **재고 원본 지표는 `stockreal > 0`** — `<> 0` 으로 세면 음수 클램프분이 설명 없는
   차이로 보인다.
6. **`caja_fuerte_operations` 에 `branch_id` 가 없다** — 금고를 거쳐야 매장에 닿는다.
7. **로그인 응답 필드는 `accessToken`**(`token` 아님), 요청 필드는 `emailOrUsername`.
   ★ 새 로그인은 **기존 세션을 끊는다** — 스크립트로 로그인하면 앱이 튕긴다.
8. **superadmin 은 `users.store_id` 가 NULL** 이라 매장 스코프 화면·API 가 전부 빈다.
   `X-Store-Id` 가 그 통로인데 지금 REST 에서 안 먹는다(위 ★★★).
9. **컨테이너의 `wget` 은 AFIP 의 약한 DH 를 거부한다**("dh key too small"). 앱과 같은
   **Node TLS** 로 재야 실제 상태를 안다(FEDummy = AppServer/DbServer/AuthServer OK).
10. **`docker system df` 는 회수량을 과소 보고한다** — 11.66GB 라 했는데 실제 21.44GB.
