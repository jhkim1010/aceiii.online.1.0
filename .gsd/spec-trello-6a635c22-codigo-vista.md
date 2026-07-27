# SPEC: Trello 6a635c22 — Codigo Vista 코드 컬럼 미표시 픽스
생성일: 2026-07-27 (trello-daily-loop 자동 실행)

## 목표
Codigo Vista 테이블에서 "코드가 존재하는데 표시되지 않고, 옆으로 스크롤해도 볼 수 없다"는 증상 해소.

## 배경 및 컨텍스트
- 카드: https://trello.com/c/zTHHD941 ("En el cuadro de codigo vista no se ve el codigo, tampoco se puede recorrer mas a un costado. Existen los codigos pero no muestran")
- 파일: `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` (2026-06-11 이후 무변경 — 증상 코드 현존)
- 검증된 메커니즘 (코드 정독):
  1. CÓDIGO 셀은 `width` 고정 + `overflow: hidden` + `textOverflow: ellipsis` → 컬럼 폭보다 긴 SKU 는 잘리고, **셀 내부 잘림은 테이블 가로 스크롤로 볼 수 없음** (카드의 "recorrer mas a un costado" 불가와 정확히 일치).
  2. 컬럼 폭은 localStorage(`codigo-vista-col-widths`)에 영구 저장되는데, 드래그 최소값이 40px 라 실수로 좁힌 폭(코드 사실상 안 보임)이 **세션을 넘어 지속**되고 복구 수단이 8px 드래그 핸들뿐.
- 운영 로그: error-2026-07-27.log 비어 있음 — 백엔드 무관, 순수 프론트 UI.
- DB/pool 무관 (프론트 단독 변경).

## 기술 스택
- Next.js 13 + MUI 5 (ventago-app)
- DB: 사용 안 함 (pool 영향 없음)
- ESLint: ventago-app 프로젝트 설정 (Warning 도 빌드 차단)

## 태스크 목록
- [x] TASK-1: `loadColWidths` 에 저장값 정합성 보정(최소 60px 클램프) + 드래그 최소값 40→60 통일 — 파일: CodigoVistaView.tsx
- [x] TASK-2: CÓDIGO 셀에 전체 코드 Tooltip 추가(잘려도 hover 로 항상 확인 가능) — 파일: CodigoVistaView.tsx
- [x] TASK-3: ESLint 검증 — `npx eslint CodigoVistaView.tsx` exit 0 (오류 0개)

## 결과 (2026-07-27)
- 브랜치 `fix/trello-6a635c22` (ventago-app) 커밋 **8740d40** — 로컬만, push 안 함
- main 워킹트리 원상 복구(클린). 샌드박스 브리지 제약으로 .git 에 stale *.lock.stale* 파일 다수 잔존 — Mac 에서 `find .git -name '*.lock*' -delete` 권장

## 완료 기준
- ESLint 오류 0개 (신규 코드 기준)
- 코드 셀이 잘려도 전체 SKU 확인 경로 존재 (Tooltip)
- localStorage 에 60px 미만 폭이 저장돼 있어도 로드시 자동 복구

## 금지사항 / 주의사항
- 테이블 레이아웃(tableLayout/minWidth) 변경 금지 — 회귀 위험
- 기존 미커밋 파일 커밋 금지 (워킹트리 클린 확인됨)
- 커밋은 브랜치 `fix/trello-6a635c22` 로컬까지만, push 금지
