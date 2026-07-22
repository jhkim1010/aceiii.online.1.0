# SPEC — 오프라인 시 F10(AFIP 발급) 차단 + 프린트/제브라 오프라인 동작 보장

작성 2026-07-21 · 상태: 구현 완료(디스크 반영), 빌드/실기 검증 대기

## 배경 / 문제
오프라인(인터넷 단절) 중에는 AFIP CAE 를 실시간 발급할 수 없다. 그런데 POS 의 F10
(판매 완료 + AFIP 발급 프리뷰)이 그대로 열려 있어, 캐셔가 오프라인에서 F10 을 누르면
발급 요청이 네트워크 오류로 실패하거나 혼란을 준다. 발급 경로를 오프라인에서 차단해야 한다.
프린트(코만다/print-agent)와 제브라(라벨/zebra-agent)는 오프라인에서도 계속 동작해야 한다.

## 조사 결과 (실측)
- F10 핸들러: `ProductList.tsx` `submitVentaConFactura` (useHotkeys('f10')) → handleSubmit(..., openFacturarAfter=true)
  → 판매 후 `PartialInvoiceModal` 자동 오픈. 발급 실제 호출은 모달 `afipService.issue`.
- 2차 진입: `facturarGateOn && lastSale` "Facturar venta #N" 버튼 → 같은 모달.
- 오프라인 인프라: `services/offline-mode.service.ts`(싱글턴, `isOffline()`, `subscribe()`),
  `components/OfflineBanner.tsx`. 네트워크오류 2회→클라우드 프로브→MODO SIN CONEXIÓN, 15초 복구 프로브.
- ★프린트/제브라 오프라인: `services/api.service.ts` 인터셉터가 이미 오프라인+edge 감지 시
  `POST /print/temp`(코만다), `POST /print/barcode`(라벨)을 edge `/api/offline/*` 로 우회.
  edge `server.js` 가 print-gateway 로 지점 print/zebra-agent 에 emit. → 코드 변경 불필요, 이미 동작.
  (edge 미지원 `/print/qr` 는 우회 대상 아님 — 그대로 둠.)

## 결정 (Locked)
- D1: 오프라인이면 F10 발급을 **하드 차단**한다. 판매를 잃지 않도록 "F2 로 완료, 복구 후 발급"을 안내(toast).
      F10 은 오프라인에서 판매를 완료하지 않는다(발급 전용 키이므로). 판매는 F2 로.
- D2: `PartialInvoiceModal` 은 2차 방어 — 모달 진입 후 단절돼도 Emitir/F10/Enter 를 차단하고 경고 Alert 표시.
- D3: "Facturar venta #N" 버튼은 오프라인 시 비활성 + 툴팁 안내.
- D4: 프린트/제브라는 기존 인터셉터 우회로 그대로 동작 — 변경 없음(회귀 방지).
- D5: 반응형 상태는 신규 훅 `hooks/useOfflineStatus.ts`(offline-mode.service 구독 래퍼)로 공유.

## 변경 파일
- 신규 `ventago-app/src/hooks/useOfflineStatus.ts` — 오프라인 상태 구독 훅.
- 수정 `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`
  — useOfflineStatus 사용, submitVentaConFactura 오프라인 가드, Facturar 버튼 disabled.
- 수정 `ventago-app/src/views/facturacion/PartialInvoiceModal.tsx`
  — onConfirm/keydown 오프라인 가드, 경고 Alert, Emitir 버튼 disabled.

## 검증
- [x] esbuild 구문 검사 3파일 통과.
- [ ] `npm run build`(Jenkins) 통과 — pool 무관(프론트).
- [ ] 실기: 오프라인 전환 후 (1) F10 → 발급 안 되고 toast, (2) F2 → 판매+코만다 인쇄(edge), (3) 제브라 라벨(edge),
      (4) Facturar 버튼 비활성, (5) 복구 후 F10 정상 발급.

## 비고 / 후속
- 프린트/제브라가 실제로 edge 로 failover 하려면 지점 print-agent·zebra-agent 가 edge 소켓에 접속해야 함(Phase 58 Wave B2).
  파일럿 PC 에서 에이전트 failover 접속을 함께 확인할 것.
- 오프라인 판매의 **후속 발급 전략**(CAEA / 전용 PV / 일마감 정합)은 별도 스펙 대상(이전 논의 참조).
