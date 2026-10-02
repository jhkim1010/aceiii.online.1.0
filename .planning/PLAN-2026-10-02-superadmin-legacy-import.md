# superadmin 이 매장 대신 Legacy importación 실행 — 계획 (2026-10-02)

## 요청
superadmin 이 각 매장의 레거시 임포트(1단계 + 2단계 「Pasar a la tienda」)를 **대신** 실행.

## 현재 (코드 근거)
- 대상 매장 = **로그인한 사람의 `user.storeId`** — 엔드포인트 **11개** 전부.
  - `legacy-import.controller.ts`: `POST preview` · `POST upload` · `GET history`
  - `partial-upload.controller.ts`: `POST plan` · `POST sesiones` · `GET sesiones/:id` ·
    `POST sesiones/:id/archivo` · `GET sesiones/:id/sucursales` · `POST sesiones/:id/importar` ·
    `GET sesiones/:id/ejecuciones` · `DELETE sesiones/:id`
- superadmin 은 `storeId = NULL` → 지금 누르면 `store_id NOT NULL` 제약에 걸려 **실패**
  (운영 실측: 대상 테이블 전부 NOT NULL — 새지는 않는다).

## 제안
### api
1. **단일 해석 함수** `tiendaDestino(user, tiendaIdPedido)` — 11개 엔드포인트가 전부 이것만 쓴다.
   - superadmin → `tiendaId` **필수**. 없으면 400(「Elegí la tienda」). 매장이 존재하는지 확인. **폴백 없음.**
   - 그 외 → 항상 `user.storeId`. `tiendaId` 를 보내도 **자기 매장과 다르면 403**(무시하지 않는다 — 조용히
     무시하면 화면 버그가 자기 매장에 쓰기를 숨긴다).
2. 세션·실행 조회(`sesiones/:id`)는 지금처럼 **세션의 store_id = 해석된 매장** 일 때만.
3. 감사: 「superadmin X 가 매장 Y 에 임포트」 를 `legacy_imports`/`legacy_import_runs` 의 `user_id` 로 이미 남김 +
   서버 로그 한 줄(`[legacy] actuando por tienda=Y superadmin=X`).
4. 시험: 11개 핸들러가 **전부** `tiendaDestino` 를 거치는지 세는 spec(하나 빠지면 실패) ·
   superadmin 무 tiendaId → 400 · 비-superadmin 이 남의 tiendaId → 403 · 돌연변이 확인.

### app (superadmin 화면)
- **Tiendas › 매장 상세** 에 탭/카드 「Importación legacy」 추가 → 기존 `ImportLegacyView` 를 `tiendaId`
  prop 으로 재사용(모든 호출에 `?tiendaId=` 를 붙임). 상단에 **대상 매장 배너**(이름 · @apodo · CUIT · id)
  고정 — 「지금 누구 매장에 넣고 있나」 가 화면 어디서든 보이게.
- 1단계 「Importar a mi tienda」 버튼 문구 → superadmin 이면 「Importar a **Shaple**」.
- 실행 직전 확인: 매장 이름을 한 번 더 보여 주는 확인창(2단계 각 묶음 실행도 동일).

## 범위 밖
- 매장 쪽(admin) 화면 동작 변경 없음. 「매장이 준 코드로 agent 가 대신」 방식(접근권)은 쓰지 않는다 —
  superadmin 은 이미 전 매장 권한자라 접근권을 거치면 마찰만 는다.

## 위험
- **테넌트 격리** — 대상 매장을 잘못 고르면 남의 매장에 데이터가 들어간다. 그래서 (a) 해석 함수 1개,
  (b) 배너 + 확인창에 매장 이름, (c) 비-superadmin 경로는 지금과 100% 동일.
- 업로드 파일 크기·시간은 지금과 같음(65MB 한 방 / 그 이상 나눠 올리기).

## 규모 · 순서
- 규모 **M** (api 2 컨트롤러 + 헬퍼 + spec / app 1 화면 + prop 배선)
- 배포: **api 먼저** — 옛 화면은 `tiendaId` 를 안 보내므로 매장 admin 동작은 그대로. 그다음 app.
