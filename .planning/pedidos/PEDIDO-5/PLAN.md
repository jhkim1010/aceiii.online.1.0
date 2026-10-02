# PEDIDO #5 — 「Layout」 (POS 고객 정보 패널)

| 항목 | 내용 |
|---|---|
| 매장 · 지점 | cool (store 6) · coolsistema |
| 요청자 · 일시 | israel samuel · 2026-10-02 15:34 (AR) |
| 분류 | **개선** (화면 배치) |
| 접수 답장 | 자동 발송됨 (상태 en curso) |

## 요청 원문 (스페인어)
> al agregar cliente, se expande el cuadro de texto de cliente y tapa todas las descripciones.
> El checkbox de Aceptar promociones por Whatsapp estaría bueno que esté en el label de cliente

→ ① 고객을 넣으면 고객 입력칸이 **펼쳐져서** 아래 상품 설명을 가린다
→ ② 「WhatsApp 홍보 수신 동의」 체크박스를 **「Info de cliente」 제목줄**로 옮겨 달라

## 현재 동작 (코드 근거)
- `ventago-app/src/views/homes/components/InfoClient.tsx:280`
  문서번호가 **6자리 이상**이 되거나 고객을 고르면 `isExpanded` → 1줄(컴팩트)에서 **5줄**로 바뀐다
  (1012~1250행 4줄 + 1265행 WhatsApp 줄).
- `VcontrolHome.tsx:458` 왼쪽 열은 `InfoClient` 바로 아래 `ProductList`(카트)가 붙어 있고 높이가
  화면에 고정(`100vh`)이다 → 고객 패널이 늘어난 만큼 **카트 표가 줄어** 상품 설명 줄이 안 보인다.
  (`ProductListTable.tsx:317` 이 `clientExpanded` 로 높이를 다시 잰다 — 즉 «가림»이 아니라 «밀림»)
- 입력칸은 **라벨 없이 placeholder 만** 있어서, 값이 채워지면 무슨 칸인지 사라진다(첨부 캡처:
  `LUJAN 1419`, `FLORENCIO VARELA` 가 무엇인지 표시 없음). 원문 「tapa las descripciones」 가
  이쪽(칸 설명이 사라짐)을 뜻할 가능성도 있다 → 아래 «확인 필요».
- `GroupBox`(`src/components/ui/GroupBox.tsx`)는 이미 제목줄 오른쪽 `action` 슬롯을 지원한다 → ②는 간단.

## 제안 (권고안)
1. **WhatsApp 체크박스를 제목줄로** — `GroupBox action` 에 넣는다. 한 줄(≈34px) 절약. 요청 ② 그대로.
2. **펼침 높이를 5줄 → 3줄로 압축** — 같은 칸들을 재배치:
   - 1줄: CUIT/DNI · 이름 · Cond. IVA · 판매원
   - 2줄: 주소 · 지역 · 주(Provincia) · 나라
   - 3줄: 전화 · 이메일 · 운송사 · 상호(fantasía) · 메모 아이콘(📝, 누르면 메모 입력) · ↺ · Nuevo
3. **「▲ 접기」 버튼** — 입력이 끝나면 한 번에 1줄 요약으로 접는다(고객 선택 시 이미 쓰는 요약 카드와 동일).
   데이터는 그대로 유지. 다시 ✎ 로 펼친다.
4. 칸 설명 문제 대응: 값이 들어간 칸은 **마우스를 올리면 칸 이름 툴팁**(높이 증가 0).

### 대안
- B: 펼침 패널을 카트 위에 **겹쳐 띄우는 팝오버** — 카트 높이는 안 바뀌지만, 입력 중엔 카트가 가려진다. 비권장.
- C: 라벨을 칸 위에 상시 표시(MUI floating label) — 칸 설명은 해결되나 높이가 더 늘어난다. 비권장.

## 범위 밖
- 고객 등록 API·검증 규칙 변경 없음. 컴팩트(1줄) 모드·요약 카드 동작 변경 없음.

## 영향
| 대상 | 내용 |
|---|---|
| api | 없음 |
| app | `InfoClient.tsx` (배치·action·접기) — POS 화면 전 매장 공통 |
| DB | 없음 |
| 위험 | POS 키보드 흐름(F8 판매원, Enter 이동 순서 `focus-pos.ts`) — 칸 순서가 바뀌면 Tab/Enter 순서 확인 필요 |

## 규모 · 검증
- 규모: **S~M** (프론트 1파일 + 포커스 순서 확인)
- 검증: app tsc/eslint · cmux 브라우저로 POS에서 CUIT 입력 → 펼침 높이 측정(전/후) · Enter 이동 순서 · WhatsApp 체크 저장 확인(고객 저장 후 `whatsappOptIn` 반영 — InfoClient.tsx:658)

## 확인 필요 (매장에 물어볼 것 — 승인 시 보낼 초안)
> ¡Gracias Israel! Para entender bien: cuando decís que «tapa las descripciones», ¿te referís a
> que **la lista de productos queda más chica** y no se ven las descripciones de los artículos, o a
> que **los campos del cliente pierden el nombre** (no se sabe qué es cada casilla una vez cargada)?
> Vamos a mover el check de WhatsApp al título «Info de cliente» como sugeriste.
