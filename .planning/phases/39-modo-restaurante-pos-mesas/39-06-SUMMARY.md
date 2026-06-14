---
phase: 39-modo-restaurante-pos-mesas
plan: 06
subsystem: frontend (config toggle + 배치도 editor)
tags: [restaurant, storeConfig, swr, salon-editor, normalized-coords, configuracion, checkpoint-pending]
status: checkpoint-pending
requires:
  - 39-02 (RestaurantTables CRUD 라우트: by-branch / POST / PUT :id/position / DELETE)
  - 39-04 (storeConfig update-flag 화이트리스트 useRestaurantMode + restaurant-categories 라우트)
provides:
  - StoreConfigContext.useRestaurantMode + restaurantCategoryIds (분기 메커니즘 — 39-07 SalonView 가 소비)
  - useRestaurantTables SWR 훅 + RestaurantTableRow export (39-07 재사용)
  - configuracion/restaurante 토글 페이지 (admin WithAccess 게이트)
  - SalonEditor 자유 드래그 배치도 편집기 (정규화 0~1 좌표, configuracion 전용)
affects:
  - 39-07 SalonView (useRestaurantMode 분기 + useRestaurantTables 렌더)
tech-stack:
  added: []
  patterns:
    - "StoreConfigContext 3-spot 미러 확장 (interface/defaultState/fetchConfig) — 기존 use* 플래그 패턴"
    - "순수 pointer 드래그 정규화 좌표 (getBoundingClientRect → clamp 0~1) — dnd-kit 미사용 (39-RESEARCH 권장)"
    - "next/dynamic ssr:false + WithAccess(admin) — configuracion 권한 게이트 (preferencias 선례)"
    - "useApi(SWR) 기반 참조 데이터 훅 — 전역 5분 dedup"
    - "에러 더블 노출: 인라인 Alert + react-toastify 토스트 (feedback_error_visibility)"
key-files:
  created:
    - ventago-app/src/hooks/api/useRestaurantTables.ts
    - ventago-app/src/pages/configuracion/restaurante.tsx
    - ventago-app/src/views/configuracion/restaurante/RestauranteConfigView.tsx
    - ventago-app/src/views/configuracion/restaurante/SalonEditor.tsx
  modified:
    - ventago-app/src/context/StoreConfigContext.tsx
decisions:
  - "SWR 훅에 명시 dedupingInterval:300000 전달 — 전역 5분과 동일하지만 플랜 acceptance(300000) 충족 + 의도 명시"
  - "SalonEditor storeId prop 수용하되 백엔드는 user.storeId 스코프이므로 void 처리 (no-unused-vars 회피 + 향후 멀티-store 검증 훅)"
  - "테이블 카드에 stopPropagation 삭제 버튼 — pointerdown 드래그와 click 삭제 분리"
metrics:
  duration: ~12min
  completed: 2026-06-14
  tasks: 2 of 3 (Task 3 = 브라우저 human-verify checkpoint)
  files: 5
requirements: [REQ-1, REQ-4, REQ-5]
---

# Phase 39 Plan 06: Config 식당모드 토글 + 배치도 편집기 Summary

req1/4/5 프론트 절반 완성. (1) StoreConfigContext 3곳(interface/defaultState/fetchConfig)에 `useRestaurantMode` + `restaurantCategoryIds` 노출 — 39-07 SalonView 분기 메커니즘. (2) configuracion/restaurante 토글 페이지(admin WithAccess) — 식당모드 Switch(update-flag) + 카테고리 다중선택(restaurant-categories). (3) SalonEditor 자유 드래그 배치도 편집기 — 순수 pointer + getBoundingClientRect 정규화 0~1 좌표, 추가/삭제/형태·좌석수 파생 크기, configuracion 전용(SalonView 미노출, 권한 분리). (4) useRestaurantTables SWR 훅. **Task 3(브라우저 검증)은 human-verify checkpoint — 미완료(checkpoint-pending).**

## What Was Built

| 항목 | 내용 |
|------|------|
| StoreConfigContext (3곳) | interface + defaultState(false/null) + fetchConfig(res 매핑) 에 useRestaurantMode/restaurantCategoryIds. 기존 catch 폴백(false) 유지 |
| useRestaurantTables.ts | useApi 기반 SWR 훅. `RestaurantTableRow` export(39-07 재사용), `dedupingInterval:300000`, branchId 없으면 null key (조건부 fetch) |
| restaurante.tsx (page) | next/dynamic(ssr:false) + WithAccess(allowedApps:['admin']) + acl read/configuracion |
| RestauranteConfigView | 식당모드 Switch → PUT update-flag{field:'useRestaurantMode'}. 카테고리 multi-Select → PUT restaurant-categories{categoryIds}. context reload 후 동기화. 인라인 Alert+토스트 더블 에러. 토글 OFF 시 편집기/카테고리 숨김 |
| SalonEditor | branch selector(useBranchByStore) → useRestaurantTables. 캔버스 정규화→픽셀(left=posX*100%). 순수 pointer 드래그 clamp 0~1 → PUT :id/position. 추가(POST posX/posY 0.5)/삭제(remove). 형태+좌석수 파생 크기(BASE+scale, w/h 미저장). 상태색 libre/ocupada/por_cobrar |

## Tasks Completed

| Task | Name | Commit (submodule) | Pointer (parent) |
|------|------|--------------------|------------------|
| 1 | StoreConfigContext + SWR 훅 + 토글 페이지 | 8864ce4 | f019550 |
| 2 | SalonEditor 자유 드래그 편집기 | 6956f59 | f019550 |
| 3 | 브라우저 human-verify | **PENDING (checkpoint)** | — |

## Verification

| Check | Result |
|-------|--------|
| `npx eslint` 5파일 | PASS — 0 errors (lines-around-comment 4건 수정 후) |
| `npx tsc --noEmit` 전체 | PASS — exit 0, 0 errors |
| `grep -c useRestaurantMode StoreConfigContext` | 3 (interface+defaultState+fetchConfig) ✅ |
| useRestaurantTables: RestaurantTableRow export + dedupingInterval:300000 | ✅ |
| RestauranteConfigView update-flag + restaurant-categories PUT | ✅ |
| 인라인 Alert + toast 더블 에러 | ✅ (reportError 헬퍼) |
| `.delete(` count (restaurante view + 훅) | 0 ✅ (apiConnector.remove 사용) |
| SalonEditor getBoundingClientRect + Math.min(1,Math.max(0,...)) | ✅ (clamp 2건) |
| SalonEditor apiConnector.put :id/position + post + remove | ✅ |
| SalonView 편집 진입점 | 없음 (configuracion 전용) ✅ |

## Decisions Made

- **dedupingInterval 명시 전달**: 전역 SWRConfig 가 이미 5분 dedup 이지만, 플랜 acceptance(`dedupingInterval: 300000`)와 의도 명시를 위해 훅에서 명시 전달.
- **storeId prop void 처리**: 백엔드 라우트가 `user.storeId` 로 스코프하므로 SalonEditor 의 storeId prop 은 현재 동작에 불필요하나, RestauranteConfigView 계약 일관성 + 향후 멀티-store 검증 훅으로 prop 유지 → `void storeId` 로 no-unused-vars 회피.
- **삭제 버튼 stopPropagation**: 테이블 카드는 onPointerDown 으로 드래그 시작 — 삭제 IconButton 에 `onPointerDown stopPropagation` 으로 드래그/삭제 제스처 분리.

## Deviations from Plan

플랜과 동일하게 구현. ESLint 보강 1건:
1. **[Rule 1] lines-around-comment 4건 수정** — StoreConfigContext 3곳 + 훅 1곳 주석 위 빈 줄 추가 (BUILD-blocking ESLint). 동작 영향 없음.

전역 SWR fetcher 가 이미 apiConnector.get 으로 구성되어 있어 훅에서 별도 fetcher 불필요 — useApi 래퍼 재사용(useBranchByStore 선례).

## Known Stubs

없음 — 모든 경로 실 백엔드 라우트(39-02/39-04) 연결. 단 Task 3 브라우저 검증 미완(아래 checkpoint).

## Threat Flags

없음 — T-39-14(Elevation: configuracion WithAccess admin + SalonView 미노출), T-39-15(Tampering: 클라 0~1 클램프 + 백엔드 @Min(0)@Max(1) 39-02) 둘 다 plan threat_model 의 mitigation 구현. 신규 trust boundary 없음.

## Checkpoint (Task 3 — human-verify, BLOCKING)

브라우저 수동 검증 대기 중. 사용자 확인 항목:
1. `./dev.sh` 실행 → 식당 매장 admin 로그인 → configuracion/restaurante 진입
2. 식당모드 토글 ON → 저장 (BadRequest 없음)
3. 식당 카테고리 다중 선택 → 저장
4. SalonEditor: 지점 선택 → 테이블 추가(형태/좌석수) → 캔버스 표시
5. 테이블 드래그 → 이동 → 새로고침 후 위치 유지(정규화 좌표 저장)
6. 테이블 삭제 동작
7. seller(판매권한) 로그인 시 편집기 진입점 없음(권한 분리)

승인("approved") 시 39-06 완료, 문제 시 화면 설명.

## Self-Check: PASSED

- FOUND: StoreConfigContext / useRestaurantTables / restaurante.tsx(page) / RestauranteConfigView / SalonEditor / 39-06-SUMMARY.md
- FOUND: submodule 8864ce4 (Task1), 6956f59 (Task2); parent pointer f019550
- Task 3 (브라우저 human-verify) PENDING — checkpoint-pending (플랜 미완료, 39-06 verifying 보류)
