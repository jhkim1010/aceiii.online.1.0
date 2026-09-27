# 핸드오프 2026-09-27 (c) — 온보딩 목업 · 상품 화면 개선 · Código Vista 설명

> 앞 문서: `HANDOFF-2026-09-27-b-impresoras-menu-y-pendientes.md`
> ★ 그 문서의 「§2 미배포 Impresoras」는 **이미 배포돼 있었다**(시드 18매장 · api #982 · front #826).

## 1. 이번 구간에 운영에 나간 것 (전부 빌드 SUCCESS · 컨테이너 재생성 확인 · 운영 화면 클릭 검증은 안 함 — 로그인 필요)

| 내용 | 커밋 | Jenkins |
|---|---|---|
| 신규 상품 「STOCK TOTAL」 직접 입력(색·탈레 미선택=기본 칸만일 때) / 고르면 🔒 잠금 | app `3adcefeb` `0b091bba` | front #827 |
| 상품 화면 지점 자동 선택: 1개면 그것, 여러 개면 마지막으로 직접 고른 지점(localStorage, 매장·사용자별) 없으면 첫 번째 · 지점 없이 madre 저장 시 조용히 끝나던 것 → 오류 토스트 · 늦게 온 타 매장 지점 목록 무시 | app `c06ba53c` `800db39c` | front #828 |
| 상품 목록 아래 중복 풋터(N productos · N unidades · 날짜) 제거 | app `d9b7dd83` | front #829 |
| 사진 칸 하나로: 왼쪽 「Imagen」 제거, 오른쪽 큰 칸이 올리기·✕·대표 지정(`ProductImagesPanel.tsx`) · 「Datos / Descripción por WEB」 탭을 1행으로 올려 폼 높이 축소 | app `63377383` | front #830 |
| **DDL(승인됨)** `products.description` varchar(255)→text, 로컬 5432·운영 5434 적용·대조 완료 | api `71fbbbf2` (`migrations/2026-09-27-f-products-description-text.sql`) | api #983 |
| Código Vista 「📝 Descripción」 탭(코드 마드레 설명 5칸 편집, `editar-un-producto`, 없으면 읽기 전용) · 설명 HTML `&amp;` 누적 버그 수정(`descripcion-web.ts` + 시험 6) | app `08eb3836` | front #831 |
| 상품 화면 **수정** 저장이 설명을 저장(종전엔 신규 생성 때만 → 운영 619개 중 설명 0) | app `65b89e0f` `270a54cf` | front #832 |

시험: `stock-directo.spec.ts` 16 · `sucursal-recordada.spec.ts` 9 · `descripcion-web.spec.ts` 6 — 돌연변이로 확인(동치 1개 제외 전부 사망).

## 2. 목업 (구현 안 됨 — 결정 대기)

- `.planning/sketches/onboarding-primer-ingreso.html` — 신규 고객 온보딩 전체.
  환영(업종 6: Ropa · **Accesorios de indumentaria, Piercing** · Almacén/kiosco · Gastronomía · Ferretería · Otro)
  → **업종별 추천 카탈로그 자동 생성**(카테고리·서브·사이즈·색·시즌·가격 레벨, 별칭 Medida/Terminación/Material)
  → 계획 → 준비(목록 → **가격 레벨** → 첫 상품/SKU → Ventas(결제수단·판매원) → Impresoras(①설치 ②연결 ③배정))
  → 학습(판매 전 점검 오버레이 → **연습 모드** 판매(이름/SKU 입력→목록 선택→사이즈×색 재고표) → 마감·arqueo).
  단계 완료마다 폭죽 + 「Siguiente paso」 카드, **Enter 만으로 전 과정 진행**(검증: Enter 67회로 완주, 오류 0).
  원칙(사용자): **기존 화면은 바꾸지 않는다 — 가이드는 위에 얹는 층.** 연습 판매는 CODEX 권고대로 저장 안 함(실판매 후 취소 금지).
- `.planning/sketches/codigo-vista-descripcion.html` — 배포된 Descripción 탭 + 제안 3(「Cambios sin guardar」 · 「Vista en la web」 미리보기 · 표의 설명 있음 점). **사용자 선택 대기.**

## 3. 결정됐고 아직 시작 안 한 일 (앞 문서에서 이월)
- Ganancia 환율 기준(`sale_items.unit_cost_orig/currency/rate` expand) — 원가 입력 시작 전에
- print-agent / zebra-agent 「이 프린터를 쓰는 터미널」 표시 — 릴리스는 태그 수동

## 4. 알려진 미해결 (보고만 함)
- 상품 화면: 폼이 지점 선택을 비웠다 채우는 순간 madre 를 누르면 다른 지점 그리드가 뜰 수 있음(기존 경쟁 조건). 해법: 비우지 말고 기억 지점을 바로 넣기.
- madre 저장이 지점 없음·unresolved 로 막히면 설명도 같이 안 저장됨(토스트는 뜸).
- 이미 저장된 사진은 새 사진 칸에서도 삭제·대표 변경 불가(종전과 동일).
- SKU 가 분류의 **전역 id** 로 조립돼 설정 자릿수를 넘침(Cielo 17자리). 매장별 `store_entity_id` 가 이미 있음 — 바꿀지 결정 필요(기존 SKU 와 형식 혼재).
- 기준가 판정이 **이름 「PRECIO 1」** 에 묶여 있음(`productsPrice.service.ts:492`, 코드 스스로 임시 방책).
- 결제수단 추가 버튼 라벨이 영어 「New」(Configuración › Ventas).
- 현 환영 모달(`OnboardingDialog`)이 없는 「Venta Rápida」 스위치를 안내함.

## 5. 운영 실측 (2026-09-27)
- 최근 가입 8매장 중 5곳(kim · Krencia · The Market · beula · CARAMELO)이 시드 「General」 1개 + 제네릭 상품 1개, **가격 레벨 0개**에서 멈춤. Cielo 는 공급처에 색(BLANCO·NEGRO…)을 넣음.
- 판매원(`Sellers`)은 매장마다 1명 시드.

## 6. 교훈
- **cmux 브라우저 창이 가려지면 requestAnimationFrame 이 멈춘다** — 목업 말풍선 위치가 계산 안 돼 「안 보임」. 위치 계산은 setTimeout 으로. 백그라운드 탭의 타이머도 느려져 긴 자동 시험은 결과를 window 에 두고 폴링.
- **개발 번들은 cmux 에서 하이드레이션 안 됨**(빈 화면) — 실제 화면 검증은 운영 빌드/운영에서.
- 커밋 게이트 훅이 **같은 명령의 `grep -aq`** 를 `git commit -a` 로 오인해 막는다 → 커밋은 단독 명령으로.
- CODEX 는 브리프 **파일을 읽히면** 그 직후 조용히 죽었다(3/3). 맥락을 ~500자 argv 에 직접 넣으면 됨.
- `price_types.increase_value` 는 **기준가 대비 %**(80 = 20% 저렴), +% 아님 — 목업 설명을 한 번 틀리게 썼다.
- useCallback 안에서 `product` 를 읽는 판정은 낡은 렌더를 본다 → ref 로 읽기(eslint exhaustive-deps 경고가 실제 결함을 가리켰다).
