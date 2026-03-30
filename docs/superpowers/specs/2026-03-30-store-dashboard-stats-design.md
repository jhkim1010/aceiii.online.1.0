# Tienda 목록 - 매장별 실시간 통계 표시

## 목적

Superadmin이 Tienda 목록 페이지에서 각 매장의 운영 현황을 한눈에 파악할 수 있도록 한다.
현재는 이름/주소/앱/상태만 보이므로, 판매 건수·마지막 판매·활성 터미널·로그인 현황을 추가한다.

## 백엔드

### 새 엔드포인트: `GET /store/dashboard-stats`

- **위치**: `api-ventago/src/app/store/store.controller.ts` + `store.service.ts`
- **권한**: superadmin 전용 (`@Auth(ValidRoles.superadmin)`)
- **쿼리 파라미터**: `period` — `today` (기본) | `week` | `month`

### 응답 형태

```json
[
  {
    "storeId": 1,
    "salesCount": 15,
    "lastSaleAt": "2026-03-30T14:32:00Z",
    "activeTerminals": 3,
    "lastLoginAt": "2026-03-30T09:15:00Z",
    "hasLoginToday": true
  }
]
```

### SQL 쿼리 전략

하나의 Sequelize raw query 또는 3개의 집계 쿼리를 병렬 실행:

1. **판매 통계** — `Sale` 테이블에서 `storeId`별 GROUP BY
   - `COUNT(*)` as salesCount
   - `MAX(saleDate)` as lastSaleAt
   - WHERE: `saleDate >= :periodStart` AND `status NOT IN ('Anulado', 'Anulación')`

2. **활성 터미널** — `CashRegister` 테이블에서 `storeId`별
   - `COUNT(DISTINCT terminalId)` where `closingTime IS NULL` (현재 열려있는 caja)

3. **로그인 현황** — `Users` 테이블에서 `storeId`별
   - `MAX(lastLoginAt)` as lastLoginAt
   - `CASE WHEN MAX(lastLoginAt) >= :todayStart THEN true ELSE false END` as hasLoginToday

기간 계산은 각 매장의 `timezone` 필드를 사용하여 현지 시간 기준으로 처리한다.

## 프론트엔드

### 수정 파일

1. **`ventago-app/src/views/admin/stores/list/StoresListView.tsx`**
   - 기간 필터 칩(Hoy / Semana / Mes) 추가
   - dashboard-stats API 호출 및 상태 관리
   - 통계 데이터를 테이블 행에 매핑

2. **`ventago-app/src/views/admin/stores/list/components/DataConfig.tsx`**
   - 새 컬럼 정의 추가

### 새 테이블 컬럼

| 컬럼명 | 필드 | 표시 형식 |
|--------|------|----------|
| Ventas | salesCount | 숫자 (예: `15`) |
| Última venta | lastSaleAt | 상대 시간 (예: `hace 2h`) |
| Terminales activos | activeTerminals | 숫자/뱃지 (예: `3`) |
| Último login | lastLoginAt | `hasLoginToday ? "Hoy" : "hace 2 días"` |

### 기간 필터

테이블 상단에 MUI ToggleButtonGroup으로 Hoy / Semana / Mes 표시.
선택 시 `period` 파라미터를 변경하여 API 재호출. salesCount에만 영향.

## 검증

1. API 엔드포인트 호출하여 응답 구조 확인 (Postman 또는 curl)
2. 프론트엔드에서 기간 필터 전환 시 숫자 변경 확인
3. 터미널이 없는 매장, 판매가 없는 매장 등 edge case 확인
4. dev 서버에서 preview로 시각적 확인
