# 핸드오프 2026-09-29 (저녁) — 메뉴 숨김 · Novedades · 에이전트 · Cielo

> 앞 문서: `HANDOFF-2026-09-29-impresion-precios-permisos.md` (오후분은 그 문서 §6)

## 1. 운영에 나간 것 (전부 빌드·릴리스 확인)
| 내용 | 커밋 / 태그 | 빌드 |
|---|---|---|
| 에이전트 버전 기록 `branch_agents.agent_version` + Impresoras 화면 «Versión» | api `5c1096d3` · app `6a580329` · 마이그 `2026-09-29-f` | #1003 / #860 |
| Mac 앱 «손상됨» 해결 — afterPack ad-hoc 서명(번들 전체) | root `print/zebra scripts/afterpack-adhoc-sign.js` | print-agent v1.2.8 · zebra v1.0.20 |
| Configuración 표 17개: Actions 열을 이름 바로 뒤로 (`actionsAfterFirst`) | app `b792aa96` | #861 |
| **Preferencias › Menú** — 매장이 앱/모듈을 메뉴에서 숨김(권한 불변, admin 은 «· oculto») | api `313695fe` · app `1112601a` · 마이그 `2026-09-29-g` (`store_configs.menu_prefs`) | #1004 / #862 |
| Novedades: 자동 풍선 제거 → 로그인 시 주간 알림 + **Alt+F1** 패널 | app `31127c38` | #863 |
| **Novedades 설문** + Reportes › Novedades(admin 전용) | api `21bd8068` · app `bce02bb2` · 마이그 `2026-09-29-h` | #1005 / #865 |
| Proveedor 등 분류명 별칭이 유지 안 되던 결함 + «NONE» 을 상품명 접두어에서 제외 | app `66fd056b` | #864 |
| Cielo(22) 상품 14개 이름에서 `/NONE` 제거 (DML, 승인) | 마이그 `2026-09-29-i` | — |
| zebra QR 미리보기가 «2 por etiqueta» 실제 배치 표시 | root | zebra v1.0.21 |
| zebra QR 탭: 가격수준 재요청 + 기본 «Precio base» 선택 | root | zebra v1.0.22 |

운영 DB 적용(5434, 로컬 5432 동일): f(컬럼) · g(컬럼) · h(테이블+권한 1/20/20) · i(Cielo 14행).

## 2. 결함 원인 기록 (재발 방지)
- **분류 별칭**: 저장 키(`Suppliers`,`Sizes`,`colors`,`Seasons`,`origins`)와 읽기 키(`supplier`…)가 달랐다 + `useState(title)` 가 첫 값에 고정. `utils/module-alias.ts` 가 단일 출처, 옛 키도 읽는다.
- **zebra 가격수준 빈 목록**: QR 탭이 목록을 1회만 요청(`qrInitOnce`) — API 재배포 중 열면 영구 공백이었다.
- **Mac «손상됨»**: 인증서 없이 electron-builder 가 서명을 건너뛰어 번들이 봉인되지 않았다. 지금은 «확인되지 않은 개발자» → 설정›보안›«그래도 열기». 경고 없애려면 Developer ID + 공증(계정 필요).

## 3. Cielo × WooCommerce — 진행 중 (사장님 차례)
결정: **기준은 Ventago**, 처음엔 **주문 수신만** 켠다. 로그인 정보는 대화에 있었지만 사용하지 않았다(비번 변경 권고함).
0단계 대조 결과 (공개 페이지만 읽음, 원본 CSV 는 세션 scratchpad — 재생성: `/tienda/page/N` 의 `data-product_sku` + `wp-json/wp/v2/product`):
- 쇼핑몰 **916개**(단일 665·옵션 251). SKU 719개 중 718개가 `20`,`9.5` 같은 짧은 숫자로 서로 다른 상품이 공유(64종) → **상품 코드로 쓸 수 없음.** 197개는 SKU 없음.
- Ventago Cielo 15개(부모 8). 일치 **1개**(PINZA P47 `25372379003`).
- 주문 수신만은 안전: SKU 미일치 품목은 `[WP no-SKU] 이름` 으로 보류판매에 들어가고 notes 에 «SKU sin match» (`wp-webhook.service.ts:311`).
- ★ **재동기화 금지**: 설명서(`SETUP-WOOCOMMERCE.md:149`)는 «보고만» 이라지만 코드는 **없는 SKU 를 publish 로 생성**(`wp-sync.service.ts:420-443`). 설명서 수정 필요.
다음 단계: ① 사장님: WP 고유주소≠Plain, REST API 키(Read/Write, 관리자) ② Sucursales › Cielo › Web 채널 생성·연결시험(카탈로그 스위치 OFF) ③ 웹훅 2개(Pedido creado/actualizado, v3) ④ 시험 주문 ⑤ 이후 별도 phase: Woo 916개 → Ventago 가져오기 + Ventago SKU 를 Woo 기존 상품에 써 넣어 연결 → 재고/가격 동기화.

## 4. 남은 일
- **Phase 97** (superadmin macOS 데스크톱 앱) — 추가만 됨. `/gsd:discuss-phase 97`.
- 카트 단가 승인 2단계 — 결정 대기.
- 출력 경로 2번(판매 응답 안의 출력 쿼리) — 보류(측정상 급하지 않음).
- 확인 요청: 로그인 로고(오른쪽), NOIX 재인쇄, Cielo comandera 2대 offline, zebra 1.0.22 QR 탭.
- `configurations` 표는 첫 열이 ID 라 Actions 가 ID 뒤로 감 — 이름 뒤가 맞으면 조정.

## 5. 환경 주의 (이번 세션에 겪음)
- **로컬 electron-builder 금지** — 루트 node_modules 147개가 잘렸다(복구 완료). 메모리 `local-electron-builder-prunes-root-node-modules`.
- dev `nest start --watch` 가 `dist` 를 갱신하지 않고 있었다 → 부하시험은 `api-ventago/dist-lt`(tsc 출력) 로. `dist-lt/`·`dist-lt-old/` 는 미커밋 폴더로 남아 있음(`git add -A` 주의).
- `.env` 는 원격 스테이징(15432). 로컬 DB 는 `DATABASE_PORT=5432`.
- jest 는 `NODE_OPTIONS=""` + `--maxWorkers=1` (2048 힙 상한이 OOM 을 만든다).
- zebra dev 실행: `npm run dev:zebra` — 예전 인스턴스가 살아 있으면 단일 인스턴스 잠금으로 새 것이 조용히 종료된다(메인 PID 를 먼저 kill).
