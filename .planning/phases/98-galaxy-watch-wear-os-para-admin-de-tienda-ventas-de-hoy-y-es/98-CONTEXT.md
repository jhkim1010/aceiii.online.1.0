# Phase 98 — CONTEXT (결정 확정 2026-10-04)

설계 근거·현재 상태·API 형태·웨이브는 `98-PROPUESTA.md`, 화면은 `98-mockup.png`. 이 파일은 **확정된 결정**만.

## Decisions (LOCKED)

- **D-01 플랫폼**: Galaxy Watch = Wear OS 전용. Apple Watch 범위 밖.
- **D-02 방식**: 워치 전용 앱(B). Kotlin + Jetpack Compose for Wear OS, 모노레포 신규 `wear-admin-app/`.
  applicationId = 휴대폰 앱과 동일 `com.coolsistema.tienda_admin_app`.
- **D-03 정보**: 오늘 매출(매장 타임존·지점별·티켓 수·어제 같은 시각 대비) + 카하 현황(서랍 단위·열림/닫힘·잔액·담당자·지난 날 미마감). **읽기 전용.**
- **D-04 배포**: **Google Play** (내부 테스트 트랙으로 시작). Play 개발자 계정·서명키 준비는 사용자 작업 — W5 체크포인트.
- **D-05 대상**: **매장 admin 만**(gerente·기타 역할 제외). 매 요청 시 현재 역할로 재판정 — admin 이 아니게 되면 즉시 401.
- **D-06 연결**: **코드 페어링** — 워치가 코드 표시 → admin 이 **휴대폰 앱(tienda-admin-app) 「Relojes」** 에서 입력. 웹 화면은 이번 범위 밖.
  워치 토큰은 `GET /watch/resumen` 전용(다른 라우트 401), 90일 sliding · 30일 유휴 · 회수 가능, 헤더로만 전달.
- **D-07 금액 표시**: **축약(M)** — 워치 앱·Tile·컴플리케이션 모두. 예: `$1,28 M`, 백만 미만은 `$842 K`, 천 미만은 그대로.
  (es-AR 소수점 콤마.)

- **D-08 화면 = 목업 v2** (2026-10-04 사용자 확정, `98-mockup-v2.html/.png`): D-03 을 **확장**한다.
  섹션(세로, 베젤/세로 스와이프로 이동): ① Hoy(매출 총액·판매 건수·벌수·마지막 판매 시각·어제 대비) · ② Medios de pago(현금·은행·외상·Favor, 비율 링) ·
  ③ Gastos·Descuentos(건수·금액) · ④ Ingresos(입고 건수·벌수) · ⑤ Facturación del **mes**(Tipo A/B·IVA — 오늘이 아니라 이번 달, 제목에 월 표기) · ⑥ Cajas(**유지**, 사용자 확정).
  기준 화면은 사용자가 보낸 대시보드 캡처(Estadísticas de Ventas/Gastos/Descuentos/Ingresos/FVentas del Mes). **계산 원천은 아직 미확인** —
  ventago-app·api-ventago·tienda-admin-app 에서 해당 라벨이 검색되지 않는다(`/dashboards/sales/summary` 는 필드가 다르다). 재계획 전에 원천을 찾아 **같은 계산**을 쓴다(웹과 숫자가 갈라지면 안 된다).
- **D-09 지점 여러 개**: 기본 「Todas」 = 매장 합계 + 지점별 내역(금액 내림차순). 제목 「TODAS ▾」 탭 → 지점 선택(워치가 기억). 선택은 모든 섹션·Tile·컴플리케이션에 적용되고 제목에 항상 지점명.
  카하는 지점 이름 아래 묶고 소계.
- **D-10 조작**: 베젤/↑ 다음 섹션 · ↓ 이전 섹션, 「Hoy」 맨 위에서 ↓ = 새로고침 · →(왼→오) = 시스템 뒤로 · 아래 버튼(Back) = 섹션에서는 「Hoy」로, 「Hoy」에서는 종료 ·
  위 버튼은 시스템 전용 — 사용자가 워치 설정에서 「두 번 누르기 → Ventago Admin」을 지정하도록 휴대폰 Relojes 화면에 안내 1줄. 앱 열 때마다 즉시 갱신.
  (`KEYCODE_STEM_*` 가 Galaxy Watch 에서 앱에 오는지는 미확인 — 98-07 실기기에서 확인.)
- **D-11 워치 수**: 매장당 개수 제한 없음. 각 admin 은 자기가 연결한 워치만 보고 회수(현 설계 유지, 사용자 확인).

- **D-12 지표 정의** (2026-10-04 사용자 확정): 기준 화면은 **레거시** 「Resumen del día」(`~/TrabajoProgramming/flutter_aguila` lib/screens/resumen_del_dia_*.dart) — Ventago 에는 같은 계산이 없으므로 Ventago 데이터로 새로 계산한다.
  ① Favor 는 Crédito 와 **따로** 표시 · ② Descuentos 는 **판매 건 기준**(할인이 있는 판매 수 + 할인 합계) ·
  ③ Ingresos 는 **매입 + 공방 수령만**(재고 조정·지점 간 이동 제외) · ④ Facturación 은 **NC 를 뺀 순액**(이번 달, CAE 있는 전표, 종류별 + IVA).
  나머지 정의(판매 건수·합계·벌수·마지막 판매·결제수단·지출)는 레거시 계산 추적 결과를 따른다 — 재계획 시 레거시 SQL 과 대조.

- **D-13 워치 기록 삭제 정책** (2026-10-04 사용자 확정): `watch_devices`·`watch_pairing_codes` 의 users/stores FK `ON DELETE CASCADE` **유지**.
  매장 완전 삭제 시 그 매장 데이터를 남기지 않는 방향과 일치. 감사 이력 보존은 범위 밖(CODEX P2 지적을 의식적으로 수용).
- **D-14 민감 정보 노출** (2026-10-04 사용자 확정, CODEX 자문 반영) = 옵션 (다):
  ① 워치 Cajas 화면에 **담당자 이름을 싣지 않는다** — 서랍 이름·열림/닫힘·금액만. API 응답에서도 `usuario` 필드를 빼서 토큰 유출 시에도 나가지 않게 한다.
  ② **잠금 상태(ambient/잠금화면)의 컴플리케이션·Tile 에서는 금액을 숨긴다** — 예: 「•••」/건수만. 잠금 해제(활성) 상태에서만 금액 표시.
  ③ 응답 `Cache-Control: no-store`, 토큰·응답 본문 로그 금지, 워치 로컬 캐시는 마지막 값 1개만(오프라인 표시용).

- **D-15 지표 경계·표시 세부** (2026-10-04 사용자 확정, plan-checker 2차 지적 대응):
  ① **Favor 칸** = 오늘 판매에 **자동 상계된 favor**(`credit_ledger` 의 `favor_apply`, `sale_id` 기준 — 외상 판매 시 그 판매의 sale_credit 에 붙는 상계분)
     + **명시 favor 결제행**(slug favor/saldo-a-favor). 그 자동 상계 금액은 **Crédito 칸에서 뺀다**(레거시 'Ventas Favor' 의미).
     다섯 칸의 합은 여전히 그날 결제행 합과 같다. [사용자 선택]
  ② **「Ventas hoy」 = 판매 시점 합계**(레거시와 같음; 결제수단 칸 합 = 총액). 웹 VentaVista 「Venta Total」과는 `creditCashAdjustment` 만큼
     다를 수 있다 — **의도된 차이**. [사용자 선택]
  ③ 외부 전표(`afip_comprobantes_externos`)는 **Facturación del mes 에 넣지 않는다.** [사용자 선택]
  ④ 입고 건수 = 그날 입고된 **모델(코드 마드레) 수.** [사용자 선택]
  ⑤ 기본값 수용(사용자 이의 없음): 매입 = **수동 재고 입고**(자체 생산 OT 제외) · `devuelto` 반품은 판매 합계에서 제외(웹과 동일) ·
     전날 판매의 당일 취소는 **오늘 −1건**(웹 규약).
  ⑥ **지점이 1개인 매장**: 제목 「VENTAS HOY · {tienda}」, 지점 선택(▾) **숨김**(목업 ①). 판정 = 응답 `sucursales`(활성 지점) 길이 ≤ 1.
  ⑦ D-14 ② 확정 해석: ambient/잠금에서 금액을 가릴 플랫폼 수단이 없으면 **원형 컴플리케이션 SHORT_TEXT 의 기본값은 건수(또는 •••)** —
     금액 노출은 **사용자가 나중에 명시적으로 허용할 때만**. 이번 phase 는 원형에 금액을 싣지 않는다(허용 스위치도 만들지 않는다 — 허용은 새 결정으로).

## Claude's discretion

- 새 테이블 이름/컬럼, 코드 길이·만료(제안: 8자 · 5분), rate limit 수치, 캐시 TTL(제안 30초).
- Tile 갱신 주기(시스템 최소 15분 근처), 오프라인 표시 문구.

## Deferred

- 푸시 알림(FCM) · Apple Watch · 웹 페어링 화면 · 기존 `/dashboards/sales/summary` 의 UTC 「오늘」 버그(별건).
