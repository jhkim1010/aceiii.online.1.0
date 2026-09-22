# 기능 점검표 2026-09-22 — 코드에서 뽑은 369항목

핸드오프 `HANDOFF-2026-09-22-…점검표·매뉴얼.md` §3 ①. 이 표가 ② AI 학습 자료 · ③ 고객 매뉴얼의 **유일한 근거**다 —
여기서 ✅ 가 아닌 것은 매뉴얼에 쓰지 않는다.

## 만든 방법

- **대상 목록은 기계로 뽑았다**: 운영 DB `apps`/`modules` 49행 · `navigation/menuRegistry.ts` ·
  `pages/configuracion/index.tsx`(허브 탭 16) · `views/reports-v2/registry.ts`(보고서 18) ·
  `views/tesoreria/tesoreriaTabs.ts`(4) · `views/talleres/components/constants.ts`(10) · `src/pages/**`(131).
- **항목은 코드를 읽어 채웠다**(영역별 4갈래). 모든 행에 `file:line` 근거가 있다. 경로는
  `ventago-app/src/` 기준(API 는 `api-ventago/src/`, 명시).
- 코드로 확인 못 한 동작은 "미확인" 으로 적었다 — 추측으로 채우지 않았다.

## 실측 열 범례

| 표시 | 뜻 |
|---|---|
| ⬜ | 아직 화면에서 확인 안 함 (코드 판독만) |
| ✅ | 운영 화면에서 기대 결과 확인 |
| ❌ | 화면에서 기대와 다름 — 옆에 실제 결과 |
| ⏭ | 운영에서 돌리면 안 되는 조작(판매 생성·카하 마감·삭제 등) — 코드 판독으로만 둔다 |

## 진입점이 없는 페이지 (131개 중 20)

메뉴·레지스트리·DB 모듈·앱 안 링크 어디에서도 참조되지 않는 페이지. 탐침은 `/tesoreria`(레지스트리에서만 참조)를
양성 대조군으로 잡는 것을 확인했다(첫 셈은 zsh 단어분리 실수로 무효 — 다시 셌다).

| 분류 | 페이지 |
|---|---|
| 정상 — 외부에서 들어온다 | `/401` `/404` `/500` · `/entrega/[token]`(주문 확인 링크) · `/m/stock`(라벨 QR) · `/admin/onboarding`(백엔드 링크) |
| 정상 — 허브 탭과 같은 화면의 단독판 | `/configuracion/envios` `/configuracion/inventario` `/configuracion/importar-legacy` |
| **여는 길이 없다** | `/verifica-correo` · `/reportes/asistencia` · `/configuracion/restaurante` · `/configuracion/categorias-gastos` · `/admin/permisos` · `/admin/store/setup-wizard` · `/admin/vto` · `/dashboards/stock`(내용도 텍스트 한 줄) · `/configuracion/carpetas-compartidas` · `…/logs` |

이 밖에 URL 로만 들어가는 **옛 화면**: `/reportes/*` 14개(새 보고서로 리다이렉트 안 됨) · `/talleres/{vendors,etapas,lotes,envios,orders,deliveries,defects,control,defect-codes,pedidos}` · `/ventas/detalle/[id]` · `/dashboards/ventas` · `/materia-prima/telas-madre`.

## ★ ② AI 학습 자료의 전제가 뒤집혔다 — 운영 AI 지식이 0건

- 운영 `knowledge_documents` **0행**. AI 도우미는 지금 근거 문서 없이 답한다.
- 파이프라인은 있다: `api-ventago/manuales/*.md` → `## 섹션` 단위 분할 → `knowledge_documents`
  (`source = manuales/<파일>.md#<slug>`, `store_id` NULL = 전 매장 공용). 부팅 1회 + 매일 03:00.
  (`src/app/chat/knowledge/manual-sync.service.ts`)
- 원인 (CODEX 가 바로잡음 — 처음엔 「폴더가 저장소에 없다」고 잘못 적었다): 원본 `.md` 11개는 **루트 저장소**
  `manuales/` 에 있었다. 그런데 운영은 api 저장소만 배포하고, `docker-compose.yml` 의
  `../manuales:/app/manuales:ro` 는 Jenkins 작업 폴더 부모의 **빈 폴더**(docker 가 4/30 생성)를 마운트했다.
  → **수정 완료(커밋 api `66d3a16b`)**: 원본을 `api-ventago/manuales/` 로 이동, 마운트 제거, 이미지 COPY,
  `.md` 0개면 빌드 실패. 배포 후 기대 ≈ 100행(`## ` 섹션 100 + 인트로).
- **배포 확인 (Jenkins api #927, 14:06 UTC)**: 빌드 검사 `manuales: 11 개 .md` 통과 · 마운트 제거 확인 ·
  리더 인수 14:08:38 뒤 동기화 `upsert=111` → **운영 `knowledge_documents` 103행**(전부 store_id NULL).
  111≠103 은 같은 파일 안 **제목이 같은 섹션**이 같은 source 로 덮인 것 — ② 에서 제목을 나눌 것.
- ★★ **그런데 AI 는 여전히 답하지 못한다**: 운영 컨테이너에 `LLM_PROVIDER`·API 키가 하나도 없어 기본값 Ollama
  (운영에 없음)로 간다 → 「El servicio de IA no está disponible… Ollama」. 운영 `chat_messages` 전체 6행 =
  질문 3건(3월·7월·9월) 전부 이 실패. **AI 도우미는 운영에서 한 번도 답한 적이 없다.**
  코드엔 claude/openai/groq/ollama 제공자가 있다(claude 는 `claude-sonnet-4-20250514` 고정).
- 검색은 키워드 ILIKE(3자 이상 단어, 상위 3건, 문서당 1500자) — 자료는 **섹션을 짧게, 사용자가 쓸 단어로** 써야 걸린다.
- 선행 수정: 아래 F2 의 `/chat/knowledge` 쓰기 권한 → **수정 완료(api `f36b3633`)**.

## 네 영역에 공통으로 나온 형태 (실측 우선순위)

하나씩이 아니라 **형태로** 센다 — 같은 형태가 영역마다 반복됐다.

| # | 형태 | 사례 (항목 ID / 이상 번호) |
|---|---|---|
| F1 | **권한이 메뉴에만 있다** — `WithAccess` 가 `allowedRoles` 와 판매원 차단 목록을 안 본다 | `/facturacion` · `/ventas-online` · `/cheques` · `/materia-prima/*` · 옛 `/talleres/*` · `/talleres/defect-codes`(게이트 0) · POS 단축키 F2/F10/Ctrl+S 가 `crear-venta` 무시 |
| F2 | **API 쪽 권한 — 코드로 재판정함** | ~~integration/toggle·status~~ 위협 아님: 운영 0행 · 상태를 읽어 허용하는 서버 코드 없음 · 타 매장은 테넌트 훅(enforce)이 막음. ~~legacy-import~~ 판독 오류: 세 엔드포인트 모두 `assertAdmin`. **남은 것 = `POST /chat/knowledge`·`sync-drive`·`sync-manuales` 가 역할 없는 `@Auth()`** (주석은 "superadmin용"). 공용 행(`store_id` NULL)은 `allowGlobalRows` 로 수정이 허용되므로 **KB 가 채워지는 순간 어느 매장 사용자든 전 매장 AI 근거를 덮어쓴다** — ② 착수 전 선행 수정. 현재 0행이라 지금은 피해 없음 |
| F3 | **눌러도 아무 일 없는 컨트롤** | 보고서 15개 내보내기 · `Ejecutar` 3개 · `/olvidaste-contrasena` · `/verifica-correo` · `Recordar cuenta` · Ctrl+R `Generar Factura`/`Editar Pago` · Lotes 표 `Cerrar` · `Nuevo Pedido` · `InventoryDialog` · TiendaNube 카드 |
| F4 | **틀린 값을 보여 준다** | Resumen de Caja 「Usuario」= 로그인한 사람 · 취소 확인창 COP · `/clientes-globales` 필터 페이지 로컬 · `Cerrar Caja` 후 칩 그대로 |
| F5 | **스페인어 화면의 한국어** | Ventas 보고서 · Permisos 탭 전체 · Tienda Online 카드 · QR 알림 · pedidos 배너 · 툴팁 |
| F6 | **입력 가로채기** | `Ctrl+V` 가 입력란 안에서도 `/fichaje-qr` 를 연다 → 붙여넣기 불가 가능성 |
| F7 | **비밀번호 취급** | 사용자 생성 폼이 비밀번호 포함 데이터를 console.log · `Repetir Contraseña` 불일치 미검증 |

---

## 1. 판매 (Venta)

| ID | 화면(경로) | 진입 | 조작 | 기대 결과 | 역할/조건 | 근거 | 실측 |
|---|---|---|---|---|---|---|---|
| V-01 | /nueva-venta | 사이드바에서 "Venta" 클릭 (defaultPath) | 화면 열기 | 소매 POS(VcontrolHome)가 표시됨. 식당 모드 매장이면 RestauranteShell이 대신 표시됨. StoreConfig 로드 전에는 스켈레톤 | module `nueva-venta`, app `venta`, `useRestaurantMode` | pages/nueva-venta/index.tsx:20-35; navigation/menuRegistry.ts:258 | ⬜ |
| V-02 | /nueva-venta | 같음 | 열린 caja 없이 진입 | `POST /cash-register/auto-open` 자동 호출. 실패하면 toast "No se pudo abrir la caja automáticamente: …" | 선택 지점 필요 | PL:445-475 | ⬜ |
| V-03 | /nueva-venta | 같음 | "Buscar SKU"에 입력 → Enter 또는 + 버튼 | 카트에 행이 추가되고 "Cantidad (F8)"로 커서 이동 | 가격 유형 선택 필요 | PI:793, 883-890, 606-615 | ⬜ |
| V-04 | /nueva-venta | 같음 | "Agregar" → "Autorización de Gerente/Administrador"에서 Usuario/Contraseña 입력 → "Autorizar" | `POST /auth/verify-admin-credentials` 성공 시 버튼이 "Autorizado"로 바뀌고 "Precio" 입력 가능. 실패 시 "Credenciales inválidas o sin permisos" | 관리자 자격증명 | PI:131-157, 848, 895-955 | ⬜ |
| V-05 | /nueva-venta | 같음 | "Tipo de precio" 선택 | 가격 유형 변경. 권한이 없으면 컨트롤이 보이지 않음 | functionSlug `elegir-tipo-de-precio` | PI:866-880 | ⬜ |
| V-06 | /nueva-venta | 같음 | SKU 칸을 비운 채 Tab → 코드(`tmp001` 제안)·"Nombre del producto"·"Precio" 입력 → + | tmp 모드로 들어가 코드 없는 상품(generic, customName)이 카트에 추가됨. X 버튼 또는 코드를 비우면 SKU 모드로 복귀. generic이 없으면 "Producto genérico no configurado" | 매장 generic 상품 필요 | PI:115, 318-385, 401-416, 656-735 | ⬜ |
| V-07 | /nueva-venta | 같음 | SKU에 `dp` 입력 → Enter → "Cobro de deuda"에서 "Importe a cobrar"·"Nº de recibo" 입력 → "Agregar cobro" | "dpago — Deuda pago" 안내 후 회수 줄이 카트에 추가됨. 이후 상품을 추가하면 "Estás cobrando una deuda…" 오류 | cuenta corriente 고객 선택 + 빈 카트. Fallados/Movidos 모드에서는 불가 | PI:394-409, 622-652; PL:724-790; …/DeudaPagoDialog.tsx:81-156 | ⬜ |
| V-08 | /nueva-venta | 같음 | 카트 행 휴지통 클릭 / 수량·가격 편집 | 행 삭제 또는 갱신. 회수 줄은 편집 대신 "Para cambiar el importe del cobro…" 표시 | - | …/ProductListTable.tsx:100; PL:2562-2612 | ⬜ |
| V-09 | /nueva-venta | 같음 | Info de Cliente의 문서 칸에 8자리 또는 11자리 입력 | 매장 고객이 있으면 자동 선택 + "Cliente ya registrado — seleccionado automáticamente". 없으면 글로벌 고객에서 채움 + "Datos copiados desde Clientes Globales" | - | views/homes/components/InfoClient.tsx:285-341 | ⬜ |
| V-10 | /nueva-venta | 같음 | 문서 칸을 비운 채 Tab | `GET /clients/next-temp-document` 결과로 임시 문서번호가 채워짐 | 고객 미선택 | InfoClient.tsx:402-420 | ⬜ |
| V-11 | /nueva-venta | 같음 | 확장 폼에서 "Nuevo" / "Editar" | `POST /clients` → "Cliente creado exitosamente". `PUT` → "Cliente modificado exitosamente" | `crear-cliente-en-venta` / `editar-cliente-en-venta` | InfoClient.tsx:513-586, 1155-1191 | ⬜ |
| V-12 | /nueva-venta | 같음 | 고객 카드의 "Desvincular cliente", "Editar cliente", 현금 아이콘, 트럭 아이콘 | 고객 해제·편집. 현금 아이콘은 `/cuentas-corrientes/{storeClientId}`로 이동(외상 잔액 > 0일 때만 표시). 트럭 아이콘은 `/ventas-online?search={doc}`로 이동(미배송 주문이 있을 때만 표시) | 카드 표시 조건은 괄호 안 참고 | InfoClient.tsx:700-715, 814-851 | ⬜ |
| V-13 | /nueva-venta | 같음 | F3 → "Búsqueda (F3)"에 입력, "Deudores"/"Reservadores" 체크, 행 클릭 | 검색칸 포커스 → 목록 필터 → 고객 선택 | - | …/ClientList/components/ClientFilters.tsx:25-28, 143-174; …/ClientList/ClientList.tsx:25, 68 | ⬜ |
| V-14 | /nueva-venta | 같음 | F2 또는 "Generar Venta (F2)" | `POST /sales` (Idempotency-Key) → "Venta creada exitosamente". 복원한 보류판매는 DELETE. 이름만 입력돼 있으면 `POST /clients/temp`로 "Cliente temporal creado". 버튼이 비활성일 때 툴팁: "Debes seleccionar una caja y una terminal" 또는 "Los pagos no cubren el total…" | `crear-venta`, 결제합계 = 총액, caja·terminal 필요 | PL:299-300, 1345-1365, 1880-1923, 2115-2120, 2663, 2757-2784 | ⬜ |
| V-15 | /nueva-venta | 같음 | Alt+F2 또는 Alt+클릭 → 날짜 선택 → "Confirmar venta · {fecha}" | "Registrar venta con otra fecha" 다이얼로그 → 해당 날짜 12:00으로 판매 등록 | V-14와 같음 | PL:2093-2112, 2800-2830 | ⬜ |
| V-16 | /nueva-venta | 같음 | F10 | 판매 완료 후 "Facturar venta #N" 모달이 매장 기본 %로 열림. 오프라인이면 "Sin conexión: no se puede facturar…", FE가 꺼져 있으면 "Facturación electrónica no habilitada", PV가 없으면 "No hay punto de venta AFIP configurado" | `useFacturaElectronica` + AFIP 발행자 | PL:196-201, 1928, 2123-2158, 2886-2905 | ⬜ |
| V-17 | /nueva-venta | 같음 | Ctrl+F12 (맨 F12 아님) | V-16과 같지만 100% 고정(pctFijo)으로 열림. 맨 F12는 POS 동작 없음 | V-16과 같음 | PL:2160-2179, 2888-2892 | ⬜ |
| V-18 | /nueva-venta (발급 모달) | F10 또는 Ctrl+F12 | %/Emisor/"Provincia del comprador" 선택, "Térmica"/"PDF A4"/"WhatsApp"/"Email" 체크 → "Emitir (F10) →" 또는 "Omitir (Esc)" | `POST /afip/vouchers`로 발급 → "Listo (Enter)". Omitir 시 판매는 유지되고 미발급 상태로 남음 | provincia·채널 필요, 온라인 상태 | views/facturacion/PartialInvoiceModal.tsx:145, 416-576; services/afip.service.ts:19-20 | ⬜ |
| V-19 | /nueva-venta | 같음 | F9 | 결제가 Efectivo 100%로 바뀌고 toast "Efectivo — 100% (…)" 표시 | - | IA:219-238, 259-269 | ⬜ |
| V-20 | /nueva-venta | 같음 | PgUp | Crédito 100%로 설정. 불가하면 이유 toast만 뜨고 변경 없음. 후보가 여럿이면 info toast + 결제 모달 | 고객 + creditStatus `active` | IA:198-257; views/homes/utils/pago-rapido.ts | ⬜ |
| V-21 | /nueva-venta | 같음 | PgDn | Banco 100%로 설정 (불가 시 V-20과 같은 방식) | - | IA:271-280 | ⬜ |
| V-22 | /nueva-venta | 같음 | Ctrl+F9 또는 "Pagos" 칩 클릭 | "Agregar Métodos de Pago" 모달이 열림 (이미 열려 있으면 유지) | - | IA:86-97, 343-359; PSM:725-727 | ⬜ |
| V-23 | /nueva-venta (결제 모달) | V-22 | 수단 + 금액 → "+" → "Aceptar" 또는 F11 | 행 추가. 잔액 초과 시 "Por favor, selecciona un método de pago válido…". Cheque는 "Banco *"·"Nº de cheque *" 필수. "Aceptar"는 지불합계 = 총액일 때만 활성 | - | PSM:505-548, 658-662, 910-916, 1126-1131 | ⬜ |
| V-24 | /nueva-venta (결제 모달) | V-22 | 고객을 선택한 상태로 모달 열기 | credito는 creditStatus `active`일 때만, favor는 favorBalance > 0일 때만 표시. 비활성이면 "Cliente con estado de crédito: X" 경고 | storeClientId | PSM:232-240, 325-342 | ⬜ |
| V-25 | /nueva-venta | 같음 | "MercadoPago" 칩 → (모달) QR 대기 → "Cancelar QR" | MP 100% 설정 → `POST /mercadopago/qr`로 QR 표시 → 승인 시 "✓ Pago Mercadopago recibido — generando venta". 취소 시 `DELETE /mercadopago/qr/:id`. 칩을 다시 누르면 Efectivo로 복귀 | 활성 MP 계정 + terminal | IA:360-399; PSM:419, 455-492; …/McdpgQrPanel.tsx:187 | ⬜ |
| V-26 | /nueva-venta (결제 모달) | V-22 | Internet(Envío) 수단 선택 → "Registrar pedido online" → "Confirmar envío" | `POST /online-orders/from-pos` → "Nueva venta" 또는 "Ver en despacho"(`/ventas-online`로 이동). 카트 초기화 | 고객 필수 | PSM:1108-1123, 1141-1156; …/EnvioRegistroModal.tsx:290, 311, 470-497 | ⬜ |
| V-27 | /nueva-venta | 같음 | "Descuentos" + → 이름·값·$/% → ✓ / 칩 X | 빨간 칩 "-$…" 추가 또는 삭제, 총액 재계산 | - | IA:402-481 | ⬜ |
| V-28 | /nueva-venta | 같음 | "Recargos" + → ✓ / 칩 X | 주황 칩 "+$…" 추가 또는 삭제 | - | IA:483-548 | ⬜ |
| V-29 | /nueva-venta | 같음 | "Transporte" 금액 → + / 요약의 X | 요약에 "Transporte:" 행 추가, 입력칸은 숨겨짐. X로 0으로 되돌림 | - | IA:550-563; …/PaymentSummary.tsx:224-229 | ⬜ |
| V-30 | /nueva-venta | 같음 | Ctrl+S 또는 "Suspender (Ctrl+S)" | `POST /suspended-sales` (복원 중이면 `PUT`) → "Venta suspendida correctamente", 카트 비움. 빈 카트면 "Agrega al menos un producto.". 회수 줄이 있으면 거부 | - | PL:1367-1480, 2204-2207, 2694-2700 | ⬜ |
| V-31 | /nueva-venta | 같음 | "Ventas Suspendidas" 행 클릭 / 휴지통 | 카트로 복원 (다른 보류판매 편집 중이면 자동 재보류 + "Venta anterior guardada en suspendidas"). 삭제 시 `DELETE` → "Venta suspendida eliminada". 모바일 도착 시 toast "Nueva venta en espera desde el móvil" | `ver-facturas-con-deudas` | views/homes/components/DraftAndDebtors/DraftAndDebtorsList.tsx:64, 89, 104-114, 199-230, 385-386; …/DraftAndDebtors/components/DataConfig.tsx:155-165 | ⬜ |
| V-32 | /nueva-venta | 보류판매 복원 상태 | ESC | confirm "¿Eliminar esta venta suspendida?": Aceptar → DELETE + "Venta suspendida eliminada", Cancelar → 재보류 | 모달이 열려 있지 않을 때 | PL:2213-2240 | ⬜ |
| V-33 | /nueva-venta | 같음 | ESC (모달 없음) 또는 리셋 아이콘 | 카트·결제·고객 초기화 + "Contexto de venta borrado" | - | PL:2049-2067, 2634-2641 | ⬜ |
| V-34 | /nueva-venta | 같음 | "Imprimir Temp" / "Temp s/ precio" | `POST /print/temp`로 견적 티켓 → "Presupuesto enviado al print-agent" (가격 없는 버전은 경고 toast가 뜰 수 있음). 지점을 못 찾으면 "No se pudo resolver la sucursal. ¿Caja abierta?" | 카트 1행 이상, `crear-venta` | PL:2276-2360, 2665-2692 | ⬜ |
| V-35 | /nueva-venta | 같음 | "auto impTiq" 체크 후 판매 | 판매 후 `/print/temp` 자동 인쇄. comandera 상태 pill 🟢/🟡 "Sin asignar"/🔴 "Sin comandera". print-agent가 없으면 체크박스 disabled | 온라인 thermal agent | PL:546, 1930-2033, 2701-2756 | ⬜ |
| V-36 | /nueva-venta | 같음 | "Fallados" / "Movidos" (Origen→Destino) / "Devolver Ropas" 또는 Ctrl+E → "Registrar Fallados"/"Registrar Movimiento"/"Registrar Devolución" | 모드끼리 상호 배타이고, 켜면 카트가 비워짐 → `POST /stocks/movement` | Movidos는 지점 2개 이상일 때만 표시 | PL:665-685, 821-1063, 2408-2512, 2645-2661 | ⬜ |
| V-37 | /nueva-venta | 같음 | "QMode" 체크 또는 Ctrl+Q | SKU 입력 시 자동 매칭 + 자동 추가 | - | PL:2200, 2400-2406; PI:418-420 | ⬜ |
| V-38 | /nueva-venta | 같음 | F7 / F8 | Vendedor 필드 포커스 / "Cantidad" 포커스 + 전체 선택 | - | PL:2182-2197 | ⬜ |
| V-39 | /nueva-venta | 같음 | Ctrl+R → ←/→ 이동, 번호 입력 후 Enter → "Ticket" / "Duplicar" / "Anular" | 당일 판매 Repaso 패널 (`GET /sales/all`). Ticket은 `/print/temp`. Duplicar는 카트에 복사 + "Venta duplicada en el formulario". Anular는 confirm 후 `POST /sales/:id/nullify` + "…anulada correctamente" (이미 취소된 판매는 버튼 disabled) | - | views/homes/VcontrolHome.tsx:97-100, 328-330; views/homes/components/SaleReview/SaleReviewPanel.tsx:85, 172-228, 297-311, 405-415, 670-697 | ⬜ |
| V-40 | /nueva-venta | /ventas의 "Modificar venta" (`?editSale=id`) | 수정 후 F2 → "Guardar cambios" / "Anular y registrar nueva" / "Cancelar modificación" | 칩 "Modificando venta #N"과 "Sin promociones automáticas" 표시 → `POST /sales/:id/modify/preview` → "Confirmar modificación" 또는 "⚠ Esta venta se reemplaza" → `POST /sales/:id/modify` | `modificar-venta` | views/homes/hook/SaleEditLoader.tsx:47-194; PL:1794-1830, 2371-2399, 2836-2882 | ⬜ |
| V-41 | /nueva-venta | 같음 | 상태가 hold/blocked인 고객 선택 | 칩 "EN REVISIÓN" / "BLOQUEADO" 표시 | credit status | views/homes/components/CreditBadges.tsx:156-177 | ⬜ |
| V-42 | /ventas-online | Venta > Ventas Online (injectStart) | 화면 열기 | `useEnvios`=true: "Operarios"·"Dispositivos" + 탭 Despacho/Cuentas por cobrar/Historial. false: KPI 4개 + 탭 Pedidos/Envíos/Devoluciones | store `useEnvios`. 페이지에 WithAccess 없음 | views/ventas-online/VentasOnlineView.tsx:143-151, 165-213, 240-304; navigation/menuRegistry.ts:263-265; pages/ventas-online/index.tsx | ⬜ |
| V-43 | /ventas-online (Despacho) | 같음 / POS 트럭 아이콘 | "Buscar cliente / pedido / tracking" 입력 | 보드 필터. `?search=`가 있으면 자동으로 채워짐 | - | DB:138-141, 566 | ⬜ |
| V-44 | /ventas-online (Despacho) | 같음 | "Sucursal" 선택 (Todos 포함) | 지점 전환. 선택이 없으면 "El tablero requiere seleccionar una sucursal." | 지점 2개 이상 | DB:583-614 | ⬜ |
| V-45 | /ventas-online (Despacho) | 같음 | 카드의 "Preparar" / "Marcar listo" / "Marcar entregado" | `PATCH /online-orders/:id/prepare`·`mark-ready`·`deliver` → "Movido a Preparando" 등 | - | DB:75-77, 443-457, 1382-1393 | ⬜ |
| V-46 | /ventas-online (Despacho) | 같음 | listo 카드 "Despachar" → "Transporte"·"Código de tracking del transporte" 입력 | `PATCH /online-orders/:id/ship`. 누락 시 "Seleccioná un transporte" / "Ingresá el código de tracking" | - | DB:403-436, 726-790, 1370-1380 | ⬜ |
| V-47 | /ventas-online (Despacho) | 같음 | "Revertir a la etapa anterior" → "Revertir" | `PATCH …/revert` → "Pedido revertido a la etapa anterior" | en_transito이면서 saldo > 0이면 아이콘 숨김 | DB:519-528, 907-946, 1152, 1208-1216 | ⬜ |
| V-48 | /ventas-online (Despacho) | 같음 | "Cancelar pedido" 아이콘 | 결제된 금액이 있으면 "Cancelar — dejar a favor del cliente", 없으면 "Cancelar pedido" → `PATCH …/cancel` → "Pedido cancelado" | 취소 가능한 컬럼만 | DB:485-510, 1223-1231; views/ventas-online/components/CancelPedidoDialog.tsx:49-77 | ⬜ |
| V-49 | /ventas-online (Despacho) | 같음 | "Resolver reclamo" → "Resolver" | `PATCH …/disputa/resolver` → "Reclamo resuelto" | 분쟁 카드 | DB:365-372, 860-900, 1264 | ⬜ |
| V-50 | /ventas-online (Despacho) | 같음 | "Archivar entregados" → "Archivar" | `POST /online-orders/board/clear-delivered` (Historial에는 남음) | 역할 admin/gerente/superadmin | DB:343-357, 543-547, 692, 828-852, 1037 | ⬜ |
| V-51 | /ventas-online (Despacho) | 카드 선택 | 우측 패널 "Ticket" / "Recibo" / "Registrar cobro" / "Cancelar pedido" / 📝 Nota | `/print/temp`. `POST …/cobro` → "Cobro registrado". `POST …/nota` → "Nota agregada" | cobro는 saldo > 0, cancel은 취소 가능 상태 | views/ventas-online/components/EnvioTimeline.tsx:242, 280-316, 445-510; …/components/CobroModal.tsx:242-253, 431-440 | ⬜ |
| V-52 | /ventas-online (Despacho) | 같음 | 카드 QR 아이콘 | "Confirmación del cliente — #N" + `GET …/confirm-link`, 복사 시 "Enlace copiado" | - | DB:690, 817; …/components/ConfirmLinkQrModal.tsx:42-93 | ⬜ |
| V-53 | /ventas-online (Cuentas por cobrar) | 탭 | 행의 "Registrar cobro", 페이지 이동 | CobroModal 열림 | - | views/ventas-online/CuentasPorCobrarTab.tsx:210-245 | ⬜ |
| V-54 | /ventas-online (Historial) | 탭 | "Desde"/"Hasta" | 종료된 주문 기간 조회 | - | views/ventas-online/HistorialTab.tsx:78-86 | ⬜ |
| V-55 | /ventas-online | 같음 | "Dispositivos" → "Nombre del dispositivo" 입력 후 생성, 토큰 복사, 활성/비활성 | `POST /despacho/devices` → "Dispositivo creado — copiá el token". `PUT`으로 토글 | `useEnvios` | views/ventas-online/components/DispositivosModal.tsx:70-95, 117-189 | ⬜ |
| V-56 | /ventas-online | 같음 | "Operarios" → 이름 + PIN으로 생성, 토글 | `POST /despacho/operarios`. PIN 오류 시 "Nombre y PIN (4 a 6 dígitos) requeridos" | `useEnvios` | views/ventas-online/components/OperariosModal.tsx:49-88 | ⬜ |
| V-57 | /ventas-online (레거시) | 같음 | 행 클릭 | `/ventas-online/[id]`로 이동 | `useEnvios`=false | VentasOnlineView.tsx:246-248 | ⬜ |
| V-58 | /ventas-online/[orderId] | V-57 | "Confirmar pedido" / "Iniciar preparación" / "Marcar como enviado" (Transporte·Código de tracking) / "Marcar como entregado" | `PATCH …/confirm`·`prepare`·`ship`·`deliver` | status가 각각 pending / confirmed / confirmed·preparing / shipped | views/ventas-online/OrderDetailView.tsx:112-130, 452-495, 527-555 | ⬜ |
| V-59 | /ventas-online/[orderId] | 같음 | "Registrar devolución" → "Motivo"·"Detalle"·"Monto a reembolsar" 입력 | `POST /online-orders/:id/return` | shipped / delivered | OrderDetailView.tsx:160, 496-505, 560-600 | ⬜ |
| V-60 | /ventas-online/[orderId] | 같음 | "Cancelar pedido" / 뒤로 아이콘 | CancelPedidoDialog 열림 / `/ventas-online`로 이동 | 취소 가능 상태 | OrderDetailView.tsx:191, 204, 508-515 | ⬜ |
| V-61 | /ventas | Venta > "Historial de ventas" | 화면 열기 | 판매 목록 + 요약 표 + DailySalesStats | `ver-ventas`, module `ventas` | navigation/menuRegistry.ts:114; views/sales/list/SalesListView.tsx:663; pages/ventas/index.tsx | ⬜ |
| V-62 | /ventas | 같음 | "Hoy"/"Ayer"/"Esta semana"/"Este mes"/"Custom", 날짜, caja, terminal 선택 | `GET /sales/all` 재조회 | - | views/sales/list/components/SalesListToolbar.tsx:235-290; SalesListView.tsx:287 | ⬜ |
| V-63 | /ventas | 같음 | 결제수단, "Movidos"/"Fallados", "Crédito", "Internet (Envío)" 체크, "Cliente..." 입력 | Internet이 켜져 있으면(기본값 ON) `GET /online-orders/venta-vista` 결과가 병합됨 | "Tienda..."는 superadmin만 | SalesListToolbar.tsx:305-400; SalesListView.tsx:142, 152, 303-326 | ⬜ |
| V-64 | /ventas | 같음 | 요약 표 행/셀 클릭 → 칩 X, "Quitar filtros", "Limpiar filtros" | 지점/활동 칩(MOV+, MOV−, FAL…) 적용·해제. 필터가 걸려 있으면 Alert "Lista filtrada…" 또는 "Sin resultados…" | - | SalesListView.tsx:457, 710-775; SalesListToolbar.tsx:407 | ⬜ |
| V-65 | /ventas | 같음 | 눈 아이콘 "Ver Venta" / "Ver Envío" | 우측 패널에 판매 상세 (`GET /sales/:id`) 또는 온라인 주문 상세 (`GET /online-orders/:id`) | `detalle-de-venta` | SalesListView.tsx:612-633; …/components/SaleDetailPanel.tsx:44; …/components/OnlineOrderDetailPanel.tsx:83 | ⬜ |
| V-66 | /ventas (상세 패널) | V-65 | "Imprimir" / "🔄 Reintentar devolución" | 브라우저 `window.print()`. MP 환불 실패 시 `POST /mercadopago/refunds/:saleId/retry` → "✓ Devolución Mercadopago completada" | MP 환불 실패 이력이 있을 때 | SaleDetailPanel.tsx:208-232; views/mercadopago/components/McdpgRefundFailureSection.tsx:101-112, 199-208 | ⬜ |
| V-67 | /ventas | 같음 | "Reimprimir ticket" | `POST /sales/:id/reprint` → "✓ Ticket enviado al print-agent" 또는 "No se pudo reimprimir: …" | activityType=sale 행만 | SalesListView.tsx:578-590, 634-640 | ⬜ |
| V-68 | /ventas | 같음 | "Facturar (AFIP)" | PartialInvoiceModal(V-18) 열림. 발급 후 목록이 갱신되고 버튼이 사라짐 | FE on + 발행자 존재 + 발급 대상 | SalesListView.tsx:566-574, 641-646; views/sales/list/facturable.ts | ⬜ |
| V-69 | /ventas | 같음 | "Modificar venta" | `/nueva-venta?editSale=id`로 이동 (V-40) | `modificar-venta`. internet·movido·fallado·Anulado 행에는 없음 | SalesListView.tsx:597-610, 648-655 | ⬜ |
| V-70 | /ventas | 같음 | 취소/환불 버튼 찾기 | 이 화면에는 Anular 버튼이 없음. 취소는 POS의 Ctrl+R "Anular"(V-39) 또는 Modificar(replace)로만 가능 | - | SalesListView.tsx:612-658 | ⬜ |
| V-71 | /ventas/detalle/[id] | URL 직접 입력 (코드상 진입 링크 없음) | 화면 열기 → "Reimprimir Ticket" / "Volver a Ventas" | `GET /sales/:id`로 상세 + MP 환불 섹션 표시. `POST /sales/:id/reprint`. `/ventas`로 복귀 | module `ventas` | views/sales/details/SalesDetailView.tsx:31, 98-110; views/sales/details/components/ActionButtons.tsx:20-72; SaleDetailPanel.tsx:13 | ⬜ |
| V-72 | /facturacion | Venta > "Facturación AFIP" | 화면 열기 | 툴바 + Verificar/Notas/IIBB/Emitidas 패널 | 메뉴는 supervisorRoles(PRIVILEGED + gerente + branch_manager)만. 페이지 자체는 app `venta`만 확인 | navigation/menuRegistry.ts:271; configs/roles.ts:35-39; pages/facturacion/index.tsx:17; views/facturacion/FacturacionShell.tsx:19-50 | ⬜ |
| V-73 | /facturacion | 같음 | "⚙ Configuración" → 로고 업로드 / "Generar logo" / PV "Editar"·"Guardar"·"Eliminar" | IssuerConfig로 전환. `PUT /store/:id`(파일), `POST`·`PUT /afip/issuers`, `DELETE /afip/issuers/:id` | - | FacturacionShell.tsx:29-37; views/facturacion/IssuerConfig.tsx:30-195; services/afip.service.ts:53-56 | ⬜ |
| V-74 | /facturacion | 같음 | "Punto de venta" 선택, "ver en Ventas →", "Recargar", "Mandar a AFIP automático", "Imprimir x comandera térmica" 스위치 | Emitidas 필터링 / "Fallaron en ARCA: N" + 사유 툴팁 / `/ventas`로 이동 / store 플래그 저장 toast | - | views/facturacion/FacturacionToolbar.tsx:60-146 | ⬜ |
| V-75 | /facturacion | 같음 | "Diagnosticar" → "Liberar para facturar" / "Adjuntar a esta venta" | `GET /afip/vouchers/:id/diagnostico`, `POST …/resolver` (liberar / adjuntar) | 확인이 필요한 판매가 있을 때 | views/facturacion/VerificarPanel.tsx:43-160; afip.service.ts:28-34 | ⬜ |
| V-76 | /facturacion | 같음 | NotasPendientes "Liberar" | `POST /afip/notas/reservas/:id/liberar` | 대기 중인 노트가 있을 때 | views/facturacion/NotasPendientesPanel.tsx:67-86; afip.service.ts:50-51 | ⬜ |
| V-77 | /facturacion | 같음 | "Mes" → "Ver" / "Descargar Excel" / "Generar Reportajes por ARCA" → "Generar Excel" / "Generar IVA Digital" | `GET /afip/iibb`, xlsx 다운로드, ARCA 파일 생성 toast | - | views/facturacion/IibbPanel.tsx:45-98; views/facturacion/ReportesArcaModal.tsx:50-116 | ⬜ |
| V-78 | /facturacion | 같음 | Emitidas "Buscar cliente…", 🖨️, "PDF", "NC"/"ND" → "Emitir" | reprint / PDF / `POST /afip/vouchers/:id/nota-credito`·`nota-debito`. 이미 있으면 "NC emitida"/"ND emitida" 표시 | - | views/facturacion/EmitidasPanel.tsx:84-200; views/facturacion/NotaModal.tsx:43-61; afip.service.ts:36-44 | ⬜ |
| V-79 | /cuentas-corrientes | Venta > Cuentas corrientes | aging 카드, "Buscar nombre o documento...", 행 → "Ver ledger del cliente" | `GET /credit/reports/aging`, top-debtors 조회 → `/cuentas-corrientes/:id`로 이동 | app `venta` | views/cuentas-corrientes/CuentasCorrientesView.tsx:44-74, 134, 208; hooks/api/useCreditAging.ts:24 | ⬜ |
| V-80 | /cuentas-corrientes/[clientId] | V-79 또는 POS 현금 아이콘 | 화면 열기 / "Volver a la lista" | summary + ledger (`/credit/clients/:id/summary`, `…/ledger`) | - | views/cuentas-corrientes/ClientLedgerView.tsx:59-66, 110-111; hooks/api/useCreditClientSummary.ts:29 | ⬜ |
| V-81 | /cuentas-corrientes/[clientId] | 같음 | "Registrar pago" → "Pago de deuda (FIFO)" 또는 "Adelanto / saldo a favor", "Monto", "Método de pago", "N° de recibo" | `POST /credit/payments` → "Pago de $X registrado." 누락 시 경고 toast | 잔액 > 0일 때만 버튼 활성 | ClientLedgerView.tsx:143-150; views/cuentas-corrientes/CreditPaymentModal.tsx:76-110, 140-206 | ⬜ |
| V-82 | /cuentas-corrientes/[clientId] | 같음 | "Reservar Seña" | `POST /credit/senias` → "Seña de $X registrada." | creditStatus ≠ blocked | ClientLedgerView.tsx:134-141; views/cuentas-corrientes/SeniaRegisterModal.tsx:67-105 | ⬜ |
| V-83 | /cuentas-corrientes/[clientId] | 같음 | ledger 행 "Cancelar Seña" → Acción(refund/to_favor) | `POST /credit/senias/cancel` | SENIA_RESERVE + relatedSaleId | ClientLedgerView.tsx:283-296; views/cuentas-corrientes/SeniaCancelDialog.tsx:39-116 | ⬜ |
| V-84 | /cuentas-corrientes/[clientId] | 같음 | "Política" → "Límite de crédito"/"Plazo de pago (días)"/"Estado" | `PATCH /credit/policy/:id` → "Política actualizada." | UI 역할 제한 없음 (서버 쪽 미확인) | ClientLedgerView.tsx:126-133; views/cuentas-corrientes/CreditPolicyModal.tsx:55-168 | ⬜ |
| V-85 | /cliente-vista | 사이드바 (DB 모듈 기반, 코드 하드코딩 없음 → 미확인) | 칩 "Todos"/"Activos"/"Eliminados" (기본 Activos) | 서버가 필터: `GET /clients?estado=`. 카드 Total/Activos/Eliminados | module `cliente-vista` | pages/cliente-vista/index.tsx:11; views/cliente-vista/ClienteVistaView.tsx:148-154, 243-262, 591-645 | ⬜ |
| V-86 | /cliente-vista | 같음 | "Buscar cliente..." / "Nuevo Cliente" / 편집 아이콘 → "Crear"·"Actualizar" | 검색 결과 표시. `POST /clients` / `PUT /clients/:id` | `crear-cliente` / `editar-cliente` | ClienteVistaView.tsx:345-351, 533-546, 651, 716-720, 776-890 | ⬜ |
| V-87 | /cliente-vista | 같음 | "Desactivar cliente" → "Desactivar" | `DELETE /clients/:id` → `Cliente "X" desactivado.` 이후 Eliminados에 표시 | `eliminar-cliente` | ClienteVistaView.tsx:547-577, 897-913 | ⬜ |
| V-88 | /cliente-vista | 같음 | WhatsApp 아이콘 | WhatsAppSendDialog 열림 | whatsapp 값이 있고 isActive일 때 | ClienteVistaView.tsx:505-525, 916-930 | ⬜ |
| V-89 | /cliente-vista | 같음 | 행 선택 후 "Enviar Campaña (n)" / "Carga Masiva" | `/clientes-globales/campanas?clients=ids` / `/clientes-globales/carga-masiva`로 이동 | `enviar-campana` / `manage-clientes-import` | ClienteVistaView.tsx:229-237, 664-705 | ⬜ |
| V-90 | /clientes-globales | URL 또는 대시보드 "Clientes" 카드 | "Todos"/"Activos"/"Inactivos", "Buscar cliente...", "Nuevo Cliente", "Editar" | `GET /global-clients`. 필터는 현재 페이지 안에서만 적용됨. `POST`/`PUT /global-clients` | `crear-cliente-global` / `editar-cliente-global` / `carga-masiva-clientes` | views/clientes-globales/GlobalClientesView.tsx:105-142, 199-201, 319-416 | ⬜ |
| V-91 | /clientes-globales/carga-masiva | V-89 / V-90 (사이드바에서 숨김) | "Descargar Plantilla" → "Seleccionar Archivo" (.csv/.xlsx/.xls) → "Editar Mapeo" / "Atrás" → "Iniciar Carga" | 3단계 Stepper → `POST /clients/import` 청크 전송 → Creados/Actualizados/Saltados/Errores → "Nueva Carga" / "Ver Clientes" | module `clientes-import` 또는 `cliente-vista` | pages/clientes-globales/carga-masiva/index.tsx; views/clientes-globales/CargaMasivaClientesView.tsx:290, 353, 456-635, 680-780; navigation/menuRegistry.ts:133 | ⬜ |
| V-92 | /clientes-globales/import-history | carga-masiva의 "Historial" (유일한 진입점) | "Recargar" | `GET /clients/import/history` 목록 | `view-clientes-import-history` | CargaMasivaClientesView.tsx:442-452; views/clientes-globales/ImportHistoryView.tsx:64, 185-186 | ⬜ |
| V-93 | /clientes-globales/campanas | V-89 | "Nueva campaña" → Canal/Contenido/Audiencia/Revisar y enviar → "Encolar y enviar" | `GET /campaigns` 이력. `preview-count`. `POST /campaigns` + `/enqueue` → "Campaña encolada — N destinatarios…". `?clients=`로 들어오면 audience='selected' | app `venta` | views/campanas/CampanasView.tsx:59-102, 218-270; views/campanas/CampaignWizard.tsx:40, 72-73, 93, 179-190, 448-490 | ⬜ |
| V-94 | /dashboards/ventas | URL 직접 (Venta 메뉴에서 제외) | 화면 열기 | `GET /dashboards/sales/summary` 카드 (Gastos del día / Descuentos / Facturas pendientes / Clientes) + Ventas del día / Ingresos del día / Últimas ventas / Productos más vendidos | module `dashboard-venta` | navigation/menuRegistry.ts:260; views/dashboards/ventas/DashboardsSalesView.tsx:32, 76-120; …/components/LastSalesCard.tsx:29; …/components/TopSoldProductsCard.tsx:27 | ⬜ |
| V-95 | /dashboards/ventas | 같음 | "Clientes" 카드 클릭 | `/clientes-globales`로 이동 (매장 고객이 아닌 글로벌 고객 목록) | - | DashboardsSalesView.tsx:111 | ⬜ |

### 1. 판매 (Venta) — 코드 판독에서 나온 이상 (미실측)

**이상 징후 (Anomalies)**
1. **죽은 버튼, 클릭 시 "próximamente" toast만 뜸**: POS의 Repaso(Ctrl+R) 패널에서 "Generar Factura" → `'Factura: próximamente'`, "Editar Pago" → `'Editar Pago: próximamente'`. `views/homes/components/SaleReview/SaleReviewPanel.tsx:418-422, 679-684`
2. **/ventas/detalle/[id]의 죽은 코드**:
   - 이 판매 상세 화면에 매장 편집 모달(`ModalStore`)과 사용자 편집 모달(`ModalUser`)이 붙어 있습니다.
   - 둘을 여는 `onEdit`를 `ActionButtons`가 `void onEdit`로 버려서 열 방법이 없습니다.
   - 이 라우트로 들어오는 링크도 코드 전체에 없습니다. `views/sales/details/SalesDetailView.tsx:46-47, 113-131`; `views/sales/details/components/ActionButtons.tsx:18`; `views/sales/list/components/SaleDetailPanel.tsx:13`
3. **렌더링되지 않는 코드**:
   - `PaymentSummary.tsx`의 `handlePrintTemp`에 연결된 버튼이 없습니다. `…/ProductList/components/PaymentSummary.tsx:129-176`
   - 쓰이지 않는 파일: `DraftAndDebtors/components/SalesFilters.tsx`, `ventas-online/ReturnsTab.tsx`, `ventas-online/ShippingManagementTab.tsx`.
   - 이 중 `ReturnsTab`은 `PUT`을 씁니다. `OrderDetailView.tsx:117`에 PUT이 404를 냈다는 주석이 있습니다.
4. **역할 게이트가 메뉴에만 있음**:
   - /facturacion은 사이드바에서만 supervisorRoles로 막고, 페이지는 `allowedApps venta`만 확인합니다. vendedor도 URL로 열 수 있습니다. `pages/facturacion/index.tsx:17`
   - /ventas-online 페이지에는 WithAccess 자체가 없습니다. `pages/ventas-online/index.tsx`
5. **숨긴 버튼과 달리 단축키는 권한 검사를 안 함**:
   - "Generar Venta", "Suspender", "Imprimir Temp"는 `crear-venta` 권한으로 숨겨집니다.
   - 하지만 F2, Alt+F2, F10, Ctrl+F12, Ctrl+S 단축키에는 권한 검사가 없습니다. `PL:2115, 2154, 2175, 2204` vs `PL:2663`
6. **ESC가 두 번 바인딩됨**: 보류판매를 복원한 상태에서 ESC를 누르면 두 핸들러가 동시에 실행될 수 있습니다. 하나는 전체 초기화, 다른 하나는 삭제 confirm입니다. 실제 동작은 미확인. `PL:2062-2066, 2213-2240`
7. **오래된 주석/문구**:
   - POS 주석은 발급 경로가 "/facturacion Pendientes 패널"이라고 하지만, 그 패널은 제거됐습니다. `PL:2786-2791` vs `FacturacionShell.tsx:11-16`
   - "Devolver Ropas" 주석은 Ctrl+D라고 하지만 실제 키는 Ctrl+E입니다. `PL:2414` vs `PL:677`
8. **Anular confirm의 금액 형식이 잘못됨**: 아르헨티나 매장인데 `es-CO` / `COP`(콜롬비아 페소)로 표시합니다. `SaleReviewPanel.tsx:220`
9. **/clientes-globales 필터가 페이지 로컬**: Activos/Inactivos 필터와 통계를 현재 페이지 안에서만 계산합니다. ClienteVista에서 이미 고친 것과 같은 버그입니다. `views/clientes-globales/GlobalClientesView.tsx:128-142`
10. **/cliente-vista의 Eliminados 처리**:
    - 이미 삭제된(Eliminados) 행에도 "Desactivar cliente" 버튼이 보입니다.
    - 되살리는(reactivar) 동작은 없습니다. `ClienteVistaView.tsx:547-560`
11. **"Adelanto / saldo a favor"에 도달할 수 없는 경우**: "Registrar pago"가 잔액 ≤ 0일 때 비활성이라, 빚 없는 고객은 이 옵션을 쓸 수 없습니다. `ClientLedgerView.tsx:148`; `CreditPaymentModal.tsx:150-153`
12. **도달 불가능한 분기**:
    - `EnvioTimeline`은 `refundAction==='devolver'` toast를 처리하지만, 취소 다이얼로그는 `'favor'`만 보냅니다. `EnvioTimeline.tsx:338`; `CancelPedidoDialog.tsx:69-77`
    - MP QR 패널의 "Ir a configuración"은 `onConfigure`가 필요한데, POS 결제 모달이 넘기지 않아 절대 표시되지 않습니다. `PSM:1090-1099`; `McdpgQrPanel.tsx:115`
13. **URL로만 들어갈 수 있는 화면**:
    - /dashboards/ventas: Venta 메뉴에서 exclude. `menuRegistry.ts:260`
    - /clientes-globales/carga-masiva, /import-history: hiddenModuleUrls. `menuRegistry.ts:133-134`
    - /clientes-globales(목록): 사이드바 항목 미확인. 대시보드의 "Clientes" 카드로만 연결됨.
    - /ventas/detalle/[id]: 위 2번 참고.

## 2. 상품 · 원자재 · 공방

| ID | 화면(경로) | 진입 | 조작 | 기대 결과 | 역할/조건 | 근거 | 실측 |
|---|---|---|---|---|---|---|---|
| P-01 | /productos | 사이드바 Producto 그룹 클릭 → 바로 /productos (defaultPath) | 페이지 진입 | 좌측에 목록과 "＋ Entrada de stock" 입력폼, 우측에 Sucursales·Variantes·Códigos madres 패널이 보임 | app `producto` + module `productos` 필요. 없으면 /unauthorized | pages/productos/index.tsx:10, navigation/menuRegistry.ts:279, views/products/list/ProductsView.tsx:1575 | ⬜ |
| P-02 | /productos | 동일 | 상단 날짜 입력 변경 / "Hoy" 클릭 | GET /products/stock-today 로 해당 날짜 입고 목록과 KPI(productos/unidades/$)가 갱신됨 | - | views/products/list/components/ProductsList.tsx:55, :340-347 | ⬜ |
| P-03 | /productos | 동일 | "Código Madre" 체크박스 on/off, "SKU o nombre…" 검색 | 체크하면 madre 단위로 묶어서 보임. 해제하면 편집 대상이 해제됨. 응답이 잘렸으면 "+N códigos madre no mostrados" 표시 | - | ProductsList.tsx:285-293, :318-323, :333 | ⬜ |
| P-04 | /productos | 동일 | Madre 뷰에서 행의 휴지통 아이콘(title "Eliminar registro de hoy") 클릭 → confirm | DELETE /products/stock-today/:parentId?date=. 토스트 "Registro del día eliminado (N entradas)". madre 전체·전 지점의 그날 입고가 상쇄됨 | - | ProductsList.tsx:159-178, components/DataConfig.tsx:300-318 | ⬜ |
| P-05 | /productos | 동일 | 변형 행의 연필 아이콘(title "Modificar el código madre") 클릭 | 해당 madre가 좌측 폼에 로드됨. GET /products/:id/inventory-by-date(-branch) | - | DataConfig.tsx:26-47, ProductsView.tsx:120, :169-175 | ⬜ |
| P-06 | /productos | 동일 | 우측 "Códigos madres" 목록 행 클릭 | variant가 폼에 채워짐. 토스트는 "Variantes existentes cargadas (con entradas de hoy)" 또는 "Variantes cargadas con stock 0 — ingrese solo las cantidades nuevas". 모드는 edit/add로 전환 | - | ProductParentList.tsx:446-460, :345-374 | ⬜ |
| P-07 | /productos | 동일 | 새 상품: 분류·이름·가격·Variantes 그리드 입력 → "Guardar" | POST /products 후 POST /products/variants/batch. 토스트 "Producto creado correctamente". 지점을 하나도 고르지 않으면 "Debe seleccionar al menos una sucursal" | store.useVariants=true이고 useColor/useSize가 둘 다 false가 아니어야 variant 모드 | ProductsView.tsx:1101, :1203-1217, BasicDataCard.tsx:1190-1200 | ⬜ |
| P-08 | /productos (단순 모드) | 동일 | "Cantidad"에 음수 입력 → "Guardar" | 토스트 "La cantidad no puede ser negativa". 이 모드에서는 Variantes 그리드가 렌더되지 않음 | stores.useVariants=false 또는 useColor=useSize=false (설정: 관리자 ModalStore) | ProductsView.tsx:85-93, :910-915, BasicDataCard.tsx:1127 | ⬜ |
| P-09 | /productos | 동일 | 기존 madre 로드 후 수량/가격/SKU 수정 → "Modificar" | PUT /products/:id(SKU) 후 PUT /products/:parentId/correct-today. 바뀐 것이 없으면 "No hay cambios para actualizar" | 코드 입력칸은 `editar-un-producto` 권한이 없거나 autoSku면 disabled("Sin permiso para editar el código") | ProductsView.tsx:1268, :1377-1378, :1424, :1441, BasicDataCard.tsx:978, :1207-1218 | ⬜ |
| P-10 | /productos | 동일 | madre 편집(EDITANDO 배지) 중 variant 추가·수정 → 저장. "✕" 누르면 편집 해제 | PUT /products/:parentId/edit-madre-variants. 토스트 "Cambios guardados correctamente" | useVariants=true | ProductsView.tsx:787-846, :1703-1723 | ⬜ |
| P-11 | /productos | 동일 | "Limpiar" 클릭 / Serial 칸 클릭 | 폼 초기화. Serial을 클릭하면 분류·공급자는 유지한 채 새 제품 모드로 들어감(GET /products/next-serial) | - | BasicDataCard.tsx:1176-1185, :770-800, :314 | ⬜ |
| P-12 | /productos | 동일 | 토글 "Publicar" / "Re-vendedor" / "Marketplace" / "Tienda Web" | Publicar는 권한이 있을 때만 보임. Tienda Web은 기존 상품이면 즉시 PUT /products/publish-shop 후 토스트 "Publicado en tienda web" | Publicar: function `publicar-o-no-publicar-producto`. Tienda Web: shopEnabled 매장만 | BasicDataCard.tsx:810-848 | ⬜ |
| P-13 | /productos | 동일 | Códigos madres 목록의 "Web" 칼럼 아이콘 토글 | PUT /products/publish-shop. 토스트 "Publicado en la tienda web" / "Quitado de la tienda web". 실패하면 원래 값으로 롤백 | shopEnabled 매장에서만 칼럼이 보임 | ProductParentList.tsx:68-108, :111-116, DataConfig.tsx:444-470 | ⬜ |
| P-14 | /productos | 동일 | madre 행 휴지통(title "Eliminar producto") → 다이얼로그 "¿Eliminar el código madre?" → "Eliminar" | GET /products/:id/delete-impact로 판정한 뒤 DELETE /products/:id. canDelete=false면 "Eliminar" disabled | 칼럼 자체가 function `eliminar-un-producto` 보유자에게만 보임 | ProductParentList.tsx:66, :116, :159-172, :530-538 | ⬜ |
| P-15 | /productos | 동일 | variant가 있는 madre 삭제 다이얼로그 → "Marcar como Borrado (madre + N)" | POST /products/:id/deactivate-tree. 토스트 "\"이름\" y N variante(s) marcados como Borrado" | blocker VARIANTES가 있을 때만 버튼이 보임 | ProductParentList.tsx:180-203, :516-529 | ⬜ |
| P-16 | /productos | 동일 | 편집 모드에서 "Datos" 탭의 "Editar ruta" / "Aplicar plantilla" | 프리셋을 적용하면 PUT /products/:id/routing-template. 토스트 "Plantilla \"…\" aplicada (N etapas)". 등록된 etapa가 없으면 "Ninguna etapa de la plantilla existe. Cargá las etapas primero." | mode==='edit' 이고 탭 0일 때만 보임 | BasicDataCard.tsx:1048-1053, RoutingTemplateSection.tsx:114-126, :174-195 | ⬜ |
| P-17 | /productos | 동일 | "Descripción por WEB" 탭 → Resumen/Material/Cuidados/Origen 입력 | 입력값이 product 상태에 반영됨. 저장 경로는 미확인 | - | BasicDataCard.tsx:944-945, :1045, DescripcionEditor.tsx:120-177 | ⬜ |
| P-18 | Zebra Agent (데스크톱) | 웹이 아니라 zebra-agent Electron 앱 | 상품 검색 "Buscar" → 체크 → "Imprimir x ZPL" | WS get_stock_today/search_products로 조회한 뒤 로컬에서 ZPL을 프린터로 전송. 로그 "✅ N etiqueta(s) impresas". 프린터가 미설정이면 "Impresora no configurada" | 에이전트가 서버에 연결돼 있어야 함. ProductBranch가 없는 활성 상품은 404(알려진 이슈, 코드상 재현 경로는 미확인) | zebra-agent/renderer/index.html:209, :234, zebra-agent/main.js:460-548 | ⬜ |
| P-19 | /precios, /codigo-vista | 사이드바 모듈(DB module url /precios) | 페이지 진입 | 좌측 상품 테이블, 우측 탭 "📈 Ajuste Global" / "⚖️ Niveles de Precio" / "🎁 Promociones". GET /products/by-store, /price-types | module `precios` 필요. superadmin 사이드바에서는 숨김 | pages/precios/index.tsx:8, pages/codigo-vista/index.tsx:8, navigation/menuRegistry.ts:365, views/codigo-vista/CodigoVistaView.tsx:439-440, :1866-1883 | ⬜ |
| P-20 | /precios | 동일 | 필터 "Cód. Madre", "Web Sincro", "Borrados", Categoría/Proveedor/Origen/Temporada, "Buscar por código o nombre..." | 목록이 필터링되고 "N de M"이 표시됨. Borrados를 켜면 삭제된 것만 보임 | Web Sincro는 WP 채널이 있을 때만 | CodigoVistaView.tsx:1459, :1475, :1483-1528, :1563-1570 | ⬜ |
| P-21 | /precios | 동일 | 행 선택 → "Eliminar (N)" → "Confirmar eliminación" | POST /products/update-status status=deactivated. 토스트 "N producto(s) eliminado(s)" | Borrados 필터가 꺼져 있을 때 | CodigoVistaView.tsx:1413-1422, :1289-1307, :2739-2766 | ⬜ |
| P-22 | /precios | 동일 | Borrados on → 선택 → "Restaurar (N)" | POST /products/update-status status=active. 토스트 "N producto(s) restaurado(s)" | showOnlyBorrados | CodigoVistaView.tsx:1401-1411, :1263-1282 | ⬜ |
| P-23 | /precios | 동일 | Ajuste Global: "Tipo de ajuste"(Establecer/Porcentaje/Monto fijo/Por tramos), "Subir ↑"/"Bajar ↓" → "Aplicar Ajuste" | POST /products/bulk-update-prices. 토스트 "Ajuste aplicado a N producto(s)". 아무것도 선택하지 않으면 전체('todos')에 적용 | 방향 버튼은 set·tramos 모드에서는 숨김. tramos는 최대 10개("Agregar tramo (n/10)") | CodigoVistaView.tsx:2111-2150, :2482-2488, :2652-2662, :1165-1240 | ⬜ |
| P-24 | /precios | 동일 | "Establecer" 모드에서 상품 1개 선택 → "Guardar todos los cambios" | PUT /products/:id와 bulk-update-prices(사진은 /minio 업로드) 후 토스트 "Cambios guardados" | infMode==='set' 이고 activeId가 있을 때 | CodigoVistaView.tsx:2640-2650, :1022-1092 | ⬜ |
| P-25 | /precios | 동일 | Niveles de Precio: 카드 클릭 → Nombre/Valor(%)/"Activar redondeo" → 저장. "Aplicar Ratios" | PUT /price-types/:id → 토스트 "Nivel de precio actualizado". Ratios는 bulk-update-prices → "Ratios aplicados a N producto(s)" | BASE 레벨은 increaseValue가 0으로 고정 | CodigoVistaView.tsx:1896-2065, :2097-2105, :1337-1349, :1108-1156 | ⬜ |
| P-26 | /precios | 동일 | 🎁 Promociones: 폼 작성 후 저장, 카드의 Switch/"Editar"/"Duplicar"/"Eliminar" | POST/PUT /promotions, PUT /promotions/:id/toggle, DELETE /promotions/:id. 토스트 "Promoción creada"/"Promoción actualizada"/"Promoción eliminada de …" | - | PromotionsTab.tsx:71-151, PromotionCard.tsx:52-76, PromotionForm.tsx:191-310 | ⬜ |
| P-27 | /precios | 동일 | "Importar Excel" → "Descargar plantilla vacía" → 파일 업로드 → "Importar" | GET /code-import/template, POST /code-import. 미리보기 칩(colores/códigos madres/hijitos) 표시. 완료 토스트 "Importación completada — datos actualizados" | - | CodigoVistaView.tsx:1429-1438, :2728, CodeImportDialog.tsx:262, :294, :336-365, :647-670 | ⬜ |
| P-28 | /precios | 동일 | Madre 행의 QR 아이콘(title "Imprimir QR") → 가격 레벨 선택 | POST /print/qr {branchId, parentProductId, priceTypeId}. 토스트 "QR 출력 요청 완료"(한국어) | isParent 행에만 보임. selectedBranchId가 없으면 아무 반응 없이 return | CodigoVistaView.tsx:414-432, :1824-1831, :2773-2786, api-ventago/src/app/print/print.controller.ts:296 | ⬜ |
| P-29 | /precios | 동일 | Canal Web 선택 후 편집 → "Iniciar sincro Web (N)" | POST /integrations/wp/sync/:id/resync. 결과 토스트 "Sincronizado: X OK, Y fallos · …" | WP 채널이 선택돼 있고 pendientesWeb>0일 때만 보임 | CodigoVistaView.tsx:917-931, :1535-1555, :1576 | ⬜ |
| P-30 | /precios | 동일 | 활성 madre의 VariationPanel에서 variant 추가/삭제 | 추가: PUT edit-madre-variants → "Variante agregada". 삭제: update-status → "Variante eliminada (soft-delete)". 색/사이즈 미선택이면 "Seleccione color y talle" | 지점 선택 필요("Sucursal no seleccionada") | VariationPanel.tsx:54-110, CodigoVistaView.tsx:2700 | ⬜ |
| P-31 | /dashboards/producto | 사이드바 Producto > 두 번째 항목 | 페이지 진입 | 카드(Categorías/Subcategorías/Tallas/Colores/Proveedores/Temporadas 개수), "Productos con menos stock", "Últimos productos creados" | app `producto` + module `dashboard-producto` | pages/dashboards/producto/index.tsx:10, ShortcutConfigurations.tsx:28, ProductsLessStock.tsx:24, NewlyCreatedProducts.tsx:25 | ⬜ |
| P-32 | /dashboards/producto | 동일 | "+ Categoría" … "+Temporada" 버튼 | 각 생성 모달이 열리고, 저장하면 카운트가 갱신됨 | - | ShortcutConfigurations.tsx:49-56, :140-148 | ⬜ |
| P-33 | /dashboards/stock | URL 직접(사이드바 항목은 미확인) | 페이지 진입 | 텍스트 "Dashboard Stock"만 보임(기능 없음) | allowedApps `stock`(appOrder에 없는 앱). allowedRoles는 WithAccess가 무시 | pages/dashboards/stock/index.tsx:7-8, configs/withAccess.tsx:17 | ⬜ |
| P-34 | /m/stock | 라벨 QR 스캔(공개, 로그인 불필요) | `?s=&p=` 없이 접속 / 없는 상품 / 서버 오류 | 각각 "Enlace incorrecto", "Producto no disponible", "No pudimos cargar la información" + "Reintentar" | authGuard=false | pages/m/stock/index.tsx:47-104, views/m-stock/QrProductView.tsx:98-135 | ⬜ |
| P-35 | /m/stock | 동일 | 정상 QR, 매장 모드 closed/shop_redirect/full | closed는 "Esta tienda no comparte información de productos por QR.". shop_redirect는 "Ver catálogo" 링크. full은 "¿Querés ser revendedor de …?"와 "Crear mi tienda"(/register?ref=) | GET /public/qr-stock/:s/:p | QrProductView.tsx:142-195, :219, :320-345 | ⬜ |
| M-01 | /materia-prima/proveedores | 사이드바 Materia prima > Proveedores | 진입 | KPI "Total Proveedores"/"Con Deuda Pendiente"/"Deuda Total"과 카드 목록. GET /materia-prima/suppliers/store | app `materia-prima` + module `proveedores-materia-prima` | pages/materia-prima/proveedores/index.tsx:10, views/materia-prima/ProveedoresView.tsx:99, :290-302 | ⬜ |
| M-02 | 동일 | 동일 | "Nuevo Proveedor" → "Nombre / Razón social *" 등 입력 → "Crear" | POST /materia-prima/suppliers → "Proveedor creado". 이름이 비어 있으면 버튼 disabled | - | ProveedoresView.tsx:269-276, :190-192, :592-603 | ⬜ |
| M-03 | 동일 | 동일 | 카드 연필 아이콘 → 수정 → "Guardar" | PUT /materia-prima/suppliers/:id → "Proveedor actualizado" | 삭제·비활성화 버튼은 없음 | ProveedoresView.tsx:362-366, :187-189 | ⬜ |
| M-04 | 동일 | 동일 | 연락 아이콘(ContactSupplierTrigger) → WhatsApp/전화/Email | 각각 wa.me / tel: / mailto: 링크가 열림 | 해당 필드가 있을 때만 | ProveedoresView.tsx:361, components/ContactSupplierPopover.tsx:103, :133, :161 | ⬜ |
| M-05 | /materia-prima/inventario | 사이드바 Materia prima 클릭 → defaultPath | 진입, 탭 "Materiales" / "Lista plana" | 탭 0은 TelasMadreView, 탭 1은 InventarioView | module `inventario-materia-prima` | pages/materia-prima/inventario/index.tsx:14-20, navigation/menuRegistry.ts:299 | ⬜ |
| M-06 | 동일(Materiales) | 동일 | "Nuevo material" → 코드/이름/색상 행 → "Guardar" | POST /mes/materials/parent-with-variants → "Material creado con N variantes". 코드·이름·색이 없거나 색이 중복되면 에러 토스트 | - | TelasMadreView.tsx:251-257, :981-1064, :1092 | ⬜ |
| M-07 | 동일(Materiales) | 동일 | 부모 선택 → "Agregar color" / 색 행 편집·삭제 아이콘 | POST /mes/materials/:id/colors → "Color agregado". PUT → "Color actualizado". 삭제는 confirm 후 DELETE /mes/materials/colors/:id → "Color eliminado" | - | TelasMadreView.tsx:533-543, :660-671, :420-439, :762-786 | ⬜ |
| M-08 | 동일(Materiales) | 동일 | "Reponer stock" → 색별 수량 → "Registrar ingreso" | POST /materia-prima/movements/bulk-entrada → "Ingreso registrado en N colores". 수량이 없으면 "Ingresá cantidad en al menos un color" | - | TelasMadreView.tsx:545-551, :1416-1449, :1574-1580 | ⬜ |
| M-09 | 동일(Lista plana) | 동일 | "Nuevo material" → 입력(인라인 "Nuevo proveedor", "Registrar varios colores a la vez") → "Crear" | POST /mes/materials 또는 /mes/materials/bulk → "Material creado" / "N materiales creados". 인라인 공급자는 "Crear y seleccionar" | - | InventarioView.tsx:657-663, :488-547, :1084-1104, :1606-1620 | ⬜ |
| M-10 | 동일(Lista plana) | 동일 | 행 아이콘 "Editar" / "Convertir a doble unidad (rollo/kg → m)" | PUT /mes/materials/:id → "Material actualizado". 변환은 POST /mes/materials/:id/convert-to-dual → "Material convertido a doble unidad" | 변환 아이콘은 단일 단위 자재에만 보임 | InventarioView.tsx:840-852, :346-364, :543-544 | ⬜ |
| M-11 | 동일(Lista plana) | 동일 | "Desactivar"/"Reactivar"/"Eliminar" 아이콘 → 확인 | 셋 다 PUT /mes/materials/:id {isActive}. 토스트 "Material desactivado"/"activado"/"eliminado". 비활성 항목은 "Mostrar inactivos"로 확인 | - | InventarioView.tsx:853-870, :581-598, :706, :1353-1405 | ⬜ |
| M-12 | 동일(Lista plana) | 동일 | "Categorías" 버튼 | CategoriesManagerDialog가 열림(세부 동작 미확인) | - | InventarioView.tsx:648-655 | ⬜ |
| M-13 | /materia-prima/movimientos | 사이드바 Materia prima > Movimientos | "Entrada" → Material*/Proveedor*/Cantidad*/"Estado de pago"(Pendiente/Parcial/Pagado) → "Registrar" | POST /materia-prima/movements/entry → "Entrada registrada". 자재나 공급자가 없으면 "Material y proveedor son obligatorios". 이중 단위면 "Agregar {unit}"로 롤 입력 | module `movimientos-materia-prima` | MovimientosView.tsx:336-347, :582-586, :670-676, :720-745, :212-259 | ⬜ |
| M-14 | 동일 | 동일 | "Salida" → Material*/수량 → "Registrar" | POST /materia-prima/movements/exit → "Salida registrada" | - | MovimientosView.tsx:349-360, :788-793, :265-294 | ⬜ |
| M-15 | 동일 | 동일 | 필터 Tipo/Material/Proveedor/Desde/Hasta | 목록 필터링(쿼리 방식은 미확인) | - | MovimientosView.tsx:379-430 | ⬜ |
| M-16 | /materia-prima/pagos | 사이드바 Materia prima > Pagos | "Registrar Pago" → Proveedor*/Monto*/Fecha/"Método de pago"(Efectivo/Transferencia/Cheque/Tarjeta/Otro) → "Registrar" | POST /materia-prima/payments → "Pago registrado". 공급자 없음 → "Proveedor es obligatorio", 금액 ≤0 → "Monto debe ser mayor a 0" | module `pagos-materia-prima` | PagosView.tsx:238-250, :540-558, :190-218 | ⬜ |
| M-17 | 동일 | 동일 | 부채 공급자 행 클릭(title "Clic para pre-cargar pago") | 해당 공급자로 결제 폼이 미리 채워진 채 열림 | - | PagosView.tsx:315-325 | ⬜ |
| M-18 | /materia-prima/dashboard | 사이드바 Materia prima > Dashboard | 진입 | KPI "Total Materiales"/"Stock Bajo / Agotado"/"Valor del Inventario"/"Deuda a Proveedores", 차트, 저재고 표의 연락 버튼 | module `dashboard-materia-prima` | MateriaPrimaDashboardView.tsx:44-55, :172-193, :327 | ⬜ |
| M-19 | /materia-prima/* | URL 직접 | vendedor 단독 사용자가 URL로 접근 | 사이드바에서는 숨겨짐(canAccessApp). 페이지 WithAccess는 vendedor 차단을 검사하지 않음. structure에 앱이 있으면 열릴 수 있음(실측 필요) | vendedorBlockedApps | navigation/menuRegistry.ts:195-224, configs/withAccess.tsx:29-43 | ⬜ |
| M-20 | /materia-prima/telas-madre | URL 직접(사이드바 order에 없음) | 진입 | TelasMadreView 단독 화면(inventario 탭 0과 동일) | module `inventario-materia-prima` | pages/materia-prima/telas-madre/index.tsx:10, navigation/menuRegistry.ts:300-306 | ⬜ |
| T-01 | /talleres | 사이드바 Talleres(directPath, 하위 메뉴 없음) | 진입 | 탭 10개(📊 Overview … Liquidaciones), 기본 탭 overview. `?tab=garbage`면 overview, `?tab=dashboard`면 overview로 alias | canAccessApp('talleres'). vendedor 단독이나 superadmin이면 /unauthorized | pages/talleres/index.tsx:22-40, views/talleres/components/constants.ts:38-60, TalleresMainView.tsx:39 | ⬜ |
| T-02 | /talleres | 동일 | 우측 도움말 아이콘(Tooltip "Guía de uso") | OnboardingTour 다이얼로그가 강제로 열림(Siguiente·Omitir 등) | 첫 방문 때는 localStorage 플래그로 자동 표시 | TalleresMainView.tsx:53-60, :113-122, components/OnboardingTour.tsx:213-285 | ⬜ |
| T-03 | /talleres (모든 탭) | 동일 | 배너 "N recepción(es) sin ingresar al stock" 칩 클릭 | Lotes 탭으로 이동하고 해당 lote의 IngresoStock이 열림(`?lote=&action=ingreso`) | GET /talleres/recepciones/pendientes. 0건이면 배너 없음 | components/PendingInventoryBanner.tsx:35-90, tabs/LotesTab.tsx:51-52 | ⬜ |
| T-04 | /talleres (모든 탭) | 동일 | 배너 "N situación(es) para revisar" 칩 클릭 | AJUSTAR_CANTIDAD는 "Ajustar cantidad — LOT" 다이얼로그 → POST /talleres/lotes/:id/ajuste-cantidad → "Ajuste registrado". 그 외는 해당 탭으로 이동 | GET /talleres/lotes/excepciones | components/ExcepcionesBanner.tsx:53-124, components/AjusteCantidadDialog.tsx:76-97, :188-189 | ⬜ |
| T-05 | Overview 탭 | 동일 | 진입, 데이터 없음 상태 | GET /talleres/dashboard-v2. 비어 있으면 "Ir a Talleres"/"Crear primer Lote". 오류면 "Reintentar" | - | hooks/api/useTalleresDashboardV2.ts:16, overview/OverviewTab.tsx:48, overview/components/OverviewEmptyState.tsx:30-42 | ⬜ |
| T-06 | Overview 탭 | 동일 | 긴급 테이블 행 클릭 / "Reasignar", "Extender plazo" | 행을 클릭하면 `?tab=envios&envioId=`로 이동. 두 버튼은 disabled(Tooltip "Proximamente") | - | overview/components/UrgentActionTable.tsx:27, :121-133 | ⬜ |
| T-07 | Etapas 탭 | 동일 | 빈 상태 "Cargar etapas estándar (confección)" | POST /talleres/etapas 여러 번 → "N etapas estándar creadas" | etapa가 0개일 때만 | tabs/EtapasTab.tsx:398-406, :161-171 | ⬜ |
| T-08 | Etapas 탭 | 동일 | "+ Nueva Etapa" → "Nombre de la Etapa"/"Orden"/"Activa" → "Crear". 연필로 수정 | POST/PUT /talleres/etapas → "Etapa creada"/"Etapa actualizada". 이름이 없으면 버튼 disabled | - | EtapasTab.tsx:326-332, :654-696, :181-213 | ⬜ |
| T-09 | Etapas 탭 | 동일 | 비활성 아이콘(title "Desactivar") → "Desactivar etapa" 확인 | GET /talleres/etapas/:id/usage로 사용 여부 확인 → PUT isActive → "Etapa desactivada"/"Etapa activada" | - | EtapasTab.tsx:228-276, :703-785 | ⬜ |
| T-10 | Etapas 탭 | 동일 | "Tarifas por Taller x Etapa" 셀 클릭 → RateHistoryPanel "+ Nueva tarifa" → "Precio unitario"/"Vigente desde" → "Guardar" | POST /talleres/vendor-etapas/:v/:e/rate → "Tarifa actualizada". "Cerrar"로 닫기 | 활성 셀만 | EtapasTab.tsx:495-570, :800, etapas/components/RateHistoryPanel.tsx:178-184, :346-418, :525-531 | ⬜ |
| T-11 | Cost Sheet (BOM) 탭 | 동일 | "Producto (código madre)" 선택 → "Crear BOM v1.0" | POST /mes/bom/for-product → "BOM creado — agregá materiales abajo" | 활성 BOM이 없을 때만 | cost-sheet/CostSheetTab.tsx:77-87, :191-208 | ⬜ |
| T-12 | Cost Sheet 탭 | 동일 | "Agregar material" → 자재·수량 입력(자동저장) / "Quitar" / "Nueva versión" | PUT /mes/bom/:id/items(500ms 디바운스). 새 버전은 POST /mes/bom/:id/new-version → "Nueva versión creada" | - | cost-sheet/components/BomEditorSection.tsx:126-150, :188-197, :300-310, :450, :468-474 | ⬜ |
| T-13 | Cost Sheet 탭 | 동일 | "Calcular Cost Sheet" / "🔄 Recalcular" / 편집 폼 수정 | POST /talleres/cost-sheets/:pid/calculate → "Cost Sheet calculado"/"Cost Sheet recalculado". 폼 수정은 PATCH 후 calculate(디바운스) | - | CostSheetEmptyState.tsx:67-71, :111-118, CostSheetTab.tsx:152-156, CostSheetHeader.tsx:50-57, CostSheetEditableForm.tsx:40-68 | ⬜ |
| T-14 | Lotes 탭 | 동일 | "Nuevo Lote" → Producto/"Cantidad Total"/Notas → "Crear Lote" | POST /talleres/lotes 후 목록 갱신. 상품이나 수량이 없으면 버튼 disabled | - | tabs/LotesTab.tsx:264-270, :147-160, :509-566 | ⬜ |
| T-15 | Lotes 탭 | 동일 | 행 버튼 "Cut Ticket"(CT 없음) / "Enviar"(CT 있음) | Cut Ticket 탭으로 이동(`?lote=`). 또는 EnvioFormDialog. availableQuantity≤0이면 Enviar disabled | OPEN/IN_PROGRESS 상태만 | LotesTab.tsx:389-419, :74 | ⬜ |
| T-16 | Lotes 탭 | 동일 | 휴지통(title "Eliminar Lote (queda en log de auditoría)") → confirm | DELETE /talleres/lotes/:id → "Lote eliminado" | 모든 사용자에게 보임(권한 가드 없음) | LotesTab.tsx:195-215, :433-443 | ⬜ |
| T-17 | Lotes 탭 | 동일 | 행 클릭 → Drawer "Nuevo Envio"/"Ingresar a stock"/"Cerrar Lote" | Ingresar: "Ingresar a stock" 다이얼로그에서 Destino 선택 → "Ingresar N uds" → POST /talleres/lotes/:id/ingreso-stock → "Ingreso registrado — N uds". Cerrar: confirm → PUT status CLOSED → "Lote cerrado" | CT가 없으면 Envio/Ingresar disabled. CLOSED면 Cerrar disabled | drawers/LoteDetailDrawer.tsx:70-90, :299-344, drawers/IngresoStockDialog.tsx:69-155 | ⬜ |
| T-18 | Lotes 탭 | 동일 | 표의 "Cerrar" 버튼(COMPLETED lote) | 아무 동작 없음(onClick은 stopPropagation만 함) | status==='COMPLETED' | LotesTab.tsx:421-431 | ⬜ |
| T-19 | Cut Ticket 탭 | 동일 | "Lote" 선택 → "✂️ Configurar y Generar Cut Ticket" → 다이얼로그 "Configurar ruta y generar Cut Ticket" → "Configurar y Generar" | POST /talleres/lotes/:id/cut-ticket. 번호 CT-YYYY-NNN과 BOM/ruta 스냅샷 생성. etapa가 0개면 "No hay etapas de producción activas…" | "Guardar como ruta predeterminada de este producto" 체크 가능 | cut-ticket/CutTicketTab.tsx:146-162, components/CutTicketEmptyState.tsx:50-108, components/RutaConfigDialog.tsx:433-441, :460-467, :548 | ⬜ |
| T-20 | Cut Ticket 탭 | 동일 | 사이즈×컬러 매트릭스 입력 | PATCH /talleres/lotes/:id/size-color-matrix. cutDate가 있으면 readOnly | - | components/SizeColorMatrixEditor.tsx:24, :82-91 | ⬜ |
| T-21 | Cut Ticket 탭 | 동일 | "✂️ Iniciar Corte" | 매트릭스가 0이면 "La matriz está vacía…". 합계가 다르면 confirm. PATCH /talleres/lotes/:id/cut-date → "Corte iniciado" | cutDate가 없을 때만 보임 | CutTicketTab.tsx:60-90, components/CutTicketHeader.tsx:75-88 | ⬜ |
| T-22 | Cut Ticket 탭 | 동일 | "📄 PDF (para taller)" | GET /talleres/lotes/:id/cut-ticket/pdf blob 다운로드. 실패하면 "PDF descarga falló" | - | CutTicketTab.tsx:100-118, CutTicketHeader.tsx:90-98 | ⬜ |
| T-23 | Cut Ticket 탭 | 동일 | "Editar ruta" → "+ Agregar" → "Guardar cambios" | PATCH /talleres/lotes/:id/routing → "Ruta actualizada". 진행 중인 etapa를 이동·삭제하면 에러 토스트 | - | components/RoutingFlow.tsx:83, :110-120, RutaConfigDialog.tsx:360-400, :444-448, :520-568 | ⬜ |
| T-24 | Cut Ticket 탭 | 동일 | "Recargar BOM" / 행 "Declarar retazo (sobrante descartado)" | POST …/cut-ticket/rebuild-bom → "BOM cargado — materiales descontados del inventario". Retazo는 prompt 후 POST /materia-prima/movements/retazo | - | components/BomTable.tsx:73-107, :120-131, :201 | ⬜ |
| T-25 | Talleres 탭 | 동일 | "Nuevo Taller" → "Nombre del Taller *"/"Procesos que realiza" → "Crear" | POST /talleres/vendors 후 PUT /talleres/vendor-etapas/:id/etapas → "Taller creado" | - | tabs/TalleresTab.tsx:333-340, :222-249, :508-617 | ⬜ |
| T-26 | Talleres 탭 | 동일 | 행 클릭(확장) / "Editar" / "Desactivar" → "Desactivar taller" | 행을 클릭하면 VendorExpandedRow 펼침. PUT isActive → "Taller desactivado"/"Taller activado" | - | TalleresTab.tsx:135, :409, :455-480, :275-283, :622-652 | ⬜ |
| T-27 | Talleres/Envíos/Liquidaciones 탭 | 동일 | "Excel" 내보내기 | xlsx 다운로드. 데이터가 없으면 disabled(Tooltip "No hay datos para exportar") | - | components/TalleresExportButton.tsx:20, :31-50, TalleresTab.tsx:303, EnviosTab.tsx:118, LiquidacionesTab.tsx:154 | ⬜ |
| T-28 | Envíos 탭 | 동일 | "Nuevo Envio" → "Lote *"/"Etapa (proceso) *"/"Taller *"/"Cantidad *" → "Registrar envío" | POST /talleres/envios → "Envío registrado". 수량 초과면 "Cantidad supera lo disponible (N)" | - | tabs/EnviosTab.tsx:144-150, envios/EnvioFormDialog.tsx:146-190, :209-314 | ⬜ |
| T-29 | Envíos 탭 | 동일 | 행 "Recibir" → "Recibido *"/"Rechazado"/(최종 공정은 "Sucursal de ingreso *") → "Registrar recepción" | POST /talleres/recepciones. 최종 공정이면 재고에 입고됨. 지점을 고르지 않으면 "Elegí la sucursal de ingreso a stock" | PENDING/PARTIAL 상태만. 필터 Estado/Taller/Etapa, "Atrasado" 칩 | EnviosTab.tsx:158-199, :267, :280-292, envios/RecepcionFormDialog.tsx:139-219, :255-290, :381-387 | ⬜ |
| T-30 | Pipeline 탭 | 동일 | 토글 "Flujo"/"Kanban". Kanban 필터 "Todos los vendors"/"Todos los productos". 같은 열에서 카드 드래그 | GET /talleres/dashboard/kanban. 순서를 바꾸면 PATCH /talleres/envios/:id/priority. 실패하면 롤백하고 "Error al guardar el orden". 다른 열로는 이동 불가 | - | tabs/PipelineTab.tsx:139-158, components/KanbanBoard.tsx:55, :140-178, components/KanbanFilters.tsx:105-136 | ⬜ |
| T-31 | Reworks 탭 | 동일 | 상태 필터(Pendiente/En curso/…), 행 "Cancelar" 아이콘 → confirm, "Actualizar" | PATCH /talleres/rework-orders/:id/cancel → "Rework cancelado" | PENDING/IN_PROGRESS만 취소 가능. 이 탭에는 생성 UI 없음 | tabs/ReworksTab.tsx:38-47, :83-87, :205-213, :227-233 | ⬜ |
| T-32 | Liquidaciones 탭 | 동일 | "+ Generar borrador" → "Taller / Vendor"/Desde/Hasta → "Generar borrador" | POST /talleres/settlements/draft → "Borrador #id generado (N líneas)" | - | tabs/LiquidacionesTab.tsx:180-192, liquidaciones/components/GenerateDraftDialog.tsx:97-113, :121-220 | ⬜ |
| T-33 | Liquidaciones 탭 | 동일 | 행 클릭 → Drawer "Descargar PDF"/"Confirmar"/"Cancelar borrador"/"Marcar como pagada" | GET …/pdf. POST /talleres/settlements/:id/{confirm,cancel,mark-paid} → "Liquidación confirmada" 등 | DRAFT: Confirmar/Cancelar. CONFIRMED: Marcar como pagada | liquidaciones/components/SettlementDetailDrawer.tsx:128-175, :385-455 | ⬜ |
| T-34 | /talleres/liquidaciones, /talleres/settlements | URL 직접 | 접속 | /talleres/?tab=liquidaciones로 리다이렉트 | next.config redirect | ventago-app/next.config.js:182-188 | ⬜ |
| T-35 | /dashboards/talleres, /talleres/dashboard | URL 직접(사이드바 비노출) | "Ver lista de talleres"/"Gestión de Órdenes"/"Gestión de Liquidaciones"/"En preparación" | 각각 /talleres/vendors, /talleres/orders, /talleres?tab=liquidaciones로 이동. "En preparación"은 disabled | module `dashboard-talleres` | pages/dashboards/talleres/index.tsx:8, :27-108, pages/talleres/dashboard/index.tsx:1-4 | ⬜ |
| T-36 | /talleres/vendors (레거시) | URL 직접 | "Registrar Nuevo Taller" → Drawer 저장 | POST/PUT /talleres/vendors | module `vendedores` | pages/talleres/vendors/index.tsx:9, vendors/talleres_VendorsListView.tsx:123-129, vendors/components/talleres_VendorFormDrawer.tsx:156-165 | ⬜ |
| T-37 | /talleres/etapas (레거시) | URL 직접 | "Nueva Etapa" / 삭제 | POST/PUT /talleres/etapas. 삭제는 DELETE /talleres/etapas/:id(신규 탭에는 없는 물리 삭제) | module `etapas-talleres` | pages/talleres/etapas/index.tsx:9, etapas/talleres_EtapasListView.tsx:60-81, :134-144 | ⬜ |
| T-38 | /talleres/lotes (레거시) | URL 직접 | 진입 → "Nuevo Lote" / 발송 | Taller·Etapa·자재 드롭다운이 비어 있을 가능성이 높음(아래 이상 4 참조) | module `lotes-talleres` | pages/talleres/lotes/index.tsx:9, lotes/talleres_LotesListView.tsx:111-121, :276-282 | ⬜ |
| T-39 | /talleres/envios (레거시) | URL 직접 | 행 아이콘 "Recibir"/"Cancelar"/"Enviar a rework" | POST /talleres/recepciones. PUT /talleres/envios/:id/cancel. Rework는 "Enviar a rework" 다이얼로그 → POST /talleres/rework-orders → "Rework creado" | module `envios-talleres` | pages/talleres/envios/index.tsx:9, envios/talleres_EnviosListView.tsx:150, :215, :236-249, :451, rework/ReworkDialog.tsx:140-154 | ⬜ |
| T-40 | /talleres/pedidos (레거시) | URL 직접(사이드바 숨김) | 진입 → "Nuevo Pedido" | 한국어 이전 안내 배너와 Cut Ticket 링크. "Nuevo Pedido"는 console.log만 찍음 | module `pedidos` | pages/talleres/pedidos/index.tsx:12-20, pedidos/talleres_PedidosListView.tsx:116-123 | ⬜ |
| T-41 | /talleres/orders, /deliveries, /defects, /control (레거시) | URL 직접 | 진입 | 조회 전용 목록/패널. GET /talleres/orders/all, /deliveries/all, /defects/all, /envios/dashboard/* | modules `ordenes-subcon`/`entregas`/`defectos`/app만(control) | pages/talleres/orders/index.tsx:10, deliveries/index.tsx:10, defects/index.tsx:10, control/index.tsx:9 | ⬜ |
| T-42 | /talleres/defect-codes (레거시) | URL 직접 | 새 코드(handleNew) / "Editar" / 활성 토글 | POST /talleres/defect-codes. PATCH /talleres/defect-codes/:id | WithAccess 없음(앱 게이트 없음) | pages/talleres/defect-codes/index.tsx:9-13, defect-codes/DefectCodesAdminView.tsx:128-180, :223-230 | ⬜ |

### 2. 상품 · 원자재 · 공방 — 코드 판독에서 나온 이상 (미실측)

#### 이상 사항 (Anomalies)

1. **작동하지 않는 버튼**
   - Lotes 탭 표의 "Cerrar" 버튼은 onClick에서 `e.stopPropagation()`만 합니다 (`views/talleres/tabs/LotesTab.tsx:421-431`). 실제로 닫는 동작은 Drawer의 "Cerrar Lote"에만 있습니다.
   - `/talleres/pedidos`의 "Nuevo Pedido"는 `console.log('Nuevo pedido')`만 합니다 (`views/talleres/pedidos/talleres_PedidosListView.tsx:116-123`).
   - Overview의 "Reasignar"와 "Extender plazo"는 disabled 상태이고 Tooltip이 "Proximamente"입니다 (`overview/components/UrgentActionTable.tsx:121-133`).
   - /dashboards/talleres의 "En preparación"도 disabled입니다.
2. **열리지 않는 다이얼로그**: `InventoryDialog`("Modificar"/"Agregar nuevo")는 렌더되지만 `setDialogOpen(true)`를 호출하는 곳이 없습니다 (`views/products/list/components/ProductParentList.tsx:540`).
3. **신규 Talleres 화면에서 Rework 생성 불가**: `ReworkDialog`는 레거시 `/talleres/envios`에서만 import됩니다 (`envios/talleres_EnviosListView.tsx:24, :451`). 통합 뷰의 Reworks 탭은 조회와 취소만 됩니다.
4. **레거시 /talleres/lotes 드롭다운 비어 있음 (추정)**: `GET /production/materials`를 처리하는 API 컨트롤러를 찾지 못했습니다(`mes/materials`만 존재). 이 요청은 `Promise.all` 안에 있어서, 실패하면 vendors·etapas 목록까지 함께 비게 됩니다 (`lotes/talleres_LotesListView.tsx:111-121`).
5. **무시되는 딥링크 파라미터**
   - Overview가 `?tab=envios&envioId=`로 이동시키지만 EnviosTab은 `envioId`를 읽지 않습니다 (`UrgentActionTable.tsx:27`).
   - ExcepcionesBanner가 붙이는 `query.envio`도 읽는 곳이 없습니다 (`components/ExcepcionesBanner.tsx:92`).
6. **URL 직접 접근 권한 불일치**
   - `WithAccess`는 `allowedRoles`를 무시하고, vendedor 차단 목록(`vendedorBlockedApps`)도 검사하지 않습니다 (`configs/withAccess.tsx:17-43`). 그래서 vendedor 단독 사용자가 `/materia-prima/*`나 레거시 `/talleres/*`를 URL로 열 수 있을 가능성이 있습니다. 차단은 `/talleres` 인덱스에만 있습니다 (`pages/talleres/index.tsx:25`).
   - `/talleres/defect-codes`에는 게이트가 전혀 없습니다.
   - `WithAccess`는 로그인하지 않은 사용자를 `/auth/login`으로 보내는데, 이 페이지는 존재하지 않습니다(`pages/auth` 없음).
7. **설정 화면이 없는 플래그**: `/dashboards/stock`은 `allowedApps={["stock"]}`인데 appOrder에 `stock` 앱이 없고, 내용도 "Dashboard Stock" 텍스트뿐입니다 (`pages/dashboards/stock/index.tsx:7`).
8. **스페인어 UI에 노출되는 한국어 문구**
   - QR 출력 성공 토스트 "QR 출력 요청 완료" (`views/codigo-vista/CodigoVistaView.tsx:427`)
   - `/talleres/pedidos` 배너 "페이지 이전 안내" (`pages/talleres/pedidos/index.tsx:14`)
   - Serial 칸 툴팁 (`BasicDataCard.tsx:771-774`)
   - 사이즈 칸 툴팁 "더블클릭: 이 talle 컬럼 제거" (`VariantsStock.tsx:519-523, :621`)
9. **QR 출력 조용한 실패**: 선택된 지점이 없으면 `handlePrintQr`가 아무 안내 없이 return합니다 (`CodigoVistaView.tsx:417-419`).
10. **"Eliminar"와 "Desactivar"가 같은 동작**: 원자재 Lista plana에서 둘 다 `PUT isActive=false`만 호출합니다 (`views/materia-prima/InventarioView.tsx:581-598`). 원자재 공급자(Proveedores)에는 삭제·비활성화 UI가 아예 없습니다.
11. **구현되지 않은 단축키 안내**: 버튼 title에 "(Ctrl+Enter)"가 있지만, products 뷰 안에서 키 핸들러를 찾지 못했습니다 (`BasicDataCard.tsx:1195, :1213`). 전역 처리 여부는 미확인입니다.
12. **Lote 삭제 권한 가드 없음**: 휴지통 버튼이 모든 사용자에게 보입니다. 코드 주석에 "필요하면 WithFunctionAccess로 대체할 것"이라는 TODO가 남아 있습니다 (`tabs/LotesTab.tsx:188-190`, `pages/talleres/defect-codes/index.tsx:9-11`).
13. **"Imprimir x ZPL"은 웹이 아니라 데스크톱 앱**: 이 버튼은 zebra-agent Electron 앱에만 있고(`zebra-agent/renderer/index.html:234`), 웹 /productos에는 라벨 인쇄 버튼이 없습니다. ProductBranch 없는 상품의 404는 알려진 이슈로 정리했지만, 코드에서 재현 경로는 확인하지 못했습니다(미확인).

## 3. 관리 · 금전함(Tesorería) · 설정

| ID | 화면(경로) | 진입 | 조작 | 기대 결과 | 역할/조건 | 근거 | 실측 |
|---|---|---|---|---|---|---|---|
| A-01 | /dashboards/admin | Admin 그룹 제목 클릭(defaultPath) → Dashboard | 페이지 진입 | KPI 6개 표시: VENTAS HOY, ALERTAS URGENTES, CHEQUES EN CARTERA, TALLERES ATRASADOS, ENVÍOS ESTANCADOS, IMPRESORAS OFFLINE. `GET /dashboard/admin/control-center`를 60초마다 폴링 | app admin + module dashboard-admin. API는 admin, gerente, superadmin만 허용 | APP/pages/dashboards/admin/index.tsx:10; APP/views/dashboards/admin/ControlCenterView.tsx:345-391; APP/hooks/api/useAdminControlCenter.ts:148-158; API/app/dashboard-admin/dashboard-admin.controller.ts:46-47 | ⬜ |
| A-02 | /dashboards/admin | 〃 | 칩 `Todo` / 심각도 칩(`… (n)`) | Alertas 목록이 심각도로 필터되고 "{n} activas" 개수가 바뀜 | 〃 | ControlCenterView.tsx:402-418 | ⬜ |
| A-03 | /dashboards/admin | 〃 | 알림 행 클릭 | 서버가 준 `link`로 이동(/control-de-caja, /cheques, /sucursales, /ventas 등) | 〃 | ControlCenterView.tsx:427; API/app/dashboard-admin/dashboard-admin.service.ts:547-678 | ⬜ |
| A-04 | /dashboards/admin | 〃 | 위젯 `Ver todo →` | Cajas→/control-de-caja, Cheques→/cheques, Infraestructura→/sucursales, Pulso→/reportes-v2 등으로 이동 | 〃 | ControlCenterView.tsx:106-111; dashboard-admin.service.ts:289-307 | ⬜ |
| A-05 | /dashboards/admin | 〃 | 이상이 없을 때 | 각 위젯에 "✓ Sin anomalías de caja hoy" 같은 빈 상태 문구, 알림 0건이면 "✅ Sin alertas — buen día." | 〃 | ControlCenterView.tsx:113-116, 419-422, 459 | ⬜ |
| A-06 | /dashboards/admin | 〃 | API 실패 | "No se pudo cargar el Centro de Control — reintentando…" 표시 | 〃 | ControlCenterView.tsx:311-319 | ⬜ |
| A-07 | /dashboards/admin | 〃 | 매장 소속 계정이 `?storeId=` 조작 | 무시되고 항상 본인 매장만 조회(IDOR 차단) | admin/gerente | dashboard-admin.controller.ts:53-60 | ⬜ |
| A-08 | /sucursales | Admin › Sucursales | `Crear` | "Crear Sucursal" 모달, 필드: Nombre de la Sucursal, Dirección Comercial, CUIT (11 dígitos), Punto de venta (AFIP) 등. 저장하면 `POST /branch` 후 "Sucursal creada" | function `crear-sucursal` | APP/views/branches/components/branch/BranchTable.tsx:104-117; APP/views/admin/stores/details/components/ModalBranch.tsx:235-277, 289-503 | ⬜ |
| A-09 | /sucursales | 〃 | 행 `Editar` → `Modificar` | `PUT /branch/:id` 후 "Sucursal actualizada" | `editar-sucursal` | BranchTable.tsx:54-62; ModalBranch.tsx:235, 268 | ⬜ |
| A-10 | /sucursales | 〃 | 행 `Eliminar` | `GET /branch/:id/details`로 caja/terminal 수를 경고하는 window.confirm → `DELETE /branch/:id` → "Sucursal eliminada" | `editar-sucursal` | BranchTable.tsx:31-49, 88-93 | ⬜ |
| A-11 | /sucursales | 〃 | 행 `Agentes de Impresión` / `Integración Web (WordPress)` / `API Key` | 각각 /sucursales/[id]/impresora, /sucursales/[id]/web, ApiKeyModal(`POST /print/config/:id/regenerate-key`)로 연결 | `editar-sucursal` | BranchTable.tsx:64-86; APP/views/branches/components/branch/ApiKeyModal.tsx:88-94 | ⬜ |
| A-12 | /sucursales | 〃 | Cajas 카드 `Crear` → `Agregar` | "Crear Caja" 모달(Nombre o numero de caja, Sucursal). `POST /box` 후 "Caja creada" | `crear-caja` | APP/views/branches/components/box/BoxTable.tsx:123-135; APP/views/branches/components/box/ModalBox.tsx:53-82 | ⬜ |
| A-13 | /sucursales | 〃 | Cajas 행 `Eliminar` / `Restaurar`, 목록 전환 `Ver Eliminados` / `Ver Activos` | 확인 다이얼로그 → `PUT /box/:id` 로 isDeleted 토글 → "Caja eliminada/restaurada exitosamente." | `eliminar-caja` / `restaurar-caja-borrada` / `ver-cajas-borradas` | BoxTable.tsx:31-41, 70-78, 102-120, 159-176 | ⬜ |
| A-14 | /sucursales | 〃 | Cajas 행 `Eliminar Definitivamente` | `DELETE /box/:id` 후 "La caja fue marcada como eliminada exitosamente." | `eliminar-definitivamente-caja` | BoxTable.tsx:44-54, 81-89, 177-192 | ⬜ |
| A-15 | /sucursales | 〃 | Terminales `Crear` | "Crear Terminal" 모달(Caja, Comandera (Térmica), Zebra). `POST /terminal` | `crear-terminal` | APP/views/branches/components/terminal/TerminalTable.tsx:139-149; APP/views/branches/components/terminal/ModalTerminal.tsx:91-193 | ⬜ |
| A-16 | /sucursales | 〃 | Precios por Sucursal 셀 토글 / `Habilitar todos los precios` | `PUT /branch/:id/price-types-disabled` 후 "Todos los precios activados" | `ver-sucursales` | APP/views/branches/components/priceConfig/BranchPriceTypesCard.tsx:115, 155, 179, 330 | ⬜ |
| A-17 | /sucursales | 〃 | 에이전트 `Crear` / `Regenerar API Key` / `Eliminar` | `POST /print/agents` → "Agente creado"; `…/regenerate-key` → "API Key regenerada. El agente deberá reconfigurarse."; `DELETE` → "Agente eliminado". 지점이 0개면 Crear 비활성 | `crear-terminal` / `editar-terminal` / `eliminar-caja` | APP/views/branches/components/agents/AgentsTable.tsx:70-97, 103-160; APP/views/branches/components/agents/ModalAgent.tsx:60-71 | ⬜ |
| A-18 | /sucursales/[id]/impresora | Sucursales 행 `Agentes de Impresión` | `+ Agregar Agente` → Tipo, Nombre del agente → `Crear` | `POST /print/agents` 후 카드 추가. 목록이 없으면 "No hay agentes configurados…" | app admin + module sucursales | APP/pages/sucursales/[id]/impresora.tsx:23-28; APP/views/branches/components/printer/PrinterConfigTab.tsx:258, 318-327, 520-549 | ⬜ |
| A-19 | /sucursales/[id]/impresora | 〃 | `🖨 Imprimir prueba` | 온라인일 때만 활성. `POST /print/agents/:id/test` 결과 칩: "✅ Impresión confirmada", "⚠️ Sin respuesta del agente", "🔴 Agente desconectado" | 〃 | PrinterConfigTab.tsx:221-236, 406-451 | ⬜ |
| A-20 | /sucursales/[id]/impresora | 〃 | 라벨 클릭해 이름 변경 / `Regenerar Key` / `Eliminar` | `PUT` 라벨 변경; confirm 후 regenerate-key; confirm 후 `DELETE /print/agents/:id` | 〃 | PrinterConfigTab.tsx:156-207, 336-354, 418-433 | ⬜ |
| A-21 | /sucursales/[id]/impresora | 〃 | 다운로드 `Windows (.exe)` 등 6개 | Térmica/Zebra 설치 파일 다운로드 | 〃 | PrinterConfigTab.tsx:458-497 | ⬜ |
| A-22 | /sucursales/[id]/web | Sucursales 행 `Integración Web (WordPress)`, 또는 Configuración › Integraciones › WooCommerce | `Crear canal Web` | 채널이 없으면 안내와 버튼 표시 → `POST /integrations/wp/channels` → "Canal creado" | app admin + module sucursales | APP/pages/sucursales/[id]/web.tsx:61-67; APP/views/branches/components/wp/WpConfigTab.tsx:146-149, 331-336 | ⬜ |
| A-23 | /sucursales/[id]/web | 〃 | `Regenerar Secret` / `Probar conexión` / `Guardar configuración` / `⟳ Resincronizar todo el catálogo` | 각각 confirm 후 regenerate-secret; "Conexión correcta" 또는 "Falló la conexión"; "Configuración guardada"; confirm 후 resync | 〃 | WpConfigTab.tsx:177-277, 418-424, 467-474, 571-580 | ⬜ |
| A-24 | /usuarios | Admin › Usuarios | `Crear` → Nombre, Apellido, Email, Contraseña, Repetir Contraseña, Rol, Sucursal → `Agregar` | `POST /users/admin-create` 후 "Usuario creado". 이름·성은 3자 이상, 비밀번호는 4자 이상 | `crear-usuario` | APP/views/users/UsersListView.tsx:143-155; APP/views/users/components/ModalUser.tsx:119-139, 158-283; APP/views/users/components/DataConfig.tsx:95-108 | ⬜ |
| A-25 | /usuarios | 〃 | 행 `Editar` → `Modificar` | 비밀번호 칸 없음. `PUT /users/:id` 후 "Usuario actualizado" | `editar-usuario` | UsersListView.tsx:99-105; ModalUser.tsx:113-126, 194 | ⬜ |
| A-26 | /usuarios | 〃 | 행 `Desactivar usuario` → `Confirmar` | `DELETE /users/:id` 후 "Usuario … desactivado." 본인 계정이면 "No puede desactivar su propio usuario." | `eliminar-usuario` | UsersListView.tsx:62-95, 117-123 | ⬜ |
| A-27 | /usuarios | 〃 | 행 `Permisos por Usuario` → 토글 → `Guardar` / 🔄 → `Si, restablecer` | `PUT /user-functions/actions/:id` 후 "Permisos actualizados (n personalizados)."; `POST /user-functions/reset/:id` 후 "Permisos restablecidos al rol base" | privileged 역할만 버튼 노출 | UsersListView.tsx:107-116; APP/views/users/components/UserPermissionsDrawer.tsx:205-228, 427-461 | ⬜ |
| A-28 | /usuarios | 〃 | 역할 카드 `Permisos por Rol` → `Guardar` | 변경이 0이면 비활성. `PUT /role-functions/bulk-actions/:roleId` 후 "Permisos de "…" guardados" | privileged | APP/views/users/roles/RoleCards.tsx:37, 85-89; APP/views/users/roles/RolePermissionsDrawer.tsx:160-161, 363-371 | ⬜ |
| A-29 | /admin/auditoria | Admin › Auditoría | 검색창 "Buscar en descripción…" 입력 | 350ms 디바운스 후 `GET /audit-log` 재조회, 페이지는 0으로 | app admin + module logs-auditoria | APP/pages/admin/auditoria/index.tsx:9; APP/views/admin/audit/LogsAuditView.tsx:22-56, 123-141 | ⬜ |
| A-30 | /admin/auditoria | 〃 | 필터 Módulo / Acción / ID Tienda / Fecha Desde / Fecha Hasta | 목록 필터링. 비 superadmin은 storeId 필터를 넣어도 자기 매장으로 고정 | 〃 | APP/views/admin/audit/components/DataConfig.tsx:116-155; API/app/audit-log/audit-log.controller.ts:25-43 | ⬜ |
| A-31 | /admin/auditoria | 〃 | 행 `Ver Detalle`(👁) | AuditLogDetail 모달이 열림 | 〃 | LogsAuditView.tsx:92-103, 151-155 | ⬜ |
| A-32 | /mi-suscripcion | Admin › Mi suscripción | 진입 | `GET /billing/mis-facturas`, `/billing/mis-comprobantes`. 발행분이 없으면 "Todavía no hay facturas emitidas" | app admin | APP/pages/mi-suscripcion/index.tsx:18; APP/views/billing/MiSuscripcionView.tsx:37-46, 84 | ⬜ |
| A-33 | /mi-suscripcion | 〃 | `Enviar comprobante de pago` → Importe depositado, Fecha, Medio de pago, `Adjuntar comprobante` → `Enviar comprobante` | 금액 > 0, 날짜, 결제수단이 있어야 활성. 파일 업로드 후 `POST /billing/comprobantes` → "Comprobante enviado — lo vamos a revisar" | 잔액 > 0 (0이면 "Sin saldo pendiente" 비활성) | MiSuscripcionView.tsx:193-203; APP/views/billing/EnviarComprobanteDialog.tsx:61, 73-90, 112-188 | ⬜ |
| A-34 | /mi-suscripcion | 〃 | 증빙이 pending인 상태에서 재진입 | 버튼 대신 "Ya enviaste un comprobante el … lo estamos revisando." / 거부되면 "Comprobante rechazado — necesitamos que lo revises" | 〃 | MiSuscripcionView.tsx:100, 187-191 | ⬜ |
| C-01 | /tesoreria | 사이드바 Tesorería(directPath) | 진입 | 권한 URL로 탭 노출: /caja→Estado de Caja·Cheques, /control-de-caja→Registros, /gastos→Gastos | structure 모듈 url (superadmin은 전부) | APP/navigation/menuRegistry.ts:314-333; APP/views/tesoreria/tesoreriaTabs.ts:52-60 | ⬜ |
| C-02 | /tesoreria | 〃 | 허용 탭 0개 사용자 | 빈 화면이 아니라 /unauthorized로 replace | — | APP/pages/tesoreria/index.tsx:32-44 | ⬜ |
| C-03 | /tesoreria (Estado de Caja) = /caja | 탭 Estado de Caja, 또는 /caja 직접 | 진입 | Caja Fuerte 요약 → Cajas → pendientes de arqueo → Cierres y transferencias → Cobros que no pasaron por el cajón 순서로 표시 | `ver-cajas` 또는 `ver-resumen-de-su-caja` (둘 다 없으면 카드 없음) | APP/views/box/BoxResume.tsx:30-52; APP/pages/caja/index.tsx:10 | ⬜ |
| C-04 | 사이드바 하단 (모든 화면) | 사이드바 푸터 | `Inicia tu caja` → "Selecciona Caja y Terminal" → Caja/Terminal/Monto inicial → `Confirmar` | `POST /cash-register/open` 후 "Caja y terminal abiertas correctamente. ¡Listo para operar!" | 비 superadmin, 열린 caja 없음. API: admin, gerente, vendedor | APP/layouts/components/vertical/SidebarFooter.tsx:131-148, 424-450; APP/components/modals/SelectBoxTerminalModal.tsx:252-273, 434-436; API/app/cashRegister/cashRegister.controller.ts:335-350 | ⬜ |
| C-05 | 〃 | 〃 | 이미 열린 서랍(Box)을 선택 | "Esta caja ya ha sido inicializada por … Monto inicial registrado: $…" 표시, 금액 입력 없음. 서버는 새 세션을 만들지 않고 기존 세션을 돌려줌(재개시 없음). 기존 금액이 0이면 선언액만 올려 씀 | 규칙: 서랍 단위, 한 번 열면 다시 열지 않음 | SelectBoxTerminalModal.tsx:193-205, 262-264; API/app/cashRegister/cashRegister.service.ts:184-249 | ⬜ |
| C-06 | 〃 | 〃 | 전날 미마감 서랍 모드 → `Confirmar` | "El saldo de la caja anterior fue de $…" 안내 → `POST /cash-register/auto-close-reopen` → "Caja anterior cerrada automáticamente. $… transferido a Caja Fuerte." | unclosed-previous 존재 시 | SelectBoxTerminalModal.tsx:89-97, 290-340, 357-378; cashRegister.controller.ts:142-148 | ⬜ |
| C-07 | /caja (Estado de Caja) | 〃 | Cajas 카드 행 상태 칩 | "Abierta" / "Sin cerrar {fecha}" / "Cerrada {fecha}" / "Sin registros" + "+n registros sin cerrar", "Mi caja". 지점 헤더에 수표 칩 | 〃 | APP/views/box/components/CajasOverviewCard.tsx:96-98, 155-167, 208-268 | ⬜ |
| C-08 | /caja | 〃 | 행 `Ver detalle` | 인라인으로 Resumen de Caja 펼침. 내 서랍이 아니면 readOnly(버튼 숨김). cashRegisterId가 없으면 비활성 | 〃 | CajasOverviewCard.tsx:272-298; APP/views/box/components/BoxInlineDetail.tsx:118-131 | ⬜ |
| C-09 | /caja (내 서랍 상세) | 〃 | `Registrar Movimiento` → Tipo de operación(Ingreso/Retiro/Gasto), Origen del dinero(Caja (turno)/Caja Fuerte (sucursal)), Descripción, Monto → `Registrar` | `POST /box-operation/manual` 후 "Operación registrada correctamente". Ingreso를 고르면 origin이 caja로 강제 | `registrar-movimiento-de-caja`. Origen 칸은 `elegir-origen-de-movimiento` 필요 | APP/views/box/components/BoxSummaryCard.tsx:59-69; APP/views/box/components/ModalOperation.tsx:21-24, 43-53, 63-72, 88-134 | ⬜ |
| C-10 | /caja (내 서랍 상세) | 〃 | `Cerrar Caja` → "Confirmar cierre de caja" → `Cerrar Caja` | `POST /cash-register/close/:id` 후 "Caja cerrada exitosamente" | `cerrar-caja`, 열린 상태, readOnly 아님 | BoxSummaryCard.tsx:36-50, 71-89 | ⬜ |
| C-11 | /caja | 〃 | "Cajas pendientes de arqueo" `Arquear` → Efectivo contado, Motivo(3자 이상) → `Confirmar arqueo` | `POST /cash-register/settlement-queue/:boxId/regularize` 후 "Arqueo registrado. $… enviado a caja fuerte." 큐가 0이면 카드 자체가 안 보임 | API: admin, superadmin만 | APP/views/box/components/BoxSettlementQueueCard.tsx:56, 72, 153-156; APP/views/box/components/ModalArqueo.tsx:37-72; cashRegister.controller.ts:198-213 | ⬜ |
| C-12 | /caja | 〃 | "Cierres y transferencias" `Ver` → 칩 `Solo a revisar` | `GET /cash-register/settlements` 목록(A caja fuerte, Origen, Estado Revisar/OK)과 페이지 이동 | 〃 | APP/views/box/components/BoxSettlementsCard.tsx:65, 88-180 | ⬜ |
| C-13 | /caja | 〃 | "Cobros que no pasaron por el cajón" `Ver` | `GET /credit/cobros-no-efectivo`. 서랍 잔액에 합산되지 않음 | 〃 | APP/views/box/components/CobrosNoEfectivoCard.tsx:72, 92-127 | ⬜ |
| C-14 | /caja (Caja Fuerte 요약) | 〃 | 지점 행 `Retirar` / `Ver detalle` | 출금 모달이 열림 / `/caja-fuerte?branchId=` 로 이동. 잔액 ≤ 0이면 Retirar 비활성 | privileged만 카드 노출 | APP/views/caja-fuerte/components/CajaFuerteSummaryCard.tsx:69-70, 114, 166-183 | ⬜ |
| C-15 | /tesoreria (Registros) = /control-de-caja | 탭 Registros | Cajas 행 `Ver registros` / `Ver Detalle` | 아래 Control de Caja가 해당 박스로 필터됨 / `/caja/detalle/:id`로 이동 | `ver-cajas-control`, `ver-los-registros-de-la-caja`, `ver-el-detalle-de-la-caja` | APP/views/cash-control/list/CashRegisterList.tsx:17-26; APP/views/cash-control/list/components/BoxControlList.tsx:51-70 | ⬜ |
| C-16 | /control-de-caja | 〃 | 필터 Fecha / Terminal / Sucursal / Usuarios → `Filtrar` / `Limpiar` | 세션 목록 재조회 | `ver-control-de-caja` | APP/views/cash-control/list/components/CashControlFilters.tsx:54-141 | ⬜ |
| C-17 | /control-de-caja | 〃 | 세션 행 `Cerrar Caja`(🔒) | 확인 없이 즉시 `POST /cash-register/close/:id` 후 목록 갱신. 닫힌 행에는 아이콘 없음 | `cerrar-caja-control` | APP/views/cash-control/list/components/CashControlList.tsx:105-130 | ⬜ |
| C-18 | /control-de-caja | 〃 | `Cambiar monto inicial` → Monto inicial → `Declarar` | 미선언(0)일 때 `POST /cash-register/:id/monto-inicial`, 금고 출금도 기록. 이미 선언됐거나 마감이면 "Monto inicial ya declarado"/"Caja cerrada" 읽기 전용 + `Registrar movimiento`(→/caja) | `cambiar-monto-inicial-de-caja` | CashControlList.tsx:142-150; APP/views/cash-control/list/components/ModalCashRegister.tsx:43-44, 87-90, 96-169; cashRegister.controller.ts:44-48 | ⬜ |
| C-19 | /control-de-caja | 〃 | Caja Mercadopago `Transferir →` → Caja destino, Monto(25/50/100% 버튼) → `Confirmar transferencia` | `POST /mercadopago/transfers` 후 "✓ Transferencia registrada — $ … de Caja MP a …" | 역할 admin, superadmin, gerente(하드코딩) | APP/views/cash-control/components/McdpgWalletRow.tsx:35-37, 95-114; APP/views/cash-control/components/McdpgTransferModal.tsx:101-107, 196-208 | ⬜ |
| C-20 | /control-de-caja/detalle/[id] | Control de Caja 행 `Ver Detalle` | 진입 | 세션 Resumen de Caja(Monto inicial, Ventas, Ingresos, Gastos, Retiros, Saldo final)와 Operaciones de Caja 표시 | `ver-resumen-de-registro-de-caja`, module control-de-cajas | APP/pages/control-de-caja/detalle/[id].tsx:9; APP/views/cash-control/detail/cash-register/CashControlDetail.tsx:19-33, 62-63; BoxSummaryCard.tsx:127-133 | ⬜ |
| C-21 | /caja/detalle/[id] | Registros › Cajas 행 `Ver Detalle` | 필터 Fecha / Usuario / Terminal | `GET /cash-register/box/:id/resume`, 첫 세션 요약과 작업 목록 | module caja | APP/pages/caja/detalle/[id].tsx:9; APP/views/cash-control/detail/box-register/BoxControlDetail.tsx:29, 55-57 | ⬜ |
| C-22 | /tesoreria (Cheques) = /cheques | 탭 Cheques, 대시보드 Cheques 위젯 | 칩 En cartera / Usados / Depositados / Rechazados / Todos, 검색 "Buscar Nº / banco / titular" | `GET /cheques?status=`와 KPI(`/cheques/summary`) | 페이지 가드 없음. GET API는 vendedor도 허용 | APP/pages/cheques/index.tsx:9-11; APP/views/cheques/ChequesView.tsx:36-42, 87-88, 164-185; API/app/cheques/cheques.controller.ts:13-19 | ⬜ |
| C-23 | /cheques | 〃 | EN_CARTERA 행 `Depositar` → `Confirmar` | `PUT /cheques/:id/depositar` 후 "Cheque marcado como depositado" | API: admin, superadmin, gerente | ChequesView.tsx:104-105, 285-293, 339-367; cheques.controller.ts:77-78 | ⬜ |
| C-24 | /cheques | 〃 | EN_CARTERA/DEPOSITADO 행 `Rechazar` → Notas (motivo del rechazo) → `Confirmar` | `PUT /cheques/:id/rechazar` 후 "Cheque marcado como rechazado" | 〃 | ChequesView.tsx:107-108, 294-311, 348-357; cheques.controller.ts:84-85 | ⬜ |
| C-25 | /caja-fuerte | Estado de Caja › Caja Fuerte `Ver detalle` | 지점 버튼 선택(지점 2개 이상) | 잔액 카드, 일별(`/caja-fuerte/:id/daily`), 이동 표 전환. 볼 수 없는 지점이면 경고 Alert만 | module caja. API GET은 admin, superadmin, gerente | APP/pages/caja-fuerte/index.tsx:9; APP/views/caja-fuerte/CajaFuerteView.tsx:53, 279-302, 359-372; API/app/caja-fuerte/caja-fuerte.controller.ts:113-205 | ⬜ |
| C-26 | /caja-fuerte | 〃 | `Retirar de Caja Fuerte` → Monto a retirar, "Motivo frecuente" 칩, Motivo del retiro, Contraseña (confirmación) → `Confirmar Retiro` | 금액 ≥ 1, 사유 ≥ 3자, 비밀번호 필수. 잔액 재확인 후 `POST /caja-fuerte/withdrawal` → "Retiro de $… realizado exitosamente"; 잔액 초과면 "Saldo insuficiente…" | privileged. API는 admin, superadmin | CajaFuerteView.tsx:274, 312-324; APP/views/caja-fuerte/components/ModalWithdrawal.tsx:59-74, 160-225; APP/views/caja-fuerte/hooks/useCajaFuerte.ts:247; caja-fuerte.controller.ts:296-298 | ⬜ |
| C-27 | /caja-fuerte | 〃 | `Contar caja fuerte` → Monto contado, Nota → `Registrar arqueo` / `Ver historial` | `POST /caja-fuerte/:id/arqueo` / "Historial de arqueos" 모달(`GET …/arqueos`) | API: admin, superadmin, gerente | APP/views/caja-fuerte/components/CajaFuerteArqueoBand.tsx:60-69; CajaFuerteView.tsx:143, 174; APP/views/caja-fuerte/components/ModalArqueo.tsx:56-115; caja-fuerte.controller.ts:229-273 | ⬜ |
| C-28 | /caja-fuerte | 〃 | 토글 Todo / Solo entradas/salidas / Solo cajas, 7d / 30d / Todo | 이동 표와 일별 패널이 같은 기간으로 재조회 | 〃 | APP/views/caja-fuerte/components/CajaFuerteOperationsTable.tsx:277-297 | ⬜ |
| C-29 | /tesoreria (Gastos) = /gastos | 탭 Gastos | 필터 Descripción / Sucursal / Fecha desde / Fecha hasta | `GET /expenses/search` | app venta + module gastos | APP/pages/gastos/index.tsx:10; APP/views/expenses/ExpensesView.tsx:17-41, 114 | ⬜ |
| C-30 | /gastos | 〃 | `Crear` → Categoría, Motivo de Gasto, Monto, Fecha, Sucursal, Efectivo (caja)/Cheque en cartera, Afecta caja | `POST /expenses` 후 "Gasto creado". 열린 caja 없이 "Afecta caja"면 "Debe abrir una caja para poder registrar un gasto que afecte caja." | 버튼 권한 게이트 없음 | ExpensesView.tsx:248-258; APP/views/expenses/components/ExpenseModal.tsx:331-359, 379-500 | ⬜ |
| C-31 | /gastos | 〃 | 행 `Editar` | "Editar gasto" 후 "Gasto actualizado". caja가 마감됐으면 🔒 "Caja cerrada — el gasto ya no se puede modificar" | `modificar-gasto` | ExpensesView.tsx:69, 182-207; ExpenseModal.tsx:342-350 | ⬜ |
| C-32 | /gastos | 〃 | 행 `Eliminar` → (수표면) "Confirmo que los cheques siguen en mi poder" 체크 → `Eliminar` | `DELETE /expenses/:id[?confirmChequesInHand=true]` 후 "Gasto eliminado". 수표인데 체크 안 하면 toast로 거부. 연결 이전(link 없는) 건은 비활성 | `borrar-gasto` | ExpensesView.tsx:70, 149-170, 209-230, 272-321 | ⬜ |
| S-01 | /configuracion | Admin › Configuración | 좌측 탭 클릭 | `?tab=<key>`로 shallow replace. 권한 없는 키나 없는 키는 첫 탭으로 fallback | 탭별 requiredApps / Modules / Privileged | APP/pages/configuracion/index.tsx:56-120 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-02 | Datos de la tienda | `?tab=datos-tienda` | Razón social, Nombre comercial (alias), CUIT, Condición frente al IVA, Dirección → `Guardar datos` | `PUT /store/:id` 후 "Datos actualizados" | requiredApps admin + **requiredPrivileged** | index.tsx:57; APP/views/configuracion/tienda/DatosTiendaView.tsx:87-95, 149-209 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-03 | Datos de la tienda | 〃 | `Elegir imagen` → `Subir logo` | `putFile /store/:id` 후 "Logo actualizado" | 〃 | DatosTiendaView.tsx:112-118, 235-251 | ⬜ |
| S-04 | Preferencias | `?tab=preferencias` | 하위 탭 Ventas / Precios / Gastos / Pantalla de ingreso | Ventas: Inventario, Modo Restaurante, Envíos (Despacho). Precios: Niveles de Precio. Gastos: Categorías de Gastos. Ingreso: Frase del día | requiredApps admin | index.tsx:58; APP/pages/configuracion/preferencias/index.tsx:88-136 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-05 | Facturación | `?tab=facturacion` | 스위치 "Facturación electrónica habilitada/Deshabilitada", % por defecto 슬라이더·입력 | `PUT /store-config/:id/update-flag` (useFacturaElectronica), `PATCH …/update-digits` (afipDefaultPct) 후 "% por defecto: n%" | requiredApps admin. API는 admin, superadmin | index.tsx:62; APP/views/configuracion/facturacion/FacturacionPrefsView.tsx:77-107, 141-185; API/app/store/config/storeConfig.controller.ts:87-99, 154-156 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-06 | Integraciones | `?tab=integraciones` | 카드 WooCommerce | 지점 1개면 /sucursales/:id/web, 여러 개면 지점 메뉴 | requiredApps admin | index.tsx:63; APP/views/configuracion/integraciones/IntegracionesHubView.tsx:130-141, 148, 271-283 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-07 | Integraciones | 〃 | 카드 Sincronización automática / Mercadopago / WhatsApp / Campañas (WhatsApp masivo) | /configuracion/integraciones/sincronizacion, /configuracion/mercadopago, /configuracion/whatsapp, /configuracion/campanas로 이동 | 〃 | IntegracionesHubView.tsx:159-164, 204-233 | ⬜ |
| S-08 | Integraciones | 〃 | EmpreTienda / MercadoLibre / Signo / Telegram(/TiendaNube 미연결) | "Próximamente" 칩, 카드 비활성(opacity 0.6) | 〃 | IntegracionesHubView.tsx:43, 55-61, 167-240 | ⬜ |
| S-09 | Permisos | `?tab=permisos` | 하위 탭 권한 매트릭스 / 사용자 상세 / 감사 로그 / 승인 임계값 | Matrix(`GET /permissions/matrix`), 사용자별 지점·모바일 터미널 선택(`PUT /permissions/users/:id/branches/:b/mobile-terminal`), 임계값은 조회 전용 | app admin + module configuracion-permisos | index.tsx:64; APP/views/configuracion/permisos/PermissionsView.tsx:40-96; APP/views/configuracion/permisos/UserDetail.tsx:68-90; APP/hooks/api/usePermissionsMatrix.ts:29-30 | ❌ 실측: 탭 전체가 한국어(21개 문구). 「Resource 권한 데이터 없음」은 데이터 부재가 아니다 — API 는 134행(200)을 주지만 권한 slug 가 전부 `x.y` 형태라 분류 규칙(`includes('.')`, MatrixGrid.tsx:119-123)이 모두 Business Action 표로 보낸다 |
| S-10 | Referidos | `?tab=referidos` | 복사 아이콘 `Copiar apodo` | "Apodo copiado"; "n referidos", "Bonificado: …" 칩과 목록(`GET /onboarding/referral/mine`) | requiredApps admin | index.tsx:65; APP/views/configuracion/referidos/ReferidosView.tsx:50-66, 102-153 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-11 | Ventas | `?tab=ventas` | Métodos de Pago / Vendedores / Descuentos / Recargos / Transportes CRUD·활성 토글 | 각각 `/payment-methods`, `/sellers`, `/discounts`, `/recharges`, `/transportes` API 호출 | app venta + module configuracion-ventas | index.tsx:66; APP/views/config/ventas/ConfigurationSalesView.tsx:13-27; APP/views/config/ventas/paymentMethods/list/PaymentMethodsList.tsx:38-105, 133 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-12 | Productos | `?tab=productos` | Categorías / Subcategorías / Proveedores / Colores / Tallas / Temporadas / Origen 목록 | 별칭(alias)이 있으면 제목이 바뀜, `GET /store-config/:id` | requiredApps producto (모듈 조건 없음) | index.tsx:67; APP/views/config/productos/ConfigurationView.tsx:51, 64-122 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-13 | Envíos | `?tab=envios` | 스위치 "Activado/Desactivado" | update-flag `useEnvios` 후 "Modo envíos activado/desactivado", TransporteCard 표시 | requiredApps admin | index.tsx:68; APP/views/configuracion/transporte/EnviosConfigView.tsx:66-71, 118-134 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-14 | Inventario | `?tab=inventario` | "Permitir venta sin stock" 스위치; "Aviso de pedidos sin pagar…" Días → `Guardar` | flag `allowSaleWithoutStock` 후 "Venta sin stock habilitada/deshabilitada"; digits `unpaidHoldAlertDays`(1~3650) 후 "Aviso configurado a los n días" | requiredApps admin | index.tsx:69; APP/views/configuracion/inventario/InventarioConfigView.tsx:65-99, 124-180 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-15 | QR del producto | `?tab=qr` | 스위치 Habilitado/Deshabilitado | flag `qrPrecioPublico` 후 "El QR ahora abre la ficha del producto." | admin + **requiredPrivileged** | index.tsx:70; APP/views/configuracion/qr/QrConfigView.tsx:53-62, 107 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-16 | Prueba Virtual (IA) | `?tab=prueba-virtual` | 스위치 Habilitada/Deshabilitada, 월 선택 | flag `vtoEnabled` 후 "Prueba Virtual habilitada"; `GET /vto/usage?month=` (Por vendedor / Por dispositivo). 0건이면 "Sin generaciones este mes" | requiredApps admin | index.tsx:71; APP/views/configuracion/vto/VtoConfigView.tsx:73-100, 140-232 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-17 | Tienda Online | `?tab=tienda-online` | 공개몰 스위치 / 공개 주소 `저장` / `🎨 홈페이지 디자인 편집` | `PUT /shop/:id/theme/enabled`, `PUT /shop/:id/slug`, `POST /shop/:id/theme/edit-link`(새 탭). 편집 버튼은 공개몰이 켜져 있을 때만 | requiredApps admin | index.tsx:72; APP/components/StorefrontDesignCard.tsx:104-177; APP/components/ThemeEditButton.tsx:23-37; APP/services/store-theme.service.ts:29-75 | ❌ 실측: 카드 문구 한국어 8개 (`내 공개몰 (홈페이지)` `저장` `홈페이지 디자인 편집`…) |
| S-18 | Campañas | `?tab=campanas` | WABA ID, Phone Number ID, Access Token … → `Guardar` | `PUT /store-whatsapp-config/:id` 후 "Configuración de WhatsApp guardada", 칩 "Listo para enviar/Incompleto" | requiredApps admin | index.tsx:82; APP/views/configuracion/campanas/WhatsappCampaignConfigView.tsx:75-81, 132-196 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-19 | Campañas | 〃 | Nombre de la campaña, plantilla, Idioma → `Calcular alcance y costo` → `Acepto y enviar (US$ …)` | `/campaigns/preview-count` → `POST /campaigns` → `POST /campaigns/:id/enqueue` 후 "Campaña encolada — se enviará en breve" | 〃 | APP/views/configuracion/campanas/CampaignBuilderSection.tsx:100-142, 167-200, 245-268 | ⬜ |
| S-20 | Campañas | 〃 | 고객 검색 → 행별 WhatsApp 동의 토글 | `PUT` 동의 저장, "En esta página: n con consentimiento" | 〃 | APP/views/configuracion/campanas/WhatsappConsentSection.tsx:60-129, 171-188 | ⬜ |
| S-21 | Generar Token | `?tab=generar-token` | `Generar Token` | `POST /support-token/generate` → "Token de Soporte Técnico" 다이얼로그에 5분 카운트다운 | requiredApps admin | index.tsx:83; APP/pages/admin/generar-token.tsx:22-37, 64-70, 163-169 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-22 | Generar Token | 〃 | `Mandar Token a CoolSistema` / `Regenerar` / `Generar nuevo` / `Cerrar` | openChat 이벤트와 chatSendMessage로 AI 채팅에 토큰 전송 / 토큰 재발급 / 다이얼로그 닫힘 | 〃 | generar-token.tsx:175-210; APP/components/chat/ChatBubble.tsx:40-42; APP/components/chat/ChatWindow.tsx:65 | ⬜ |
| S-23 | Importar Legacy | `?tab=importar-legacy` | Stepper Subir archivo → Vista previa → Procesando → Resultado; 파일 선택(.sql/.backup/.dump/.gz…) | `sendFile /legacy-import/preview` 후 테이블 매핑 미리보기 | requiredApps admin | index.tsx:84; APP/views/legacy-import/ImportLegacyView.tsx:120, 243, 370, 407-435 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| S-24 | Importar Legacy | 〃 | 정책 "Saltar (no tocar los existentes)" / "Actualizar (sobrescribir…)" → `Importar a mi tienda` → `Importar otro archivo` | `/legacy-import/upload?policy=` 후 "Importación finalizada con éxito." / "Importación parcial…" 와 요약 카드 | 〃 | ImportLegacyView.tsx:261-272, 460-466, 506-515, 596-612 | ⬜ |
| S-25 | /guia-configuracion | 사이드바 "Guía de configuración" | 단계 CTA `Revisar datos` / `Ver sucursales` / `Ver caja` / `Cargar productos` / `Definir precios` / `Revisar medios de pago` / `Conectar impresora` | 각 href로 이동(/configuracion?tab=datos-tienda, /sucursales, /caja, /productos, /precios, /configuracion?tab=ventas, /nueva-venta). 대상 페이지는 모두 존재 확인 | 서버가 `user.setupGuide`를 준 사용자만 메뉴 노출(관리자 + 지점장) | APP/navigation/vertical/index.ts:81, 94; APP/views/setup-guide/setup-guide.catalog.ts:43-105; APP/views/setup-guide/SetupGuide.tsx:286 | ⬜ |
| S-26 | /guia-configuracion | 〃 | `No aplica` / `Más tarde` / `Deshacer` | `PATCH /setup-guide/steps/:code` (dismiss / snooze 7일 / undismiss) 후 재조회 | 〃 | SetupGuide.tsx:100-112, 268-297 | ⬜ |
| S-27 | /guia-configuracion | 〃 | `Ocultar guía` → `Volver a mostrarla` | `PATCH /setup-guide/visibility {hidden:true/false}`. 숨기면 "Ocultaste la guía de configuración." 표시. 자동 중단 상태면 "Ya configuraste lo esencial…" 안내 | 〃 | SetupGuide.tsx:124, 385-387; APP/views/setup-guide/SetupGuideOculta.tsx:31, 45-51; APP/views/setup-guide/SetupGuidePanel.tsx:60-68 | ⬜ |
| S-28 | /perfil | Herramientas › Mi perfil (ACL 없음) | `Cambiar Contraseña` → Contraseña actual, Nueva contraseña(6자 이상), Confirmar → `Actualizar` | 불일치면 "Las contraseñas no coinciden"; `PUT /auth/change-password` 후 "Contraseña actualizada exitosamente" | 모든 로그인 사용자 | APP/navigation/menuRegistry.ts:348; APP/views/profile/components/AboutOverivew.tsx:76-83; APP/views/profile/components/ModalChangePassword.tsx:13-25, 63-86 | ⬜ |
| S-29 | /perfil | 〃 | Mis datos `Editar` → Nombre, Apellido, Nombre de Usuario, Email | `PUT /users/:id` 후 "Usuario actualizado exitosamente" | 모든 사용자 | AboutOverivew.tsx:84-91; APP/views/profile/components/ModalEditUser.tsx:13-16, 75-81 | ⬜ |
| S-30 | /perfil | 〃 | 매장 헤더 `Editar` | ModalEditStore → `PUT /store/:id` | privileged만 | APP/views/profile/components/UserProfileHeader.tsx:160-167; APP/views/profile/components/ModalEditStore.tsx:98 | ⬜ |
| S-31 | /perfil | 〃 | "Módulo de Integraciones" 스위치 | `POST /store/:id/integration/toggle` | 역할 게이트 없음 | APP/views/profile/components/Information.tsx:17-64 | ⬜ |
| S-32 | /carpetas-compartidas | 미확인 (코드에 사이드바 링크 없음. DB 모듈에 의존하는 것으로 추정) | 폴더 카드 클릭 | `GET /carpetas-compartidas` 카드(Editor/Solo lectura) → /carpetas-compartidas/:id. 없으면 "Aún no hay carpetas asignadas…" | app admin | APP/pages/carpetas-compartidas/index.tsx:13; APP/views/carpetas-compartidas/SharedFoldersListView.tsx:16-48; APP/views/carpetas-compartidas/FolderCard.tsx:25, 53 | ⬜ |
| S-33 | /carpetas-compartidas/[folderId] | 폴더 카드 | `Subir archivo` (최대 50 MB) | XHR `POST /api/carpetas-compartidas/:id/files` 진행률 표시, 초과 시 크기 오류 | canWrite만 버튼 노출 | APP/views/carpetas-compartidas/FolderToolbar.tsx:37-45; APP/views/carpetas-compartidas/FileUploadDropzone.tsx:23, 47, 99 | ⬜ |
| S-34 | /carpetas-compartidas/[folderId] | 〃 | 행 `Descargar` / `Renombrar` / `Mover a papelera de Google Drive` | blob 다운로드 / `PUT …/files/:fileId` 후 이름 변경 toast / `DELETE` 후 휴지통(30일 복구 안내) | Renombrar·삭제는 canWrite | APP/views/carpetas-compartidas/FolderBrowserView.tsx:63-103; APP/views/carpetas-compartidas/FileTable.tsx:88-104 | ⬜ |

### 3. 관리 · 금전함(Tesorería) · 설정 — 코드 판독에서 나온 이상 (미실측)

#### 이상 목록 (Anomalies)

**버그 가능성**
1. **없는 경로로 리다이렉트.** 사용자가 없을 때 `WithAccess`가 `router.push('/auth/login')`을 호출하는데 `pages/auth/`가 없습니다(실제 로그인은 `pages/login`). — `APP/configs/withAccess.tsx:47`, `APP/configs/withAuth.tsx:18`
2. **Resumen de Caja의 "Usuario:"가 틀린 사람을 표시.** 세션을 연 사람이 아니라 현재 로그인한 사용자 이름을 씁니다. — `APP/views/box/components/BoxSummaryCard.tsx:21, 29-30, 116`
3. **`Cerrar Caja` 후 화면이 갱신되지 않음.** 성공 후 새로고침 콜백이 없어 칩이 "Abierta"로 남습니다. — `BoxSummaryCard.tsx:38-50`
4. **Control de Caja의 `Cerrar Caja`에 확인·피드백이 없음.** 확인창도 토스트도 없고, 에러는 console에만 남습니다. — `CashControlList.tsx:105-117`
5. **`Repetir Contraseña`를 검증하지 않음.** yup 스키마에 일치 검사가 없고, `register(...,{required:true})`는 resolver 사용 중이라 무시됩니다. 또 console.log에 비밀번호가 포함된 폼 데이터가 찍힙니다. — `APP/views/users/components/DataConfig.tsx:105-108`, `ModalUser.tsx:85, 111, 142, 223`
6. **권한 slug와 문구 오류.** 터미널 삭제에 `eliminar-caja` slug를 씁니다(`TerminalTable.tsx:86`). 에이전트 삭제도 `eliminar-caja`입니다(`AgentsTable.tsx:127`). 터미널 저장 toast가 "Caja creada/actualizada"로 나옵니다(`ModalTerminal.tsx:99`).
7. **store_owner·store_admin이 MP 이체를 못 함.** `canTransfer` 역할 목록이 하드코딩돼 이 두 역할이 빠지고, `roles.ts` 단일 출처 원칙에도 어긋납니다. 반면 `McdpgDetailModal`의 `Transferir saldo`는 이 게이트 없이 누구에게나 보입니다. — `McdpgWalletRow.tsx:35-37`, `McdpgDetailModal.tsx:187`, `CashControlList.tsx:264-272`

**권한 불일치 (UI에서는 보이는데 API가 403을 줄 수 있음)**
8. **Configuración 저장 탭.** Facturación, Envíos, Inventario, Prueba Virtual, Preferencias는 쓰기 API가 `update-flag`/`update-digits`(@Auth admin, superadmin)인데, 허브 탭에 `requiredPrivileged`가 없습니다. 그래서 gerente에게도 보이고 저장에서 403이 날 가능성이 있습니다. — `index.tsx:58-71`, `storeConfig.controller.ts:87-99`
9. **"Cajas pendientes de arqueo" 카드.** API가 admin/superadmin 전용인데 카드는 `ver-cajas`만 있으면 렌더됩니다. gerente에게는 "No se pudo cargar la cola."가 나올 가능성이 있습니다. — `BoxResume.tsx:43`, `cashRegister.controller.ts:198-199`, `BoxSettlementQueueCard.tsx:59-61`
10. **Cheques.** `/cheques` 페이지에 WithAccess가 없고 GET은 vendedor도 허용합니다. `Depositar`/`Rechazar` 버튼은 모두에게 보이지만 API는 admin, gerente, superadmin만 허용합니다. — `APP/pages/cheques/index.tsx:9-11`, `ChequesView.tsx:285-311`, `cheques.controller.ts:77-85`
11. **Tesorería 메뉴가 권한 없는 사용자에게도 보일 수 있음.** `injectEnd` Cheques 항목에 role 필터가 없어, admin 앱만 있으면 메뉴가 뜹니다. 들어가서 허용 탭이 0개면 /unauthorized로 튑니다. — `menuRegistry.ts:331`, `APP/navigation/vertical/index.ts:194-198`, `APP/pages/tesoreria/index.tsx:37-39`
12. **Gastos `Crear`에 권한 게이트가 없음.** 편집·삭제에는 게이트가 있습니다. — `ExpensesView.tsx:248-258`
13. **Importar Legacy는 JWT만 검사.** 역할 가드가 없고(`@UseGuards(AuthGuard('jwt'))`), 허브 탭도 app admin만 봅니다. — `API/app/legacy-import/legacy-import.controller.ts:118-146`
14. **`POST /store/:storeId/integration/toggle`에 역할·소유 검사가 없음.** 전역 JWT 가드만 있고 storeId를 path에서 받습니다(IDOR 가능성). /perfil에서는 누구나 스위치를 볼 수 있습니다. — `API/app/store/integrations/storeIntegrations.controller.ts:4-18`, `Information.tsx:17`
15. **/perfil에 BranchTable 전체가 들어 있음.** 모든 역할의 프로필 화면에 지점 CRUD 표가 박혀 있고, 버튼만 function slug로 가려집니다. — `ProfileView.tsx:33-41`
16. **셋업 가이드 링크가 틀린 탭으로 감.** `Revisar datos` → `?tab=datos-tienda`는 privileged 전용 탭입니다. 가이드를 받는 지점장은 탭이 숨겨져 첫 탭으로 fallback됩니다. — `setup-guide.catalog.ts:45`, `index.tsx:57, 103, 115`
17. **Productos 탭 게이트 불일치.** 허브 탭은 app만 보지만, 단독 페이지 `/configuracion/productos`는 module `configuracion-productos`까지 요구합니다. — `index.tsx:67`, `APP/pages/configuracion/productos/index.tsx:10`
18. **대시보드 알림 링크가 superadmin 도구로 감.** 매장 관리자용 "sync_outbox acumulado" 알림이 `/admin/diagnostics`로 연결됩니다. — `dashboard-admin.service.ts:655-656`

**작동하지 않는 버튼, 미완성 UI, 화면에 보이는 TODO**
19. **Permisos 탭이 한국어로 표시됨.** 권한 매트릭스, 사용자 상세, 감사 로그, 승인 임계값이 스페인어 UI에 한국어로 나옵니다. 승인 임계값은 "조회 화면 (편집은 후속 SPEC)"이라 고정 데이터만 보여줍니다. `지점 추가 (편집 기능 추후)` 버튼과 지점 행 X 버튼은 영구 disabled입니다. 모바일 터미널 저장 실패는 console에만 남습니다. — `PermissionsView.tsx:40-62`, `ThresholdEditor.tsx:44-50`, `UserDetail.tsx:76-78, 305-320`
20. **Tienda Online 카드가 한국어.** "공개몰 활성화됨", `저장`, `🎨 홈페이지 디자인 편집` 등이 한국어입니다. — `StorefrontDesignCard.tsx:104-177`, `ThemeEditButton.tsx:37`
21. **TiendaNube 카드는 연결돼도 클릭 불가.** "Conectado" 상태여도 onClick/href가 없어 CardActionArea가 disabled입니다. — `IntegracionesHubView.tsx:61, 167-172`
22. **Generar Token 탭은 닫으면 되돌릴 수 없음.** 탭 내용이 Dialog뿐이라 `Cerrar`를 누르면 빈 화면이 되고, 다시 여는 버튼이 없습니다(탭을 옮겼다 와야 함). — `generar-token.tsx:12, 64-66, 198`
23. **Preferencias가 허브 탭과 중복.** Preferencias › Ventas 안에 Inventario와 Envíos 뷰가 한 번 더 들어 있어, 허브의 Inventario·Envíos 탭과 같은 설정이 두 곳에 있습니다. — `APP/pages/configuracion/preferencias/index.tsx:95-110`
24. **Ventas 설정 목록 툴팁이 영어.** 'Edit'/'Remove'로 표시되고 문구에 오타("reacargo")가 있습니다. — `PaymentMethodsList.tsx:77, 84`, `RechargeList.tsx:157`

**미확인 (코드로 확인 못 한 진입 경로)**
25. `/caja-fuerte`, `/gastos`, `/carpetas-compartidas`의 사이드바 진입은 코드 레지스트리에 없습니다. DB 모듈 시드에 의존하는 것으로 보이며, 코드로는 확인하지 못했습니다. 코드상 확인된 진입은 Estado de Caja의 `Ver detalle`(caja-fuerte)와 Tesorería 탭(Gastos) 두 곳입니다.

## 4. 보고서 · 도구 · 로그인

| ID | 화면(경로) | 진입 | 조작 | 기대 결과 | 역할/조건 | 근거 | 실측 |
|---|---|---|---|---|---|---|---|
| R-01 | /reportes-v2 | 사이드바 reportes (directPath) | slug 없이 진입 | 기본으로 Stocks 보고서가 열림 | allowedApps 'reportes' | VA pages/reportes-v2/[[...slug]].tsx:15,18; VA navigation/menuRegistry.ts:286 | ✅ 화면 열림 · 오류 0 · 한국어 0 (조작은 미실측) |
| R-02 | /reportes-v2 | 좌측 사이드바 | `Buscar reporte...` 입력 | 제목·설명으로 필터링됨. 검색 중에는 Recientes/Favoritos가 숨겨짐 | 권한 있는 보고서만 표시 | VA views/reports-v2/ReportsSidebar.tsx:50,106-111,121 | ⬜ |
| R-03 | /reportes-v2 | 사이드바 | 보고서 클릭 / 그룹 `🛒 Ventas` `💰 Finanzas` `📦 Inventario` `👥 Clientes & Control` | shallow 라우팅으로 `/reportes-v2/<slug>` 이동. Clientes는 Ventas와 Clientes 두 그룹에 모두 표시됨 | – | ReportsSidebar.tsx:24-28,96; VA views/reports-v2/registry.ts:199 | ⬜ |
| R-04 | /reportes-v2/* | Topbar | ☆ (`Agregar a favoritos`/`Quitar de favoritos`) | 별 아이콘이 채워지고 `⭐ Favoritos` 섹션에 추가됨(localStorage). `🕒 Recientes`에는 최근 5개가 표시됨 | – | ReportsTopbar.tsx:141-145; ReportsSidebar.tsx:197,212 | ⬜ |
| R-05 | /reportes-v2/* | URL/사이드바 | 권한 없는 보고서 열기 | 자물쇠 아이콘과 `Sin permiso para este reporte` / `Contacte al administrador para solicitar acceso.` 표시 | permissions[slug].read≠true (superadmin 제외) | ReportsShell.tsx:33-41,85-93 | ⬜ |
| R-06 | /reportes-v2/reservado | URL 직접 입력만 가능 | – | 사이드바·검색·최근·즐겨찾기에는 없음. 직접 URL로는 Reservado가 열림(KPI `Reservas` `Monto Total` `Promedio` `Días en período`, 탭 `Tendencia`/`Lista`) | reporte-reservado | registry.ts:243; VR reservado/ReservadoCockpitBody.tsx:264-317 | ⬜ |
| R-07 | /reportes-v2/* | Topbar | 지점 선택 `TOTAL (todas)` / 지점명 | 첫 로드 기본값은 전체 합계. 변경하면 branchId 파라미터가 바뀜. 지점이 없으면 `Sin sucursales` 표시 | filterSchema에 'sucursal'이 있는 보고서 | VA views/reports-v2/components/topbar/SucursalField.tsx:27-30,67,76 | ⬜ |
| R-08 | /reportes-v2/* | Topbar | 기간 선택 (팝오버에 두 달 달력) | 시작일·종료일이 표시되고 params가 갱신되어 재조회됨 | rangeDate 스키마 | DateRangeField.tsx:26,79; ReportsFilterFields.tsx:274-284 | ⬜ |
| R-09 | /reportes-v2/* | Topbar | `Ejecutar` | Body가 등록한 refresh가 실행됨. Vendedor·Enviado·Rotación Temporada는 등록하지 않아 **비활성** | – | ReportsTopbar.tsx:160-169; ReportActionsContext.tsx:45-57 | ❌ 실측: Vendedor·Enviado·Rotación Temporada 에서 off, 나머지 15개 on (코드와 일치) |
| R-10 | /reportes-v2/* | Topbar | `Exportar Excel` / `Exportar PDF` | Stocks·Stock Vistas는 둘 다 활성. Clientes는 «Crédito solo» OFF일 때 Excel만 활성. **그 외 15개 보고서는 둘 다 비활성** | – | ReportsTopbar.tsx:146-159; VR stocks/StocksCockpitBody.tsx:102; VR stock-vistas/StockVistasCockpitBody.tsx:400; VR clientes-credito/ClientesHistorialBody.tsx:41; 그 외 `useReportActionsRegistration({ refresh })` (예: VR sales/SalesCockpitBody.tsx:387) | ❌ 실측: 켜진 것은 Stocks(둘 다)·Stock Vistas(둘 다)·Clientes(Excel) 뿐, 15개는 둘 다 off |
| R-11 | Ventas | 사이드바 | 기간 + `Unidad`(`VCode`/`Day`/`Month`/`Year`) + `Buscar...` | 지점 필드 없음. 거래 목록의 집계 단위가 바뀜 | reporte-ventas | registry.ts:156; ReportsFilterFields.tsx:161-189 | ❌ 실측: KPI·탭이 한국어 (`총 매출` `거래 건수` `평균 객단가` `할인율`…) |
| R-12 | Ventas | – | 단일 지점: KPI `총 매출` `거래 건수` `평균 객단가` `할인율`(vs 전기). 다지점: 지점 표(`Sucursal` `Ventas` `Monto Total` `Descuento` `Ticket Prom.`) 행 클릭 | 행을 클릭하면 `Mostrando:` 칩이 바뀌며 필터됨(`Haga clic en una fila para filtrar`) | – | VR sales/SalesCockpitBody.tsx:256-292,413-416,452-489 | ⬜ |
| R-13 | Ventas | – | 탭 `거래목록` `차원분석` `판매원별` `개요`. `전기 비교` 스위치. 거래 행 더블클릭 | SalesCockpitDetail 표시. 더블클릭하면 SaleDetailPanel(`Fecha` `Cliente` `Vendedor` `Total`, 품목 `Producto` `Cant.` `Precio`). 판매원을 선택하면 `판매원 필터:` 칩이 생기고 `해제`로 해제 | – | SalesCockpitBody.tsx:437-447,508-523,536-547,571; SalesCockpitDetail.tsx:295-313,675; SaleDetailPanel.tsx:74-89 | ⬜ |
| R-14 | Items (Venta) | 사이드바 | 기간 + `Buscar...` + `CodigoMadre View` | KPI `Ventas` `Unidades` `Monto Total` `Productos`. 다지점이면 지점 표(`Sucursal` `Ventas` `Unidades` `Monto` `Productos`) 행 클릭으로 필터 | reporte-items | registry.ts:171; VR items/ItemsCockpitBody.tsx:134-167,297-321 | ⬜ |
| R-15 | Items | – | 탭 `Lista de ventas` → 행 클릭 → 날짜 클릭 | Panel A 목록 → Panel B 날짜별 → Panel C 색상×사이즈 매트릭스 순으로 드릴다운 | – | ItemsCockpitBody.tsx:386-388,396-430 | ⬜ |
| R-16 | Vendedor | 사이드바 | filterSchema가 없어 기본 필드 사용: 지점 + `Buscar...` + 기간 | KPI `Total Ventas` `Transacciones` `Ticket Promedio` `Descuento Prom.`와 `Top Vendedor`. 데이터가 없으면 `Sin datos para el periodo seleccionado.` | reporte-vendedor | registry.ts:177-188; ReportsFilterFields.tsx:214-242; VR vendedor/VendedorCockpitBody.tsx:122-167 | ⬜ |
| R-17 | Vendedor | – | 판매원 행 클릭(다시 클릭하면 해제) | 상세 패널 탭 `Tendencia` `Mix de productos`(`Producto`/`Categoría`/`Color`/`Talle`/`Temporada`) `Ventas`(`Fecha` `Cliente` `Subtotal` `Desc.` `Total` `Estado`) | – | VendedorCockpitBody.tsx:161,175; VendedorCockpitDetail.tsx:225-230,354-374 | ⬜ |
| R-18 | Clientes | 사이드바(Ventas와 Clientes & Control 양쪽) | `Crédito solo` OFF(기본) + 기간 + `Buscar...` | KPI `Clientes que compraron` `Compras` `Monto del período` `Ticket promedio`. 안내 `Solo ventas con cliente asignado — no es el total de la tienda.` 표 컬럼 `Cliente` `Documento` `Compras` `Monto`… Excel 활성 | reporte-clientes-credito | ReportsFilterFields.tsx:144-158; VR clientes-credito/ClientesCreditoCockpitBody.tsx:172-173; ClientesHistorialBody.tsx:78-103; clientes-credito/components/DataConfig.tsx:52; RC:607-615 | ⬜ |
| R-19 | Clientes | – | `Crédito solo` ON | KPI `Total Saldo` `Clientes` `Promedio Saldo` `Mayor Deuda`. 탭 `Resumen`/`Lista Completa`(`Cliente` `Documento` `Teléfono` `Saldo` `Límite`). Excel 비활성 | – | ClientesCreditoCockpitBody.tsx:114-118,193,258-307 | ⬜ |
| R-20 | Breve Venta | 사이드바 | 지점 + 기간 | KPI `Total Ventas` `Monto Total` `Ticket Promedio` `Promedio Diario` `Mejor Día` `A Crédito (no cobrado aún)` `Por Cobrar (toda la tienda, hoy)`. 탭 `Tendencia`/`Por Día`(`Fecha` `Cantidad Ventas` `Total Monto`) | reporte-breve-venta | registry.ts:217; VR breve-venta/BreveVentaCockpitBody.tsx:138-140,259-347 | ⬜ |
| R-21 | Enviado | 사이드바 | 지점 + 기간. 탭 `Sin confirmar` `Por transporte` `Sin tracking` `Cancelados post envío` `Reclamos` | KPI `Sin confirmar` `Confirmación de entrega` `Entregas confirmadas a tiempo` `Reclamos abiertos` `Demora de entrega`. 탭마다 표가 다름(`Transporte` `Enviados` `Confirmados` … / `Pedido` `Cliente` `Reclamo` `Motivo` `Días` `Monto`) | reporte-enviado | VR enviado/EnviadoCockpitBody.tsx:108-116,125-127,187-226,330-357; RC:1321-1393 | ⬜ |
| R-22 | Enviado | 탭 `Sin confirmar` | 행 선택 + `¿Cuándo llegó?` + `Confirmar entrega` | 버튼이 `Confirmando…`로 바뀐 뒤 토스트 `N entregas confirmadas`(일부 실패 시 `… con error`, 이미 확인된 건은 `ya estaban confirmados`). 실패하면 `No se pudo confirmar` | API: admin/gerente/superadmin/envioManager | EnviadoCockpitBody.tsx:147-170,313-321; RC:1429-1436 | ⬜ |
| R-23 | Alertas | 사이드바 | 지점 + `Buscar...` (**기간 없음**, 스냅샷) | KPI `Total Alertas` `Sin Stock (SKU×suc.)` `Stock Bajo` `Stock Negativo` `Productos`. 탭 `Alertas`/`Lista Completa`(`SKU` `Producto` `Sucursal` `Stock` `Estado`) | reporte-alertas | registry.ts:262-269; VR alertas/AlertasCockpitBody.tsx:134-138,277-337 | ⬜ |
| R-24 | Facturación | 사이드바 | 지점 + 기간 | KPI `Total Facturado` `Facturas` `Promedio Factura` `Pendientes Pago`. 탭 `Resumen`/`Facturas`(`#` `Fecha` `Cliente` `Vendedor` `Total` `Método Pago`) | reporte-facturacion | VR facturacion/FacturacionCockpitBody.tsx:201-206,278,335-390 | ⬜ |
| R-25 | Gastos | 사이드바 | 지점 + 기간 | KPI `Total Gastos` `Cantidad` `Promedio Gasto` `Categorías`. 탭 `Resumen`/`Lista de gastos`(`Fecha` `Descripción` `Categoría` `Subcategoría` `Monto` `Usuario`) | reporte-gastos | VR gastos/GastoCockpitBody.tsx:202-207,279,333-393 | ⬜ |
| R-26 | Cheque Estado | 사이드바 | 지점 + 기간 | KPI `Total Cheques` `Monto Total` `Pendientes` `Rebotados`. 상태 막대 `Procesados`/`Pendientes`/`Rebotados`. 탭 `Resumen`/`Cheques`(`#Venta` `Fecha` `Cliente` `Monto` `Estado`) | reporte-cheque-estado | VR cheque-estado/ChequeEstadoCockpitBody.tsx:160-162,229-233,308,362-411 | ⬜ |
| R-27 | Ingreso (Depósito) | 사이드바 | 기간 + `Buscar...` + `CodigoMadre View` | KPI `Ingresos` `Ingreso Bruto` `Correcciones` `Ingreso Neto` `Sucursales` `Productos`. 지점 표 행 클릭으로 필터. 탭 `Lista de ingresos`(A→B→C 드릴다운)/`Resumen` | reporte-ingreso | registry.ts:333; VR ingreso/IngresoCockpitBody.tsx:133-166,266,313-352,420-438 | ⬜ |
| R-28 | Stocks | 기본 보고서 | `Proveedor` `Tipo` `Temporada`(`Todas`) `CodigoMadre View` `Buscar...` (**기간 없음**) | Panel A 지점 표(`Sucursal` `SKUs` `Venta hoy` `Qty` `Sin Stock` `Bajo` `Dead`) 행 클릭 → Panel B 품목 → Panel C 색상 매트릭스 | reporte-stocks | registry.ts:351-352; ReportsFilterFields.tsx:83-117; VR stocks/panels/PanelA_BranchSummary.tsx:121-127 | ⬜ |
| R-29 | Stocks | Topbar | `Exportar PDF` / `Exportar Excel` | `stocks-items-<오늘>.pdf` / `stocks-reportados-<오늘>.xlsx` 다운로드(선택한 지점 반영) | – | StocksCockpitBody.tsx:67-102; RC:225,2007 | ⬜ |
| R-30 | Stocks | Panel C | `Editar Stock` 체크 → 셀 수정 → `Confirmar` (변경이 많거나 크면 `Confirmar ajustes de stock` 다이얼로그에서 `Cancelar`/`Confirmar`) | 성공 토스트. 동시 변경 시 `El stock cambió mientras editabas. Revisá las celdas marcadas.`. 지점이 선택되지 않으면 체크 비활성(`Para editar seleccioná una sucursal…`). 편집 중 Panel D는 `Modo edición — usá Confirmar…` | API: admin/gerente/superadmin (프론트에는 역할 게이트 없음) | VR stocks/panels/PanelC_ColorMatrix.tsx:330-369,484-503,825-867; StocksCockpitBody.tsx:205-209; RC:1246-1248 | ⬜ |
| R-31 | Stocks | Panel D | `Real` 입력 → `Guardar` | 차이가 0이면 비활성. 저장 중에는 `Guardando...`. 지점 전환 시 편집 중이면 확인창 `Hay cambios sin guardar en la matriz. ¿Descartarlos?` | API: admin/gerente/superadmin | VR stocks/panels/PanelD_StockAdjust.tsx:53,131-210; StocksCockpitBody.tsx:107,115; RC:1192-1194 | ⬜ |
| R-32 | Stocks | Panel B/C 아이콘 | 이력 아이콘 클릭(같은 대상을 다시 누르면 닫힘) | 우측 380px 드로어. 유형 `Recibido` `Enviado` `Ingreso` `Fallado` `Correccion` `Venta` `Reserva` `Otro`. 없으면 `Sin movimientos en este periodo` | – | StocksCockpitBody.tsx:126-140,226; VR stocks/StocksHistorialDrawer.tsx:47-96,211,271,301 | ⬜ |
| R-33 | Stock Vistas | 사이드바 | 지점 + `Buscar...` (**기간 없음**). 탭 `Por sucursal · Variante` `Consolidado · Variante` `Por sucursal · Cód. madre` `Consolidado · Cód. madre` | KPI `Disponible` `Reservado` `Sin movimiento` `Agotado`. 창고 지점은 `DEPÓSITO` 칩으로 표시 | reporte-stock-vistas | registry.ts:368-369; StockVistasCockpitBody.tsx:28-31,174,428-431,441-456; RC:1907-1908 | ⬜ |
| R-34 | Stock Vistas | Topbar | `Exportar Excel` / `Exportar PDF` | 현재 탭 기준 xlsx/pdf 다운로드 | – | VR stock-vistas/hooks/useStockVistasReport.tsx:104,116; RC:1925,1952 | ⬜ |
| R-35 | Corregido | 사이드바 | 지점 + 기간 | KPI `Correcciones` `Monto Afectado` `Usuarios` `Días en período`. 탭 `Resumen`/`Lista`(`#Venta` `Fecha` `Cliente` `Usuario` `Monto` `#Original`) | reporte-corregido | VR corregido/CorregidoCockpitBody.tsx:174-179,251,305-358 | ⬜ |
| R-36 | Movidos | 사이드바 | 지점 + 기간 | KPI `Total Movimientos` `Ingresos (uds)` `Egresos (uds)` `Sucursales`. 탭 `Resumen`/`Lista`(`Fecha` `SKU` `Producto` `Sucursal` `Cantidad` `Tipo`) | reporte-movidos | VR movidos/MovidosCockpitBody.tsx:199-204,283,337-388 | ⬜ |
| R-37 | Fallados | 사이드바 | 지점 + 기간 | KPI `Anulaciones` `Pérdida` `Tasa Anulación` `Días en período`. 탭 `Resumen`/`Anulaciones`(`#Venta` `Fecha` `Cliente` `Vendedor` `Monto`) | reporte-fallados | VR fallados/FalladosCockpitBody.tsx:174-178,249,303-356 | ⬜ |
| R-38 | Rotación Temporada (season-turnover) | 사이드바 | 기본 필드: 지점 + `Buscar...` + 기간 | 표 `Temporada` `Vendido (uds)` `Vendido (Gs)` `Stock actual` `Turnover` `Días restantes` `Clasificación`(`Rápido`/`Medio`/`Lento`/`Muerto`). 기간 변경 시 자동 조회 | reporte-temporada | registry.ts:419-438; VR season-turnover/SeasonTurnoverBody.tsx:37-42,51-60,88-94; RC:826-827 | ❌ 실측: 화면 문구가 한국어 (`회전율` `기간 내 판매량` `현재 재고` `소진 예상일`) — 코드 판독에서 누락됐던 것 |
| R-39 | /reportes | URL 직접 입력 | – | `/reportes-v2`로 replace 리다이렉트 | allowedApps reportes | VA pages/reportes/index.tsx:13-15 | ⬜ |
| R-40 | /reportes/stocks | URL 직접 입력 | – | `/reportes-v2/stocks`로 리다이렉트 | – | VA pages/reportes/stocks/index.tsx:22-23 | ⬜ |
| R-41 | /reportes/{ventas,items,vendedor,clientes-credito,breve-venta,reservado,alertas,facturacion,gastos,cheque-estado,ingreso,movidos,corregido,fallados} | URL 직접 입력만 가능 (메뉴 링크 없음) | – | 리다이렉트하지 **않고** 레거시 화면을 그대로 렌더함(**고아 페이지**) | allowedApps reportes (+ 일부는 allowedModules) | VA pages/reportes/alertas/index.tsx:4-9; VA pages/reportes/ventas/index.tsx; 레거시 링크는 사용하지 않는 VR hub/ReportesHub.tsx:8-30에만 있음 | ⬜ |
| R-42 | /reportes/dashboards | URL 직접 입력 | – | 텍스트 `Dashboards de Reportes`만 표시(placeholder) | – | VA pages/reportes/dashboards/index.tsx:3-9 | ⬜ |
| R-43 | /reportes/asistencia | URL (코드상 메뉴 링크 미확인. DB 모듈일 가능성 있음) | 탭 `Horas`/`Adelantos`/`Revendedores`. `Período`(`Mes`/`Rango`), `Mes` 또는 `Desde`/`Hasta`, `Sucursal`(`Todas`) | 제목 `Asistencia`. 표 `Vendedor` `Total` (`Adelanto`는 Mes 모드에서만) `Sesiones` `Sin cerrar`(`OK` 칩) | API: admin/superadmin/gerente | VR asistencia/AsistenciaReport.tsx:61,89-158,192-221; API app/attendance/attendance.controller.ts:85-86 | ⬜ |
| R-44 | /reportes/asistencia | Horas 행 클릭 | 세션의 `Entrada`/`Salida`/`Nota` 수정 → `Guardar`, `Cerrar` | 토스트 `Sesión actualizada` 또는 `No se pudo guardar la corrección`. 상태 칩 `Sin cerrar`/`Cerrada` | admin/superadmin/gerente | AsistenciaReport.tsx:205,234; AttendanceEditModal.tsx:111-121,155-219; attendance.controller.ts:137-138 | ⬜ |
| R-45 | /reportes/asistencia | 탭 Adelantos | `Estado`(`Pendientes`/`Aprobados`/`Rechazados`/`Todos`). `Aprobar` → `Mes de descuento` → `Confirmar`. `Rechazar` | 토스트 `Adelanto aprobado` / `Adelanto rechazado` (실패 시 `No se pudo …`) | admin/superadmin/gerente | AdelantosPanel.tsx:80-116,166-179,192-211; API app/adelanto/adelanto.controller.ts:54-71 | ⬜ |
| R-46 | /reportes/asistencia | 탭 Revendedores | `Revocar` → 다이얼로그 `Revocar autorización` → `Revocar`/`Cancelar` | 토스트 `Autorización revocada` 또는 `No se pudo revocar la autorización` | admin/superadmin/gerente | ResellerAuthPanel.tsx:50-55,92-133; attendance.controller.ts:152-153 | ⬜ |
| H-01 | /fichaje-qr | 앱 내 단축키 **Ctrl+V** (팝업 460×640) | – | BlankLayout에 매장명, QR(300px), `Fichaje · <날짜>`, `Escaneá este código con la app para registrar entrada / salida.` 표시 | 로그인 필요(authGuard) | VA layouts/UserLayout.tsx:69-73; VA pages/fichaje-qr/index.tsx:63-100,103-104 | ❌ 실측: SKU 입력란에서 Ctrl+V → preventDefault + `/fichaje-qr?branchId=6` 팝업. 대조군(Ctrl 없는 v)은 통과. Windows 에서 입력란 붙여넣기 불가 (UserLayout.tsx:69-74, 2026-07-11 도입) |
| H-02 | /fichaje-qr | – | 대기 | refreshAt 시각에 QR이 자동 갱신됨. 오류 시 `No se pudo cargar el QR. Reintentá o revisá la conexión.` | branchId는 쿼리 → 사용자 지점 순으로 사용 | fichaje-qr/index.tsx:24-48,70-73; API attendance.controller.ts:51-52 | ⬜ |
| H-03 | /herramientas/print-agent | 메뉴 Herramientas `nav_downloads` | 프로그램별 `Descargar` | 제목 `Descargas`. Tienda Admin(APK), Print Agent/Zebra Agent(Win/macOS arm64/x64), Edge Sync Agent(zip + `Instrucciones` README), Despacho, Ventas 앱의 GitHub 릴리스 파일 다운로드. 태그는 빌드 시 최신 릴리스 기준(revalidate 300) | 역할 제한 없음 | VA navigation/menuRegistry.ts:341; VA pages/herramientas/print-agent/index.tsx:53-230,262,279-343,372-416 | ⬜ |
| H-04 | /herramientas/print-agent | – | iOS (iPhone) 버튼 | `Próximamente`로 표시되고 비활성 | – | print-agent/index.tsx:10,230,313-315,343 | ⬜ |
| H-05 | /manuales | 메뉴 `nav_ai_support` 또는 셋업 가이드 `Cómo se usa` | 언어 `Todos`/언어별 버튼. `Buscar por título...` | manifest.json에 있는 매뉴얼 목록이 필터링되고 `n / 전체` 카운트가 표시됨 | – | VA views/manuales/ManualesView.tsx:61,140-155,179-231; VA navigation/vertical/index.ts:243 | ⬜ |
| H-06 | /manuales | 카드 | 카드 클릭 / 다운로드 아이콘(`Descargar PDF`) | 미리보기 다이얼로그(iframe). 헤더에 `Descargar`, `Abrir en pestaña nueva`, `Cerrar` | – | ManualesView.tsx:258-331,461-505 | ⬜ |
| H-07 | /manuales | 우측 채팅 패널 | `Escribe tu pregunta...` + 전송 | `/chat/history` 로드 후 `/chat/message` 응답이 표시됨. 비어 있으면 `¿En qué puedo ayudarte?`. 실패 시 `Error al conectar con el asistente. Inténtalo de nuevo.` | @Auth() | ManualesView.tsx:84-112,381-454; API app/chat/chat.controller.ts:21-37 | ⬜ |
| H-08 | 전역 (UserLayout) | 우하단 플로팅 ✨ (`Asistente IA`) | 클릭 | 창 `Asistente ACE` 열림/닫힘. 초기 문구 `¡Hola! Soy tu asistente ACE.` / `¿En qué puedo ayudarte?`. /manuales에서는 아이콘 숨김. `openChat` 이벤트나 `#open-ai-chat` navAction으로도 열림 | 로그인 사용자 | VA components/chat/ChatBubble.tsx:28,35-50,66-83; VA components/chat/ChatWindow.tsx:28-33,136,158-163 | ⬜ |
| H-09 | AI 채팅 창 | – | `Escribe tu pregunta...` Enter(Shift+Enter는 줄바꿈) | 사용자 말풍선 → 로딩 → 응답(없으면 `Sin respuesta`). 오류 시 오류 문구 | @Auth() | ChatWindow.tsx:80-102,213-224 | ⬜ |
| H-10 | 전역 | 사이드바 Herramientas `Chat de equipo` (`#open-team-chat`) | 클릭 | TeamChatPanel(`Equipo`) 열림. 안 읽은 메시지가 있거나 패널이 열려 있을 때만 FAB 표시(`Chat de equipo`, 빨간 뱃지 최대 99) | ACL 없음 | VA navigation/menuRegistry.ts:360; VA components/team-chat/TeamChatBubble.tsx:25-74 | ⬜ |
| H-11 | 팀 채팅 | 목록 | `Grupo General` (`Todos los miembros`) 또는 사용자 선택 → `Escribe un mensaje...` Enter | 메시지 전송·조회, 읽음 처리(`/team-chat/read`) | 그룹 전송은 admin/superadmin/gerente만. 그 외 역할에는 `Solo gerentes y administradores pueden enviar mensajes al grupo general` 표시 | VA components/team-chat/TeamChatPanel.tsx:79-124,188-206,261-285; API app/team-chat/team-chat.controller.ts:20-76 | ⬜ |
| H-12 | /soporte | 사이드바 `Soporte en vivo` | `Actualizar` / `Abrir visor` / UUID 복사 / `Ver en vivo` | 제목 `Soporte Remoto`. 활성 세션 표(`Código (UUID)` `Estado` `Creada` `Expira` `Acción`). 권한이 없으면 `No tenés permiso para ver el soporte remoto (support.view).` | 플래그 NEXT_PUBLIC_ENABLE_REMOTE_SUPPORT=true 이고 supportRoles. 아니면 `/`로 리다이렉트 | VA pages/soporte/index.tsx:45,71-85,112-162,176-187; VA configs/featureFlags.ts:6-7; VA navigation/vertical/index.ts:84-96 | ⬜ |
| H-13 | /soporte/visor | `Ver en vivo` 또는 직접 입력 | `Código de sesión (UUID)` → `Conectar` / `Finalizar` | 상태 칩 `Conectando…` → `Conectado (en vivo)` / `Sesión finalizada` / `Error` / `Sin conexión`. 읽기 전용 | 같은 플래그 | VA pages/soporte/visor.tsx:222-292,363-368 | ⬜ |
| H-14 | /entrega/[token] | 고객에게 보낸 공개 링크(로그인 불필요) | 페이지 로드 | `Confirmación de entrega`. 발송일·`Transporte`·`Seguimiento` 표시. 이미 처리된 건은 `Ya figura como entregado…` / `Ya registramos tu reclamo…`. 링크가 잘못되면 `Enlace no válido o vencido` | @Public, Throttle | VA pages/entrega/[token].tsx:38-41,70-73,120-164,244-248; API app/online-orders/public-delivery.controller.ts:28-47 | ⬜ |
| H-15 | /entrega/[token] | – | `Sí, lo recibí` | `¡Gracias!` / `Registramos la entrega. Ya podés cerrar esta página.` | – | [token].tsx:86,175-178,223-225 | ⬜ |
| H-16 | /entrega/[token] | – | `No lo recibí` → `¿Qué pasó? (opcional)` → `Enviar reclamo` | `Recibimos tu reclamo` / `La tienda se va a contactar con vos.` → Enviado의 `Reclamos` 탭에 반영 | – | [token].tsx:98,188-213,233-235 | ⬜ |
| L-01 | /login | 직접 입력 | `Correo electrónico o Usuario` + `Contraseña` → `Iniciar Sesión` | 유효하지 않으면 버튼 비활성. 성공 시 등록 모달 또는 리다이렉트 | guestGuard | VA views/login/LoginView.tsx:131-160,569-651; VA pages/login/index.tsx:19 | ⬜ |
| L-02 | /login | – | 틀린 자격증명 | 빨간 Alert에 서버 메시지 + `Por favor, verifica e intenta nuevamente.` | – | LoginView.tsx:155-157,302-316 | ⬜ |
| L-03 | /login | – | 비활성 계정 | 다이얼로그 `Error de acceso`. `Cerrar` / `Contactar a soporte`(wa.me 새 창) | 메시지가 'Usuario inactivo o suspendido'일 때 | LoginView.tsx:152-154,320-341 | ⬜ |
| L-04 | /login | – | 승인 대기 중인 신청자 로그인 | 닫기 버튼 없는 Alert 카드(ONBOARDING_NOTICES code 기반) | 서버 응답 code | LoginView.tsx:143-149,284-300; VA views/login/onboardingNotices.ts | ⬜ |
| L-05 | /login?reason=session_expired | 다른 기기 로그인으로 401 SESSION_EXPIRED 수신 시 자동 이동 | – | 경고 `Su sesión fue cerrada porque se inició sesión desde otro dispositivo.` (닫기 가능) | – | VA services/api.service.ts:237-240; LoginView.tsx:79-83,273-277 | ⬜ |
| L-06 | /login | 로그인 응답 requireBranchRegistration | 모달 `Nueva sucursal detectada`: `Conectar a una sucursal existente`/`Crear una nueva sucursal`, `Sucursal`, `Nombre de la sucursal`, `Nombre del terminal` → `Conectar`/`Crear sucursal`, `Cancelar`(로그아웃) | 성공하면 세션 저장 후 리다이렉트. 실패 시 `Error al registrar la sucursal`. 관리자가 아니면 `Solo los administradores pueden crear nuevas sucursales…`. ESC로 닫히지 않음 | 생성은 admin만 | LoginView.tsx:90-109,162-192,344-424; API app/session/*.controller.ts:44,60 | ⬜ |
| L-07 | /login | requireTerminalRegistration | 모달 `Nuevo dispositivo detectado`: `Mover desde un terminal existente` → `Mover a este terminal` / `Agregar un nuevo terminal` → `Nombre del terminal` + `Caja asignada` → `Agregar terminal` | 기존 터미널이 있으면 기본값은 '이동'. 실패 시 `Error al mover el terminal` / `Error al registrar el terminal` | – | LoginView.tsx:110-116,223-265,427-520; session controller:98,120 | ⬜ |
| L-08 | /login | 세션 완료 | – | returnUrl이 있으면 그곳으로. 없으면 superadmin/gerente → `/dashboards/admin`, admin/vendedor → `/nueva-venta` | – | LoginView.tsx:195-220 | ⬜ |
| L-09 | /login | – | `Recordar cuenta` 체크 | **아무 효과 없음** (비제어 Checkbox) | – | LoginView.tsx:618-622 | ⬜ |
| L-10 | /olvidaste-contrasena | 로그인의 `¿Olvidaste tu contraseña?` | 이메일 입력 → `Enviar código de recuperación` / `Regresar al inicio de sesión` | **console.log만 실행, 전송 없음** | guestGuard | LoginView.tsx:580-581; VA views/forward-password/ForwardPasswordView.tsx:34-37,60-65 | ⬜ |
| L-11 | /verifica-correo | URL 직접 입력(진입 링크 없음) | `Ingresa código de recuperación` / `Reenviar` | 버튼에 핸들러 없음. `Reenviar`는 없는 경로 `/pages/auth/register-v1`로 이동 | guestGuard | VA views/forward-password/VerifyEmailView.tsx:17-24 | ⬜ |
| L-12 | /register | 로그인의 `Crea una tienda` | `Nombre de la tienda` `Apodo de la tienda` `CUIT de la empresa` `Direccion de la tienda` `Nombre` `Apellido` `Usuario` `Telefono / WhatsApp` `Correo electronico` `Contraseña` `Repetir contraseña`, 주소 방문 동의, 약관 체크 → `Continuar →` | yup 검증 메시지(`No puede estar vacío.` 등). 성공하면 OTP 단계로. 오류 시 토스트 `Ups, ocurrió un error` | guestGuard | LoginView.tsx:656-657; VA views/register/components/RegisterForm.tsx:41-51,238-257,320-535 | ⬜ |
| L-13 | /register(?ref=) | – | `¿Quién te recomendó? (opcional)` blur | 추천인 apodo를 조회하고, 유효하면 `bonificación del 50% de un mes` Alert 표시 | – | RegisterForm.tsx:179,204-217,453-483 | ⬜ |
| L-14 | /register | OTP 단계 `Confirmá tu contacto` | 이메일·WhatsApp 각각 6자리 입력 → `Verificar` / `Reenviar código`(쿨다운 `Reenviar (Ns)`) | `Correo verificado`/`WhatsApp verificado`, `Verificado` 표시. 오류 시 `Código incorrecto` / `Ingresá los 6 dígitos.` | – | RegisterForm.tsx:271-303,609-698 | ⬜ |
| L-15 | /register | 두 채널 모두 인증 완료 | – | `¡Registro enviado!` 화면(`Volver al inicio`)과 SuccessModal(`Inicia Sesion`)이 동시에 트리거됨 | – | RegisterForm.tsx:122,162-167,558-600; VA views/register/RegisterView.tsx:57-60,106-116 | ⬜ |

### 4. 보고서 · 도구 · 로그인 — 코드 판독에서 나온 이상 (미실측)

**이상 항목 (Anomalies)**
1. **Excel/PDF 내보내기 대부분이 동작하지 않음.** Cockpit 교체 이후 15개 보고서가 `refresh`만 등록해 Topbar의 `Exportar Excel`/`Exportar PDF`가 항상 비활성이다. `downloadExcel`은 사용하지 않는 레거시 `*ReportBody.tsx`에만 남아 있다(RC에는 `*-report-export` 엔드포인트가 존재). Vendedor, Enviado, Rotación Temporada는 `Ejecutar`까지 비활성이다.
2. **Rotación Temporada에 동작하지 않는 컨트롤이 있음.** filterSchema가 없어 기본 필드로 지점과 `Buscar...`가 렌더되지만, Body는 storeId와 날짜만 보낸다(SeasonTurnoverBody.tsx:57-61). Vendedor의 지점·검색이 백엔드에서 쓰이는지는 미확인.
3. **Ventas 화면에 한국어 UI가 그대로 노출됨**: `총 매출`, `거래목록`, `차원분석`, `판매원별`, `개요`, `해제`, `판매원 필터:`, `매출 추이`, `전기 비교`, `TOP 카테고리` (SalesCockpitBody.tsx:413-523).
4. **/olvidaste-contrasena는 기능이 없음**(submit이 console.log만 실행). **/verifica-correo** 버튼에는 핸들러가 없고, `Reenviar`는 존재하지 않는 `/pages/auth/register-v1`로 링크된다.
5. **로그인 화면의 죽은 요소 두 가지.** `Recordar cuenta`는 어디에도 연결되지 않았다. `Contactar a soporte`의 WhatsApp 번호는 placeholder `5491123456789`이다(LoginView.tsx:333).
6. **/register의 `Términos y condiciones` 링크가 동작하지 않음**(`href="/"` + preventDefault, RegisterForm.tsx:524). 완료 시 listo 화면과 SuccessModal이 중복으로 뜬다.
7. **레거시 /reportes/\* 14개 페이지가 고아 상태.** 리다이렉트 없이 레거시 뷰를 그대로 렌더하며, 이 페이지들을 가리키는 `ReportesHub`는 어디서도 import되지 않는다. `/reportes/dashboards`는 placeholder다. registry의 `legacyHref` 중 `/reportes/enviado`, `/reportes/stock-vistas`, `/reportes/season-turnover`는 존재하지 않는 경로다(bodyComponent가 있어 실제로 노출되지는 않음).
8. **/reportes/asistencia로 가는 메뉴 링크를 코드에서 찾지 못함**(DB 모듈 여부는 미확인).
9. **Ctrl+V 단축키 충돌.** `useHotkeys('ctrl+v', …, { enableOnFormTags: true })`가 preventDefault하므로 Windows에서 모든 입력란의 붙여넣기가 막힐 가능성이 높다(UserLayout.tsx:69-73, 실측 필요).
10. **역할 제한이 프론트에만 있는 경우**:
    - `Grupo General` 전송 제한은 프론트에만 있고, API `team-chat/send`는 `@Auth()`만 확인한다.
    - `chat/knowledge`, `sync-drive`, `sync-manuales`는 모든 로그인 사용자에게 열려 있다.
    - 반대로 `Editar Stock`/`Guardar`는 프론트에서 역할 게이트가 없다. vendedor도 보이지만 API에서 403이 난다.
11. **/manuales 미리보기 문제.** manifest 파일이 모두 .docx인데 iframe에 "PDF 뷰어"로 띄우므로, 인라인 미리보기가 되지 않고 다운로드될 가능성이 크다. iOS 다운로드는 `IOS_TESTFLIGHT_URL=''`이라 항상 `Próximamente`다.
12. **플래그로 막혀 있는데 설정 UI가 없음.** `/soporte`는 빌드 env `NEXT_PUBLIC_ENABLE_REMOTE_SUPPORT`로만 켤 수 있다.
13. **팀 채팅 안 읽음 수가 자동 갱신되지 않음.** 마운트할 때와 open이 바뀔 때만 조회하고 폴링하지 않는다(TeamChatBubble.tsx:25-30). 안 읽은 메시지가 새로 와도 FAB가 나타나지 않을 수 있다.
14. `ReportsFilterFields`의 `category`/`paymentMethod` 필드는 TODO("Wave 2 이후 구현 예정", :359)로 남아 있어 null을 렌더한다.

---

## 실측 기록 (2026-09-22, 운영 app.coolsistema.com · 매장 6 coolsistema · admin 계정)

- **방법**: cmux browser `surface:4`. 조작 없이 이동·DOM 판독만. 판매·카하·삭제 조작은 하지 않았다.
- **탐침 대조군** — 두 번 틀렸다가 대조군으로 잡았다:
  1. 내보내기 버튼을 `button[aria-label]` 로 찾았더니 18개 전부 "없음". Stocks(코드상 on)도 없음 → 탐침 오류.
     MUI Tooltip 은 `aria-label` 을 버튼이 아니라 감싼 `<span>` 에 단다. 고친 뒤 Stocks 가 on 으로 잡혔다.
  2. `cmux browser press "Control+v"` 는 조합키가 아니라 **글자 하나로** 들어간다(`key:"Control+v"`).
     조합키는 `KeyboardEvent` 를 직접 dispatch 해서 쟀다(Ctrl 없는 v 를 대조로).
- **화면 열림 · 오류 0 · 한국어 0**: `/dashboards/admin` `/sucursales` `/usuarios` `/admin/auditoria`
  `/mi-suscripcion` `/tesoreria` `/caja` `/control-de-caja` `/cheques` `/caja-fuerte` `/gastos` · 허브 탭 14개.
  (`/mi-suscripcion` 본문 120자, `/cheques` 299자 — 데이터가 적은 것인지 확인 필요)
- **중단**: 12번째 화면부터 `/login?returnUrl=` 로 튕겼다. 원인은 앱 결함이 아니라 **같은 계정의 Chrome 로그인
  (12:39 UTC, `active_sessions.id=574`)이 cmux 세션을 밀어낸 것**(중복 로그인 차단). 앞 11개 화면은
  SessionGuard 가 없는 API 만 불러 통과했다. 남은 실측은 **재로그인 후** 또는 **별도 판매원 계정**으로.
- **재로그인 후 이어서 (사용자 로그인)**: `/guia-configuracion` `/perfil` `/carpetas-compartidas` `/nueva-venta`
  `/ventas-online` `/ventas` `/facturacion` `/cuentas-corrientes` `/cliente-vista` `/clientes-globales` `…/campanas`
  `/dashboards/ventas` `/productos` `/precios` `/dashboards/producto` `/materia-prima/*`(5) `/talleres`
  `/herramientas/print-agent` `/manuales` `/reportes/asistencia` — 24개 전부 열림 · 오류 0.
  한국어 검출은 전부 데이터(상품·고객 이름)이거나 KO 매뉴얼 목록. 예외 하나: `/dashboards/ventas`
  「Últimas ventas」 시각이 `오전 9:41` — `toLocaleTimeString()` 인자 없음(LastSalesCard.tsx:83)이라
  **브라우저 언어·시간대**를 따른다. 고객 브라우저에선 es-AR 로 나오지만 매장 시간대가 아니라 기기 시간대다.
- **F1(권한이 메뉴에만) 은 admin 계정으로는 잴 수 없다** — admin 은 PRIVILEGED 라 `WithAccess` 를 전부 통과한다.
  판매원(vendedor) 전용 시험 계정이 필요하다.
