# SPEC: 신규 고객 등록 → Crédito 즉시 활성화

생성일: 2026-05-02
작성자: Claude (GSD)
관련 이슈: PaymentSummaryModal에서 신규 등록 직후 고객의 Crédito/Favor 옵션이 노출되지 않음

---

## 목표

POS에서 새 고객을 등록하는 즉시:
1. 프론트의 `selectedClient`가 등록된 고객으로 자동 채워지도록 한다 (다시 클릭 불필요)
2. 백엔드 POST `/clients`가 `clients` + `store_clients`를 한 트랜잭션으로 생성하고 응답에 `storeClientId`를 포함한다 — DNI/CUIT가 valid한 경우에만
3. 그 결과 PaymentSummaryModal에서 Crédito 옵션이 즉시 활성화된다 (creditStatus='active' default)

## 배경 및 컨텍스트

### 현재 흐름
1. 사용자 InfoClient 폼 작성 → `handleSubmit`이 `apiConnector.post('/clients', ...)` 호출
2. **응답을 그대로 버리고** `onClientCreated()` (= `setRefreshClients`) 만 호출
3. 사용자는 ClientList에서 방금 만든 고객을 다시 검색·클릭해야 `setSelectedClient` 호출됨
4. 그래도 `clients` row에는 `storeClientId` 가 없음 — `storeClientId`는 `store_clients` 테이블에 존재
5. 결과: PaymentSummaryModal `storeClientId == null` → "Para usar Crédito, seleccionar cliente" 안내 + Crédito/Favor 숨김

### 현재 분리된 두 모델
- `Clients` (`clients` 테이블): 매장 스코프 레거시 고객. 빠른 등록 가능. document 값이 `S{storeId}-NNNNN` 같은 임시 일련번호일 수 있음
- `GlobalClient` (`global_clients`) + `StoreClient` (`store_clients`): Phase 25 도입. ownerGroup 단위 식별, 매장별 신용/seña/favor 잔액 관리. `storeClientId`는 `store_clients.id`

### Phase 25 promote 흐름이 한 일
- `clients` → `global_clients` + `store_clients` 승격 (DNI/CUIT validate 통과 시)
- 결과: 같은 ownerGroupId에 동일 document 충돌 시 merge_required 반환

### 메모리 제약 (반드시 지킴)
- `feedback_ventago_global_clients_doc_required.md`: **valid CUIT/DNI 없으면 global/store_clients 기록 금지**
- 임시 document(`S{storeId}-NNNNN`) 패턴은 **store_clients 자동 생성 대상 아님**

### 운영 환경
- 운영 PG10 (호스트 OS), dev PG15 Docker
- API: NestJS, Sequelize `underscored: true` (DB는 snake_case)
- Pool: max=50 (CLAUDE.md 규약, 변경 금지)
- 모든 트랜잭션은 `sequelize.transaction()` + try/rollback 패턴

## 기술 스택

- 언어/프레임워크: NestJS 11, Next.js 13, TypeScript
- DB: PostgreSQL (운영 PG10), Sequelize + sequelize-typescript
- ESLint: api-ventago, ventago-app 각각 (Warning 0 이어야 빌드 통과)
- 프론트 상태: Context (SaleProductsContext), SWR (`useCreditClientSummary`)

## 영향 받는 파일

### 백엔드 (api-ventago)
- `src/app/clients/clients.service.ts` — `create()` 메서드 트랜잭션 확장
- `src/app/clients/clients.controller.ts` — `createClient()`에서 `user.ownerGroupId` 전달
- (참조) `src/app/shared/store-clients/store-clients.model.ts` — 변경 없음
- (참조) `src/app/client-import/validators/cuit.validator.ts`, `dni.validator.ts` — 변경 없음

### 프론트 (ventago-app)
- `src/views/homes/components/InfoClient.tsx` — `handleSubmit` 응답 활용 + `setSelectedClient`

### 운영 배포
- 코드 배포만으로 끝남. 마이그레이션 SQL 불필요 (테이블 구조 변경 없음).

## 태스크 목록

- [ ] **TASK-1**: `ClientsService.create()` 시그니처 확장 — `ownerGroupId?` 옵션 파라미터 추가, document validate (DNI/CUIT) 통과 시 트랜잭션 내에서 `clients` + `global_clients` + `store_clients` 생성
- [ ] **TASK-2**: `ClientsService.create()` 응답 형태 변경 — 항상 `Clients` 객체 + 추가 필드 `storeClientId?: number | null`, `globalClientId?: number | null` 포함하는 plain 객체 반환
- [ ] **TASK-3**: `ClientsController.createClient()` 에서 `user.ownerGroupId` 추출 후 `service.create()`에 전달
- [ ] **TASK-4**: 동일 ownerGroup에 동일 document `global_clients` 이미 존재 시 처리 — `clients`만 생성하고 `storeClientId=null` 반환 (즉시 promote는 하지 않음. 향후 promote 흐름으로 처리)
- [ ] **TASK-5**: 프론트 `InfoClient.handleSubmit()` — POST 응답을 받아 `setSelectedClient(response)` 즉시 호출. PUT 흐름도 응답으로 갱신
- [ ] **TASK-6**: ESLint 검증 — api-ventago + ventago-app 각각 lint 통과 (warning 신규 발생 0)
- [ ] **TASK-7**: 로컬 dev PG에서 동작 검증 — POST /clients (valid CUIT) → 응답에 storeClientId 포함, store_clients 행 생성 확인
- [ ] **TASK-8**: 로컬 dev PG에서 검증 2 — POST /clients (임시 document `S9-00001`) → 응답에 storeClientId=null, store_clients 행 미생성 확인 (메모리 규칙 준수)
- [ ] **TASK-9**: 프론트 시나리오 검증 — 신규 등록 valid DNI 고객 → PaymentSummaryModal에 Crédito 옵션 즉시 노출
- [ ] **TASK-10**: 운영 배포는 별도 — 사용자 승인 후 push-both.sh

## 완료 기준

- ESLint 오류 0개 (warning 신규 발생도 0)
- 로컬 dev에서 valid DNI/CUIT 신규 고객 등록 시:
  - `clients` 1행, `global_clients` 1행, `store_clients` 1행 생성
  - 응답 JSON에 `storeClientId` 포함 (number)
  - 프론트 PaymentSummaryModal 즉시 Crédito 옵션 노출
- 임시 document(`S{storeId}-NNNNN`) 신규 고객 등록 시:
  - `clients` 1행만 생성 (`global_clients`/`store_clients` 미생성)
  - 응답 JSON `storeClientId: null`
- 같은 ownerGroup에 동일 valid document 이미 있는 경우:
  - 트랜잭션 안전 종료 — `clients`도 생성하지 않고 BadRequestException (현재 동작 유지)
- 운영 PostgreSQL pool 영향 없음 (트랜잭션 1회당 1 connection 사용 후 release)

## 금지사항 / 주의사항

### DB 제약
- ❌ `clients`만 INSERT 후 `store_clients` INSERT 실패 시 데이터 불일치 — 반드시 단일 트랜잭션
- ❌ valid 검증 실패한 임시 document로 `global_clients` INSERT 금지 (메모리 규칙)
- ❌ 운영 PG10 호환성 — `EXECUTE FUNCTION`, `GENERATED AS IDENTITY` 등 PG11+ 문법 금지 (이번엔 마이그레이션 없으므로 무관)

### Pool 안전성
- ✅ `sequelize.transaction()` 사용 시 try/catch로 commit 또는 rollback 보장
- ❌ 트랜잭션 내부에 외부 API 호출, 긴 동기 작업 금지 — connection 점유 시간 최소화
- ✅ Sequelize 자체가 transaction 종료 시 connection 자동 release하므로 별도 release 호출 불필요

### Frontend
- ❌ `setSelectedClient(formData)` — 폼 데이터를 직접 넣지 말 것 (id 없음). 항상 백엔드 응답 사용
- ✅ PUT 응답도 동일하게 setSelectedClient로 갱신 (기존 selectedClient.id 유지하되 다른 필드는 응답으로 덮어쓰기)
- ✅ 응답이 없거나 비정상이면 setSelectedClient 호출 생략 (기존 동작 유지)

### 회귀 위험 영역
- `client-import` 모듈의 일괄 등록 흐름은 `ClientsService.create()` 를 호출하지 않을 가능성 있음 — 영향 범위 확인 필요
- `temp-client` 흐름은 `createTempClient()` 별도 메서드 사용하므로 영향 없음
- `promote()` 흐름은 그대로 유지 (이미 `clients`가 있는 row를 승격하는 별도 흐름)

## 회귀 테스트 시나리오

| # | 시나리오 | 기대 결과 |
|---|---|---|
| R1 | valid DNI(7-8자리) 신규 등록 | clients+global_clients+store_clients 모두 생성, storeClientId 응답 |
| R2 | valid CUIT(11자리 mod11) 신규 등록 | 동일 |
| R3 | 임시 document `S9-00001` 신규 등록 | clients만 생성, storeClientId=null |
| R4 | 동일 store에 같은 document 재등록 시도 | BadRequestException (기존 동작) |
| R5 | 다른 store에 같은 document 등록 | clients 생성 OK, global_clients 신규 (다른 ownerGroup일 때) 또는 conflict 처리 |
| R6 | client-import 일괄 등록 흐름 | 기존 동작 유지 (별도 메서드 사용 추정) |
| R7 | PUT /clients/:id (수정) | 응답으로 selectedClient 갱신, storeClientId 변경 없음 |

## 후속 작업 (out-of-scope, 별도 PR)

- 기존 `clients` 중 valid document 가지고 `store_clients` 없는 row 일괄 백필 스크립트
- 결제수단 중복 표시 문제 (별도 SPEC)
- 임시 document 고객이 추후 valid CUIT 발견 시 자동 promote 트리거

---

## 부록: 핵심 코드 변경 미리보기

### 백엔드 ClientsService.create() (의사 코드)

```typescript
async create(
  data: Partial<Clients>,
  ownerGroupId?: number,  // 신규 추가
): Promise<Clients & { storeClientId: number | null; globalClientId: number | null }> {
  // 0. 매장 내 동일 document 중복 체크 (기존)
  const existing = await this.clientsModel.findOne({
    where: { document: data.document, storeId: data.storeId },
  });
  if (existing) throw new BadRequestException('Ya existe un cliente con este documento en esta tienda');

  // 1. document validate
  const doc = normalizeCuit(data.document ?? '');
  const isValidDoc = doc && (isValidDni(doc) || isValidCuit(doc));

  // 2. 단순 흐름 (임시 document or ownerGroupId 없음): 기존대로 clients만
  if (!isValidDoc || !ownerGroupId) {
    const created = await this.clientsModel.create(data);
    const json = created.toJSON();
    return { ...json, storeClientId: null, globalClientId: null } as any;
  }

  // 3. valid document + ownerGroupId 있음: 트랜잭션으로 3개 테이블 생성
  const transaction = await this.sequelize.transaction();
  try {
    // 3-1. clients 생성
    const localClient = await this.clientsModel.create(data, { transaction });

    // 3-2. global_clients 동일 ownerGroup 충돌 체크
    const existingGlobal = await this.globalClientModel.findOne({
      where: { ownerGroupId, document: doc },
      transaction,
    });

    if (existingGlobal) {
      // 충돌 시 store_clients만 매핑 (있으면 재사용, 없으면 신규)
      const [sc] = await this.storeClientModel.findOrCreate({
        where: { globalClientId: existingGlobal.id, storeId: data.storeId },
        defaults: { isActive: true },
        transaction,
      });
      await transaction.commit();
      const json = localClient.toJSON();
      return { ...json, storeClientId: sc.id, globalClientId: existingGlobal.id } as any;
    }

    // 3-3. global_clients + store_clients 생성
    const gc = await this.globalClientModel.create({
      ownerGroupId,
      document: doc,
      fullname: data.fullname,
      nameFantasy: (data as any).nameFantasy,
      email: data.email,
      phone: data.phone,
      address: data.address,
      location: (data as any).location,
      provinceId: (data as any).provinceId,
      transport: (data as any).transport,
      resIva: (data as any).resIva,
      createdByStoreId: data.storeId,
      isActive: true,
    } as any, { transaction });

    const sc = await this.storeClientModel.create({
      globalClientId: gc.id,
      storeId: data.storeId,
      isActive: true,
    } as any, { transaction });

    await transaction.commit();
    const json = localClient.toJSON();
    return { ...json, storeClientId: sc.id, globalClientId: gc.id } as any;

  } catch (err) {
    await transaction.rollback();
    throw err;
  }
}
```

### 백엔드 Controller (의사 코드)

```typescript
async createClient(@Body() data: CreateClientsDto, @GetUser() user: any) {
  const clientData = { ...data, storeId: user.storeId };
  return this.clientsService.create(clientData, user.ownerGroupId);
}
```

### 프론트 InfoClient.handleSubmit() (의사 코드)

```typescript
if (selectedClient) {
  const updated: any = await apiConnector.put(`/clients/${selectedClient.id}`, clientPayload);
  if (updated && (updated.id || updated?.data?.id)) {
    setSelectedClient(updated.data ?? updated);
  }
  toast.success('Cliente modificado exitosamente');
} else {
  const created: any = await apiConnector.post('/clients', { ...clientPayload, storeId: user?.storeId });
  if (created && (created.id || created?.data?.id)) {
    setSelectedClient(created.data ?? created);  // storeClientId 포함된 응답 반영
  }
  toast.success('Cliente creado exitosamente');
}
onClientCreated();
```
