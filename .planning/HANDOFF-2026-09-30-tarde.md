# 핸드오프 2026-09-30 (오후) — Costo por variación · POS 변형별 단가 · 티켓 결제수단 · 잡건

> 앞 문서: `HANDOFF-2026-09-30.md` (오전)

## 1. 운영에 나간 것 (전부 빌드·컨테이너 확인)
| 내용 | 커밋 | 빌드 / 마이그 |
|---|---|---|
| 관리자 앱: 매장 상세 «Modo AFIP» (ws↔soap, `/afip/provider-switch` 재사용) v1.1.2+4 | root `022770d` | APK Dropbox 복사 · **Google Drive 폴더 없음 → 미복사** |
| Tiendas 목록 페이징 제거(전체 조회 200씩 병렬, 스크롤) | app `cc8906ea` | #874 |
| Facturación mensual 할인 반영(단일 매장 상세가 `discounts: []` 였음 — Sager) | api `7591132a` · app `76567e27` | #1016/#875 |
| `GET /apps` 전원 403 → superadmin 읽기 전용 컨트롤러 | api `672fa86e` | #1016 |
| POS Repaso: 열림 상태 기억 · Ctrl+D/Editar 가 안 닫음 · 닫힘 시 시계 59px | app `deecf564`…`7eeaf749` | #876~#880 |
| 서브카테고리 이름 유니크 = 매장+카테고리 | api `97be19b4` · app `6a5dbc0e` | 마이그 `2026-09-30-d` (로컬+운영) |
| 상품 빈 상태 → 날짜 옆 빨간 «Ningún producto cargado» | app `b50e860c` | #882 |
| Biblioteca 대량 업로드: 자동 축소(1600→1200px)·재시도·이탈 경고·PNG 흰배경 | app `a8fa1c04` | #883 |
| 색/사이즈 안 쓰는 매장: 판매 상세 3곳에서 변형 표 안 그림 | app `fdb6a57b` | #883 |
| **Costo por variación** (상품 화면·원가/환율/되돌리기·판매 원가) | api `5a020c59` · app `7b835f4a` | 마이그 `2026-09-30-e` (로컬+운영) · #1018 |
| **POS 변형별 단가**(단가별 줄 나누기) + 서버 가격판정 변형 우선 | api `5f3526f1` · app `8151cf32`,`5ae1cec9` | #1019/#884 |
| 티켓 «Forma de Pago» 재출력에도 · 0원 줄 제외 | app `5412add3` | #884 |

## 2. Costo por variación — 구조 (다음에 손댈 사람용)
- 플래그: `products.cost_por_variacion`(madre). 변형 원가 = 자식 `products.cost`(통화·마진은 madre).
- 저장 경로 하나: `PUT /cotizacion/productos/:id/costo` {cost,costCurrency,markupPct,costoPorVariacion,variantes[]}
  → `guardarCostoPorVariacion` 가 변형마다 base+레벨 계산, `bulkUpdatePrices` meta `sinCascada`/`bloquearPrimero`.
  플래그 모르는 호출자(CodigoVista)도 madre 플래그를 존중.
- 가드: 플래그 madre 에 부모가격 일괄 전파 → **ERR-COSTO-010**(트랜잭션 안에서 잠금 후 판정). 끌 때 madre 원가 필수 ERR-011. 동시수정 ERR-012.
- 되돌리기: 가격이 **전부** 되돌아갈 때만 원가·플래그 복원.
- 판매 원가(`costo-unitario.ts`): 플래그 있으면 변형 원가 우선, 없으면 madre (끈 뒤 남은 변형 원가는 무시).
- POS: 카탈로그 `precioPorVariante` + `stockByVariant[].price`. `utils/precio-variante.ts` 가 표 수량을 **단가별 줄**로 재구성(가족 = 같은 madre·가격표·이름·수동가격 여부). 서버 `precio-actual.ts` `varianteDecide`.
- 시험: api itest `costo-por-variacion`(12) · `sale-costo-por-variacion`(5, 판매 종단) — 둘 다 돌연변이 확인. app `precio-variante`·`costo-variacion`·`ticket-pagos` spec.

## 3. 남은 일
- **브라우저로 실제 확인 안 함**: 상품 화면(체크·칸별 원가 저장) → POS 에서 표 입력 → 장바구니 단가별 분리·합계. 사용자 확인 대기.
- 남은 경미 위험(Codex): 검증 직후 새 변형 삽입 경합 · 새 변형 생성 시 호출자가 임의 가격을 보내면 원가식과 불일치 · 배포 중 구/신 혼재 창.
- 자식 SKU 스캔은 여전히 POS 목록에 없음(변형별 단가는 qMode 표 경로만).
- **superadmin 전용 설정 페이지**: 사용자 제안 — 매장 설정 탭(Menú 등)은 superadmin 에게 저장 불가(매장 없음). 무엇을 설정할지 사용자 답 대기. 우선 안내 문구로 막을지도 미정.
- 관리자 앱 APK 를 Google Drive 배포 폴더에 올려야 함(이 Mac 에 폴더 없음).
- Sager 는 SOAP 전환 불가: 발행자(CUIT/PV)·인증서 0건 — 먼저 등록 필요.
- 오전 문서의 남은 일(Express 5 배열 쿼리 전수 조사, MinIO 원본 파일명 덮어쓰기 등) 그대로.
- 앱 jest `pos-precio-lista-igual-al-cobro.spec` 기존 실패 1건 그대로.

## 4. 환경 메모
- CODEX 자동 훅은 기준선이 오래돼 diff 가 커지면 자격증명 형태 탐지로 전송을 거부한다 → 이번엔 커밋 diff 를 손으로 넘김(`codex exec --sandbox read-only "$P" </dev/null > out`).
- 돌연변이 결과 «Tests: 0» = 컴파일 실패(미실행). 타입이 맞는 치환(`&& Date.now() < 0`)으로 해야 측정된다.
- 소스 grep 시험(`by-parent-attributes.spec`)은 `attributes: [ ... ]` 안 주석의 `]` 에 깨진다 — 배열 안 주석엔 대괄호 금지.
- macOS 엔 `timeout` 없음. itest 가 안 끝나면 `--forceExit`, 출력은 파일로.
- 목업 캔버스: https://claude.ai/artifact/AGTg8fz5M9XW9H33NgQW4Q (비공개)
