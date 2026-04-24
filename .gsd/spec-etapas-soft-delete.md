# SPEC: Etapas 비활성화 (Soft Delete) — 범위 B

생성일: 2026-04-23

## 목표

EtapasTab에서 공정(etapa)을 **안전하게 비활성화/재활성화**할 수 있도록 UI와 API를 추가한다. Hard delete는 하지 않는다 (과거 CT의 routing_path, envios FK 무결성 보존). 진행 중 envio가 있으면 경고 후 진행, 없으면 즉시 토글. 관리자는 비활성 공정도 조회·재활성화할 수 있도록 "Mostrar inactivas" 토글 제공.

## 배경 및 컨텍스트

- 파일: `ventago-app/src/views/talleres/tabs/EtapasTab.tsx`
- 현재 테이블 행에 편집(연필) 아이콘만 있고 비활성화 UI 없음
- Etapa 모델에 `isActive: boolean` 필드 이미 존재 (`defaultValue: true`)
- 백엔드는 `PUT /talleres/etapas/:id`로 `{ isActive: false }` 보내면 Soft delete 가능 (재확인됨)
- Envio 모델은 `EnvioStatus.PENDING/PARTIAL/COMPLETED/CANCELLED` 값 존재
- 프론트 toast: `react-hot-toast`, 이미 EtapasTab에서 import 중
- 현재 `findFiltered` 조회는 `isActive` 필터링 안 함 → 전체 반환 (프론트에서 토글로 제어)

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (PostgreSQL 15)
- 프론트: Next.js 13 + React 18 + MUI 5 + SWR
- DB 수정 없음 (기존 `is_active` 컬럼 재활용)
- PostgreSQL pool: 변경 없음 (기존 쿼리만 추가)

## 태스크 목록

- [x] TASK-1: 백엔드 소스 파악 완료 (etapa.controller/service, envio.model)
- [ ] TASK-2: SPEC 파일 작성 (현재 문서)
- [ ] TASK-3: 백엔드에 `GET /talleres/etapas/:id/usage` 엔드포인트 추가
  - envios에서 해당 etapaId 사용 중 + status가 PENDING 또는 PARTIAL 인 row count 반환
  - vendorEtapas count도 함께 반환 (참고용)
  - response: `{ activeEnviosCount: number, vendorEtapasCount: number }`
- [ ] TASK-4: 프론트 EtapasTab에 비활성화/재활성화 아이콘 추가
  - isActive=true → `tabler:eye-off` 아이콘 (비활성화)
  - isActive=false → `tabler:refresh` 아이콘 (재활성화)
- [ ] TASK-5: 확인 다이얼로그 컴포넌트 추가
  - 비활성화 전: usage 조회 → envio 있으면 경고 메시지, 없으면 일반 확인
  - 재활성화 전: 단순 확인
- [ ] TASK-6: "Mostrar inactivas" 토글 Switch 추가 (헤더)
  - 기본 false → `etapas.filter(e => e.isActive)` 만 표시
  - true → 전체 표시, 비활성 etapa는 회색/이탤릭 스타일
- [ ] TASK-7: ESLint 검증 (프론트 + 백엔드)
- [ ] TASK-8: 리뷰 리포트 작성

## 백엔드 변경 상세

**파일**: `api-ventago/src/app/subcon/etapas/etapa.controller.ts`

추가 엔드포인트:
```typescript
@Get(':id/usage')
async getUsage(@Param('id', ParseIntPipe) id: number) {
  return this.etapaService.getUsage(id);
}
```

**파일**: `api-ventago/src/app/subcon/etapas/etapa.service.ts`

신규 메서드:
```typescript
async getUsage(etapaId: number) {
  // 진행 중 envios count (PENDING/PARTIAL만)
  const activeEnviosCount = await this.envioModel.count({
    where: {
      etapaId,
      status: { [Op.in]: ['PENDING', 'PARTIAL'] }
    }
  });

  // vendor 매핑 수
  const vendorEtapasCount = await this.vendorEtapaModel.count({ where: { etapaId } });

  return { activeEnviosCount, vendorEtapasCount };
}
```

주의: EtapaService가 EnvioModel, VendorEtapaModel을 inject 해야 함 → `@InjectModel(Envio)`, `@InjectModel(VendorEtapa)` 추가 필요. Module import 순환 의존성 체크 필수.

## 프론트 변경 상세

**파일**: `ventago-app/src/views/talleres/tabs/EtapasTab.tsx`

### 신규 state
```typescript
const [showInactive, setShowInactive] = useState(false)
const [confirmDialog, setConfirmDialog] = useState<{
  open: boolean
  etapa: any | null
  mode: 'deactivate' | 'activate'
  usage: { activeEnviosCount: number; vendorEtapasCount: number } | null
}>({ open: false, etapa: null, mode: 'deactivate', usage: null })
const [deactivating, setDeactivating] = useState(false)
```

### 신규 핸들러
- `handleToggleActive(etapa)`: 비활성화면 usage 조회 → 다이얼로그 오픈, 활성화면 바로 다이얼로그 오픈
- `handleConfirmToggle()`: PUT `/talleres/etapas/:id` with `{ isActive: !etapa.isActive }` → refetch + toast

### UI 추가
- 헤더 우측: `<Switch>` + "Mostrar inactivas" 라벨
- 테이블 행 액션 열: 편집 아이콘 + 비활성화/재활성화 아이콘
- 비활성 etapa 행: opacity 0.55, fontStyle italic

### 필터링
```typescript
const visibleEtapas = showInactive ? etapas : etapas.filter(e => e.isActive)
```

## 완료 기준

- 비활성화 아이콘 클릭 → usage 조회 다이얼로그 → 확인 → isActive=false
- 재활성화 아이콘 클릭 → 확인 다이얼로그 → isActive=true
- PENDING/PARTIAL envio가 있으면 경고 메시지 ("N개의 진행 중 작업이 있습니다. 계속하시겠습니까?")
- "Mostrar inactivas" OFF → 활성만 표시 (기본)
- "Mostrar inactivas" ON → 전체 + 비활성은 회색/이탤릭
- ESLint 프론트 0개 오류, 백엔드 0개 오류
- 백엔드는 원래 `DELETE /talleres/etapas/:id`는 건드리지 않음 (하위 호환)
- 기존 Dialog(생성/수정) 동작은 변경 없음

## 금지사항 / 주의사항

- Hard delete 로직 추가 금지 (envios FK 무결성)
- Etapa 모델 스키마 변경 금지
- DB 마이그레이션 없음
- 기존 `isActive` 토글은 Dialog 안에서도 유지 (생성 시 기본 true)
- 이미 비활성인 etapa를 CT routing_path에서 제외하는 로직은 이번 범위 밖 (기존 `buildRoutingPath`가 모든 etapa를 가져옴 — 향후 과제)
- EnvioStatus import 경로 확인 필수 (TS enum)
- Op.in import 필요 (sequelize)
