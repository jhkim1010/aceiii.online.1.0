# 73 후속 5 — 재고 Cockpit 매트릭스의 지점 스코프 (새 세션용)

앞선 문서: `73-NEXT.md` ~ `73-NEXT-4.md`. 이 문서는 **2026-08-07 오후** 작업분.

---

## 0. 먼저 읽을 것

- jest: `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
- 마이그레이션은 로컬 5432 + 운영 5434 **양쪽** 적용. (이번 작업엔 마이그레이션 없음 — 코드만.)
- **CODEX 자문은 상시 절차다.** 이번에도 실제 결함을 하나 잡아냈다(§1-D).
  ★ **CODEX 에 `git diff` 를 시키지 마라.** 리포 루트에서 `git diff -- api-ventago/...` 는
    아무것도 안 나온다 — `api-ventago`/`ventago-app` 은 **gitlink(중첩 리포)** 라 루트 diff 에
    파일 단위 변경이 안 잡힌다. 각 리포에서 diff 를 떠서 **프롬프트에 인라인**으로 넣어라.
    (이걸 몰라서 CODEX 세션 두 개를 20분 넘게 헛돌렸다.)
  ★ `codex exec ... | tail -N` 로 파이프하면 **끝날 때까지 출력이 하나도 안 보인다.**
    파일로 리다이렉트하고 중간에 읽어라.
- **Jenkins 빌드 번호는 `nextBuildNumber - 1` 이 "이전 빌드"가 아니다.** push 직후엔 이미
  내 빌드가 번호를 받아 돌고 있다. 번호로 추측하지 말고 **로그에서 커밋 SHA 를 grep** 해라
  (`grep -l <sha> /var/lib/jenkins/jobs/<job>/builds/*/log`). 나는 이걸 착각해서
  "오지 않을 다음 빌드"를 10분 기다렸다 — 감시 루프가 **부재에서 침묵**하는 그 유형이다.

---

## 1. 이번에 고친 것 — 통합 보기에서 매트릭스가 한 지점만 보여주던 문제

배포: **api #635 / front #574** 둘 다 SUCCESS + 컨테이너 재생성 + 배포 번들에 코드 존재 확인.

### 1-A. 화면 지도 (다음 사람이 헤매지 않도록)

"통합 view 의 우측 상세 패널" = `reportes` > **Stocks Cockpit**.
`ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` 가 4패널 레이아웃을 조립한다.

```
┌───────────────────────────────────────┐
│ Panel A  지점 요약 (클릭 = 지점 선택,  │  selectedBranchId = null 이 "통합/전체"
│          '전체' 행 클릭 = null)        │
├──────────────────────┬────────────────┤
│                      │ Panel C  ←★    │  선택 제품의 색상×talle 매트릭스
│  Panel B  제품 목록   ├────────────────┤  GET /reports/stocks-cockpit/matrix
│  (Hoy+/Hoy− 컬럼)     │ Panel D        │  선택 셀 수동 재고 조정
│  GET .../items       │                │  POST /reports/stocks-cockpit/adjust
└──────────────────────┴────────────────┘
```

### 1-B. 진단 — SQL 이 아니라 JS 였다

`api-ventago/src/app/reports/reportsStocksCockpit.service.ts` `getMatrix()`:
SQL 의 `GROUP BY` 에 `pb.id` 가 있어 **(variant, product_branch) 당 1행**이 나온다.
`branchId=null` 이면 한 셀에 지점 수만큼 행이 온다. 그런데 매트릭스 빌드 루프가
`matrix[color][talle] = {...}` 로 **덮어써서** 마지막 행 하나만 남았다.

같은 화면의 Panel B(`getItems`)는 `GROUP BY p.id, ...` 라 pb 가 없어 **전 지점을 합산**한다.
그래서 위아래가 서로 다른 값을 말하고 있었다.

**운영 실측 (제품 262 = SKU 2545001 `[ACCESORIOS] COLLAR`, store 6):**

| | stock | h_ingreso |
|---|---|---|
| coolsistema (pb 212) | 3 | 130 |
| HELGUERA (pb 293) | 77 | 30 |
| **Panel B (합산)** | **80** | **160** |
| Panel C (수정 전, 마지막 행) | 77 | 30 |
| **Panel C (수정 후)** | **80** | **160** |

★ 73-NEXT-4 의 추정 두 개가 틀렸다:
- "우측 상세" 는 Historial drawer 가 아니라 Panel C 다.
- 30 은 "net 대신 ingreso 를 보여줘서"가 아니라 **한 지점 값이라서** 30 이었다.
  정정(`correccion ingreso%`)은 `type='adjust'` 라 `STOCK_FLOW_EXCLUDE_SQL` 에 걸려
  Hoy+ 집계에서 **애초에 제외**된다 — Panel B 도 마찬가지다.

### 1-C. ★ 표시 결함을 쓰기 결함으로 바꿀 뻔한 지점

`adjustStock` 은 `theoretical` 을 **그 pb 하나의** `SUM(stocks)` 로 **다시 계산**한다.
Panel D 가 화면에 보여주는 `Teórico` 는 프론트의 셀 값이다.

지금(수정 전)은 셀이 한 지점 값만 보여줘서 **우연히 자기일관적**이었다.
표시만 합산으로 고치고 `productBranchId` 를 그대로 뒀다면 —
사용자가 전 지점 합계(80)를 보고 "실제 재고 80" 을 입력 → 백엔드는 HELGUERA 기준(77)으로
diff 를 계산 → **+3 이 HELGUERA 한 지점에 들어간다.** 조용히 틀리는 쓰기다.

그래서 **기여 행이 딱 하나일 때만** `productBranchId` 를 확정하고, 그 외에는 `0`(조정 불가)으로
내보낸다. Panel D 는 그런 셀에 **저장 폼을 아예 내주지 않는다.**

### 1-D. CODEX 교정

> `branchCount = byBranch.length` 는 지점 수가 아니라 **행 수**다. 같은 지점의 중복 PB 행이
> "2개 지점"으로 둔갑한다.

맞는 지적이다. 세는 대상이 다르다 → `distinct branchId` 로 분리했다.
다만 **조정 대상 유일성은 여전히 행 수로 판정**한다 — 지점이 하나여도 PB 행이 둘이면
대상은 정해지지 않기 때문이다.

★ 근거 대조 (memory: "CODEX 지적도 근거까지 대조하라"): 운영 실측 결과
`(product_id, branch_id)` 중복 PB **0건**, 같은 부모 안 `(color_id, size_id)` 중복 활성 variant
**0건**. 즉 **지금은 재현되지 않는다** — 세는 값이 애초에 다르므로 넣은 방어다.

CODEX 의 **배포 순서** 조언도 채택했다: **백엔드 먼저**.
구 프론트 + 신 백엔드 = 다중 지점 셀이 빈 셀로 보여 기능만 일시 저하되고 **쓰기는 막힌다**(fail-closed).
반대 순서는 조정 폼이 열린 채로 남는다. (내 최초 판단은 프론트 먼저였다 — 틀렸다.)

### 1-E. 바뀐 파일

| 파일 | 내용 |
|---|---|
| `api-ventago/.../reportsStocksCockpit.service.ts` | `getMatrix` 합산 + `branchCount`/`byBranch`/`branches` |
| `api-ventago/.../reportsStocksCockpit.matrix.spec.ts` | 신규. 회귀 5건 |
| `ventago-app/.../panels/PanelC_ColorMatrix.tsx` | 빈 셀 판정 교체 + 스코프 칩 + 지점별 툴팁 |
| `ventago-app/.../panels/PanelD_StockAdjust.tsx` | 다중 지점 셀 쓰기 차단 + 초기화 키 보정 |

프론트에는 **구 백엔드 폴백**이 있다(`branchCount` 없으면 `productBranchId > 0 ? 1 : 0`).
백엔드가 안정되면 걷어내도 된다 — 다만 급하지 않다.

---

## 2. 아직 브라우저 미검증 (사람이 해야 함)

1. **이번 작업**: `reportes` > Stocks 에서 Panel A 의 **'전체'** 를 고르고 COLLAR 를 선택 →
   Panel C 헤더에 `Todas las sucursales (N)` 칩이 뜨는지 / 셀 값이 Panel B 와 같은지
   (Stock 80, Hoy+ 160) / 셀에 마우스를 올리면 지점별 내역이 뜨는지 /
   그 셀을 클릭하면 Panel D 가 저장 폼 대신 "지점을 고르라"는 안내를 내는지.
   그리고 **지점을 하나 고르면** 종전처럼 조정이 되는지(회귀).
2. **이월 (73-NEXT-4 §2-E)**: front #573 — 정정 확인창 없이 저장 + 5초 토스트 /
   저장 제품이 Historial 맨 위 크림색 / 사이드바 Admin → 대시보드 직행.

---

## 3. 이 코드베이스의 함정 (누적)

73-NEXT-4 §3 의 5개에 더해:

6. **집계 화면은 "한 화면 안에서 두 표가 다른 GROUP BY 를 쓴다"는 이유로 갈라진다.**
   Panel B 는 pb 없이, Panel C 는 pb 로 묶었다. 둘 다 SQL 은 맞았고 **JS 가 틀렸다.**
   같은 화면에 나란히 놓인 두 숫자는 **같은 스코프인지 화면이 스스로 말하게** 해야 한다
   (그래서 스코프 칩을 넣었다).
7. **표시를 고칠 때 그 값이 쓰기 경로의 입력이기도 한지 먼저 확인하라.** §1-C 가 그 사례다.
   읽기 값과 쓰기 대상이 같은 객체에 실려 다니면, 읽기를 고치는 순간 쓰기가 어긋난다.

---

## 4. 이월 — 계속 막혀 있는 것 (73-NEXT-4 §4 그대로)

- **결제수단 % 실사용 확인**: 운영 판매 한 건으로 Recargo 가 영수증에 찍히는지. 사람이 해야 함
- **jest CI**: `gh workflow run api-tests.yml --repo jhkim1010/api-ventago --ref main` 초록 확인 전까지
  완료로 적지 말 것
- **package-lock 불일치**: `npm ci` 불가, `npm install` 사용
- **0원 식당 판매 3건** (매장 11 "Asado"): 의도적 미보정
- **print-agent macOS**: 자동 업데이트 피드(`latest.yml`)는 Windows 전용. mac 은 수동 재설치
- **선물 티켓 실물 출력 확인**: 코드·릴리스·배선은 확인. 실제 출력은 사람이 해야 함

---

## 5. 남은 구조적 위험 (73-NEXT-4 §5 그대로 — 손대지 않았다)

- `type IS NULL AND stock > 0` 복제가 `2026-08-02-stock-balances.sql:125,133,134` /
  `2026-08-02-stock-interface-views.sql:75,79` 에 남아 있다. **전부 정정을 반영해야 하는 건
  아니다** — 133/134 는 "최초/최종 입고일" 로 의미가 달라 보인다. 용도 확정 전엔 손대지 마라
- 같은 테마 Select 문제로 조용히 깨져 있을 화면: `SaleReviewPanel.tsx:395`(외부 폭 65px ←
  최소폭 96px 와 양립 불가), `VariantsStockVenta.tsx:259`(100px),
  `SizeColorMatrixEditor.tsx:155`(110px). 뒤 둘은 셀 padding 착각도 함께 갖고 있다
- `editingMadre` 슬림화 (`parentId`/`parentName` 미사용, `deletedColorIds` 미소비)
- POS 판매 차감이 `type=NULL` 음수(`sales-create.service.ts:1274`)인데 온라인 주문은 `type='sale'`
- HTML 문서에 `Cache-Control` 없음 (정적 청크는 `immutable` 로 정상)
