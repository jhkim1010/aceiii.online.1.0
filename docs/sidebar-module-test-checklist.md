# 사이드바 모듈 연동 테스트 체크리스트

작성일: 2026-08-11  
대상: `ventago-app` + `api-ventago`

## 목적

사이드바에서 시작한 업무가 페이지, 권한, 하위 탭, API, PostgreSQL 테넌트 경계를 지나 완료될 때까지 끊기지 않는지 반복 검증한다. 단순 렌더링 성공이 아니라 정상·경계·실패·재시도 상황을 모두 검사한다.

## 자동 실행 명령

```bash
npm run test:modules --workspace=ventago-app
npm test --workspace=ventago-app -- --runInBand
npm run test:tenant --workspace=api-ventago -- --runInBand
npm run build:app
npm run build:api
```

## 공통 모듈 체크리스트

각 사이드바 진입점마다 아래 항목을 동일하게 적용한다.

- [ ] 메뉴가 허용된 역할·앱·모듈에서만 표시된다.
- [ ] 메뉴 클릭과 URL 직접 접근의 권한 결과가 같다.
- [ ] 권한 없음은 빈 화면이 아니라 `/unauthorized` 또는 명시적 안내로 끝난다.
- [ ] 새로고침과 딥링크 접근 후 같은 화면·필터·탭이 복원된다.
- [ ] 잘못된 `tab`, `slug`, `id`, `page`는 안전한 기본값 또는 404로 정규화된다.
- [ ] 선택 지점 변경 후 이전 지점의 캐시·목록·합계가 남지 않는다.
- [ ] 다른 매장의 ID를 넣으면 403/404 또는 0건이며 데이터가 섞이지 않는다.
- [ ] 로딩·빈 결과·부분 실패·네트워크 실패·401·403·409·500 상태가 구분된다.
- [ ] 더블클릭·재시도·브라우저 뒤로가기에도 중복 생성·중복 결제가 없다.
- [ ] 목록은 pageSize 상한을 지키고 검색·정렬·페이지 이동 결과가 일관된다.
- [ ] 독립 요청은 병렬 처리되고 트랜잭션 안에서 외부 I/O를 기다리지 않는다.
- [ ] 주요 사이드바 클릭부터 렌더 완료까지 P95 300ms 목표를 측정한다.

## 역할별 메뉴 계약

| 역할 | 반드시 보이는 흐름 | 반드시 숨겨지는 흐름 |
|---|---|---|
| superadmin | Admin 운영 메뉴, Configuración | 매장 POS·재고 운영 메뉴 |
| admin/gerente | 권한이 부여된 전체 매장 앱 | 미구독 앱·미허용 기능 |
| vendedor | Nueva venta, Ventas, 허용 보조 도구 | Talleres, Materia Prima, 감독자 전용 Facturación |
| envio_manager 단독 | Ventas Online, Manuales | 나머지 전체 업무 앱 |

## 모듈별 핵심 시나리오

### Admin / Sucursales / Usuarios

- [ ] 지점 생성 시 기본 Box와 Terminal이 함께 생성된다.
- [ ] 타 매장 branch/box/terminal ID를 수정·삭제할 수 없다.
- [ ] 사용자 역할 변경 후 사이드바와 API 권한이 동시에 갱신된다.
- [ ] 마지막 관리자 제거·권한 공백 같은 위험한 변경을 차단한다.
- [ ] 프린터 API key 재발급 후 이전 key가 즉시 무효화된다.

### Tesorería

- [ ] `/caja`, `/control-de-caja`, `/cheques` 권한에 따라 탭이 정확히 노출된다.
- [ ] 허용 탭 0개에서 빈 화면이 나오지 않는다.
- [ ] Caja 개장·마감·재개·중복 요청의 멱등성을 확인한다.
- [ ] MercadoPago 잔액 조회 실패가 전체 Caja 화면을 막지 않는다.
- [ ] Cheque 상태 전이가 허용된 순서만 따른다.

### Nueva venta / Historial / Ventas Online

- [ ] 지점·Box·Terminal 미선택 시 판매 확정을 차단한다.
- [ ] 현금·MP·복합·외상·무료 판매의 합계와 상태가 일치한다.
- [ ] 동일 idempotency key 재시도는 판매 1건만 만든다.
- [ ] 타 매장 product/client/seller/branch ID를 판매에 사용할 수 없다.
- [ ] 보류 판매 생성·수정·판매 전환·삭제가 재고 원장과 원자적으로 움직인다.
- [ ] 온라인 주문의 중복 수락·취소·결제 콜백을 멱등 처리한다.

### Productos / Precios / Stock

- [ ] CodigoMadre와 variant의 부모·자식 소속이 같은 매장인지 검증한다.
- [ ] 색·사이즈 추가·삭제·복원과 지점별 재고가 일관된다.
- [ ] 재고는 leaf ProductBranch에만 기록된다.
- [ ] 가격 일괄 변경이 타 매장 product/priceType을 건드리지 않는다.
- [ ] 대량 편집 시 쿼리 수가 제품×가격×지점으로 폭증하지 않는다.
- [ ] 재고 조정·이동·판매·예약이 각 보고서 지표에 한 번만 반영된다.

### Reportes

- [ ] registry의 모든 slug가 렌더되고 permissionSlug가 서버 FunctionGuard와 대응한다.
- [ ] 잘못된 slug는 기본 보고서 또는 명시적 404로 이동한다.
- [ ] 지점·날짜·검색·카테고리 필터가 화면·Excel·PDF에서 동일하다.
- [ ] 통합 보기와 지점 보기의 합계 항등식이 성립한다.
- [ ] 타 매장 storeId/branchId query를 덮어쓰거나 403으로 차단한다.
- [ ] 2,000/20,000행 상한에서 조용한 절단 없이 경고한다.

### Talleres

- [ ] `overview`, `etapas`, `cost-sheet`, `lotes`, `cut-ticket`, `talleres`, `envios`, `pipeline`, `reworks`, `liquidaciones`가 모두 렌더된다.
- [ ] 잘못된 tab query는 `overview`로 복구된다.
- [ ] 메뉴에서 차단된 역할은 `/talleres` 직접 접근도 차단된다.
- [ ] BOM -> Lote -> Cut Ticket -> Envío -> Recepción -> Liquidación 순서의 선행조건을 검사한다.
- [ ] Cut Ticket 발급 시 BOM·공정 snapshot과 자재 차감이 하나의 트랜잭션으로 커밋된다.
- [ ] 부분 입고·불량·재작업·정산이 중복 계상되지 않는다.

### Materia Prima

- [ ] 공급자·자재·이동·지급이 동일 storeId 경계 안에서만 연결된다.
- [ ] 부족 재고에서 Cut Ticket 자재 차감을 차단한다.
- [ ] 동시 차감 시 음수 재고와 교착이 발생하지 않는다.
- [ ] 지급 배분 합계가 이동 미지급 잔액과 일치한다.

### Configuración / Herramientas / Manuales

- [ ] 허용된 설정 탭만 표시되고 잘못된 query는 첫 허용 탭으로 복구된다.
- [ ] OAuth·MercadoPago·WhatsApp 설정 실패가 명확히 표시된다.
- [ ] 다운로드 링크가 실제 릴리스 파일 또는 명시적 준비중 상태를 가진다.
- [ ] Manuales는 제한된 역할에서도 접근 가능하며 깨진 문서 링크가 없다.

## 현재 자동화된 계약

- 레지스트리의 direct/default/injected 경로가 실제 Next 페이지로 존재
- 핵심 사이드바 진입점 존재
- vendedor의 Talleres/Materia Prima 차단 정책
- directPath/defaultPath 모호성 금지
- Reportes slug 유일성, body component와 permissionSlug 완전성
- Talleres 탭 유일성, 탭별 안내 완전성, BOM 선행 순서
- Tesorería의 Caja/Control/Cheques 권한 매핑

## 자동화 대기 항목

아래 항목은 현재 알려진 단절이며 테스트를 `todo`로 등록했다.

- [ ] Talleres의 잘못된 tab query를 `overview`로 정규화
- [ ] Talleres 직접 URL에 앱/기능 권한 적용
- [ ] Tesorería 허용 탭 0개 상태를 `/unauthorized` 또는 안내 화면으로 처리

## 다음 구현 순서

1. 위 3개 `todo`에 필요한 production fix를 적용하고 테스트를 활성화한다.
2. 대표 역할별 navigation snapshot fixture를 추가한다.
3. Playwright로 sidebar click -> page heading -> 대표 GET 성공 smoke를 추가한다.
4. 테스트 DB fixture로 각 쓰기 흐름의 cross-tenant·rollback·idempotency를 추가한다.
5. route timing과 API duration을 수집해 P95 300ms 회귀 게이트를 추가한다.
