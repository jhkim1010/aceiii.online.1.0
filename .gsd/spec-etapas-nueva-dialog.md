# SPEC: Etapas 탭 "Nueva Etapa" Dialog 연결

생성일: 2026-04-23

## 목표

Talleres 메인 뷰의 `EtapasTab.tsx`에서 "Nueva Etapa" 버튼과 행별 편집(연필) 아이콘을 Dialog 생성/수정 폼에 연결하여 매장 관리자가 공정 단계를 UI에서 직접 등록·수정할 수 있도록 한다.

## 배경 및 컨텍스트

- 파일: `ventago-app/src/views/talleres/tabs/EtapasTab.tsx` (353줄)
- 현재 101-103행의 "Nueva Etapa" 버튼에 `onClick` 핸들러 자체가 없음
- 테이블 213행의 연필 아이콘(`IconButton`)에도 `onClick` 없음
- 백엔드는 정상 동작:
  - `POST /talleres/etapas` (생성)
  - `PUT /talleres/etapas/:id` (수정)
  - `GET /talleres/etapas/all` (조회)
- 참고 구현: `ventago-app/src/views/talleres/etapas/talleres_EtapasListView.tsx` (라인 166-203의 Dialog)
- 데이터 페칭: `useTalleresEtapas()` SWR 훅 (`refetchEtapas()` 제공)
- 토스트 라이브러리: `react-hot-toast` (같은 폴더의 `LotesTab.tsx`에서 사용 중)
- 프로젝트 ESLint 규칙 엄격 (warning=error): `newline-before-return`, `lines-around-comment`, `no-unused-vars`

## 기술 스택

- 언어/프레임워크: Next.js 13 Pages Router + React 18 + MUI 5 + TypeScript
- HTTP: `apiConnector` (`src/services/api.service.ts`)
- 상태: 로컬 `useState`, SWR (외부 데이터)
- DB: 변경 없음 (프론트엔드만)
- ESLint 설정: `ventago-app/.eslintrc.*` (워크스페이스 레벨)

## 태스크 목록

- [x] TASK-1: 현재 `EtapasTab.tsx` 및 참고 `talleres_EtapasListView.tsx` 코드 파악
- [ ] TASK-2: SPEC 파일 작성 (현재 문서)
- [ ] TASK-3: `EtapasTab.tsx`에 imports 추가 (`Dialog`, `DialogTitle`, `DialogContent`, `DialogActions`, `TextField`, `Switch`, `FormControlLabel`, `apiConnector`, `toast`)
- [ ] TASK-4: Dialog 관련 state 추가 (`openDialog`, `editItem`, `formData`, `saving`)
- [ ] TASK-5: 핸들러 함수 작성 (`handleOpenCreate`, `handleOpenEdit`, `handleCloseDialog`, `handleSave`) — try/catch 필수
- [ ] TASK-6: "Nueva Etapa" 버튼에 `onClick={handleOpenCreate}` 연결
- [ ] TASK-7: 테이블 행 편집(연필) 아이콘에 `onClick={() => handleOpenEdit(etapa)}` 연결
- [ ] TASK-8: Dialog JSX 렌더링 블록 추가 (RateHistoryPanel 위 또는 컴포넌트 하단)
- [ ] TASK-9: ESLint 검증 (`npx eslint src/views/talleres/tabs/EtapasTab.tsx`)
- [ ] TASK-10: 리뷰 리포트 작성

## 데이터 모델

```ts
formData: {
  name: string        // 필수, trim 후 비어있지 않아야 함
  order: number       // 기본 0
  isActive: boolean   // 기본 true
}
```

- 신규 생성: `apiConnector.post('/talleres/etapas', formData)`
- 기존 수정: `apiConnector.put(`/talleres/etapas/${editItem.id}`, formData)`
- 성공 후: `refetchEtapas()` + `toast.success('Etapa guardada')`
- 실패 시: `toast.error('Error al guardar la etapa')` + `console.error`

## 완료 기준

- ESLint 오류 0개 (`EtapasTab.tsx` 기준)
- "Nueva Etapa" 버튼 클릭 → Dialog 오픈
- 폼 제출 시 신규는 POST, 기존은 PUT 호출
- 저장 성공 시 테이블 목록이 refetch 되어 새 etapa가 즉시 반영
- 편집 아이콘 클릭 시 해당 etapa 데이터로 Dialog 프리필
- 이름 공백만 있으면 "저장" 버튼 disabled
- 저장 진행 중 `saving` 플래그로 중복 요청 방지
- 에러 발생 시 Dialog 닫히지 않고 toast로 알림

## 금지사항 / 주의사항

- 백엔드는 수정하지 않는다
- Wave 7의 `RateHistoryPanel` / `selectedCell` 기존 로직은 건드리지 않는다
- Sequelize 모델이나 DB 스키마 변경 금지
- PostgreSQL pool 관련 작업 없음 (프론트엔드 단독 작업)
- 주석은 한국어, 함수/변수명은 영어
- 기존 Wave 7 단가 매트릭스 UI는 그대로 유지
