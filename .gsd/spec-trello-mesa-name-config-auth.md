# GSD Spec — Trello B4 (mesa 이름) + B5 (prefijo 저장 안 됨)

날짜: 2026-07-06 (자동 유지보수 루프)

## B4 — Mesas en modo restaurante: 회전 시 이름 사라짐
- 카드: https://trello.com/c/kfJu5KIJ (6a3584cd)
- 증상: 테이블을 회전(girar)하면 salón 뷰에서 mesa 이름이 안 보임.
- 원인: `TableCard.tsx` 에서 이름 라벨은 회전 밖(카드 위)에 있으나, 회전된 카드 본체(especialmente rect/oval 90°)의 시각적 bounding box 가 layout box 위로 (w−h)/2 만큼 확장됨. 카드 본체가 DOM 상 이름 뒤에 렌더되어 paint 순서상 위 → 불투명 배경(#232342/#e53935)이 이름을 덮음.
- 수정: 이름 Typography 에 `position:relative; zIndex:2` + 가독성용 반투명 흰 pill 배경.
- 파일: `ventago-app/src/views/restaurante/components/TableCard.tsx`
- 브랜치: `fix/trello-6a3584cd` (ventago-app)

## B5 — Prefijo(SKU 접두어) 수정이 저장 안 됨
- 카드: https://trello.com/c/7vJkl9OU (69d90504)
- 증상: prefijo 를 26 등으로 수정해도 저장 안 됨 (에러 없이 무시).
- 원인: `ConfigurationController` 에 @Auth() 가드 없음 → `CrudController.update()` 의 `@GetUser() user` 가 undefined → `if (!user) return null;` 로 **조용히 스킵**. 전역 가드는 ProxyThrottlerGuard(rate-limit)뿐, JWT 전역 가드 없음. by-store 만 @Auth() 명시돼 목록 조회는 정상 → "저장 안 됨"과 정확히 일치.
- 수정: `ConfigurationController` 클래스 레벨 `@Auth()` 부여 (MaterialSupplierPaymentController 와 동일 패턴). 소비처(BasicDataCard, ConfigurationsList/Modal)는 전부 인증 프론트 → 파급 없음.
- 파일: `api-ventago/src/app/config/configuration.controller.ts`
- 브랜치: `fix/trello-69d90504` (api-ventago)

## Review 체크
- ESLint: return 위 빈 줄 / 주석 위 빈 줄 / 미사용 import 없음.
- pool: 변경 없음 (쿼리/커넥션 무영향).
- 검증(사용자): `npm run lint` (ventago-app), 로컬 기동 후 prefijo 수정 → 재조회 시 유지 확인, salón 에서 mesa 회전 후 이름 표시 확인.
