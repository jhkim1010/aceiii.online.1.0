# VentaGO 매뉴얼 제작 계획 (Manuales Plan)

작성: 2026-07-07 · Trello "Manuales" 리스트 4개 카드 기준

## 배포 인프라 (이미 존재 — 재사용)

- 앱 메뉴 `/manuales` (ManualesView) 가 `public/manuales/manifest.json` 을 읽어 목록 표시. 언어별(es/ko) 라벨·audience·아이콘 지원.
- **파일 추가 = `ventago-app/public/manuales/` 에 docx 업로드 + manifest.json 항목 추가** (재배포 필요).
- 현 manifest 에 vendedor/admin ES·KO PDF 4건이 등록돼 있으나 실제 파일은 `Manual_Talleres_VentaGO_ES.pdf` 만 존재 → 나머지는 404. 이번 작업에서 실파일로 채움.
- 사용자 선호는 MinIO 링크 방식 — Fase 4 에서 manifest 의 fileName 을 절대 URL 허용하도록 소폭 개선하면 재배포 없이 교체 가능 (선택).

## 파일 명명 규칙

`Manual_<Area>_VentaGO_<ES|KO>.docx` — 예: `Manual_Ventas_VentaGO_ES.docx`, `Manual_Ventas_VentaGO_KO.docx`
캡처는 두 언어 공용(스페인어 UI 화면), 설명 텍스트만 언어별.

## 매뉴얼별 주제 (Trello 체크리스트와 동일)

### 1. Manual de Ventas (audience: vendedor)
1. Iniciar sesión, registro de terminal e IP de sucursal
2. Pantalla Nueva Venta (POS): buscar artículos y agregar al carrito
3. Vender con código madre: tabla de variantes color × talla
4. Niveles de precio, descuentos y promociones
5. Medios de pago: efectivo, QR MercadoPago, crédito/a favor y pago mixto
6. Suspender y retomar una venta
7. Historial de ventas: anular, devolver y reimprimir ticket
8. Apertura y cierre de caja (control de caja, caja fuerte)
9. Modo restaurante: salón, mesas y comandas
10. Impresión de tickets (comandera térmica)

### 2. Manual de Producto (audience: admin/gerente)
1. Alta de producto simple: datos básicos, precios y SKU (prefijo)
2. Código madre y variantes: colores × tallas
3. Categorías, subcategorías, temporadas, orígenes y proveedores
4. Carga de imágenes del producto
5. Gestión de precios: niveles, aumentos masivos y cambio por código madre
6. Reingreso / reposición de stock con código madre
7. Etiquetas de código de barras (Zebra): 3 formatos e impresión
8. Importación masiva de códigos/productos
9. Publicar artículos en la tienda online (activar/desactivar)
10. Parámetros: prefijo de SKU y configuraciones

### 3. Manual de Admin (audience: admin/dueño)
1. Estructura: tienda → sucursales → cajas → terminales (alta y edición)
2. Usuarios: alta, roles y permisos
3. Seguridad de sesión: dispositivos, IPs registradas y bloqueo de doble login
4. Configuración de la tienda: logo, alias y datos
5. Gastos: categorías y registro
6. Agentes de impresión: alta de comandera/Zebra, API Key y mapeo por terminal
7. Clientes: cuentas corrientes y créditos
8. Dashboards: lectura de indicadores
9. Auditoría de acciones

### 4. Manual de Stock (Reportajes) (audience: admin/gerente)
1. Consulta de stock por sucursal, producto y variante
2. Movimientos entre sucursales (movido): enviar y recibir
3. Ajustes de inventario y política de venta sin stock
4. Reportes de ventas: por período, sucursal, vendedor y producto
5. Reportes de caja y finanzas
6. Stock valorizado
7. Materia prima: inventario de telas (rollo/kg ↔ metros)
8. Talleres / producción: cortes y consumo de materiales
9. Exportar reportes a Excel

### 5. Manual de Materia Prima (audience: admin/depósito) — 신규 카드
1. Alta de materiales: telas madre y variantes (colores)
2. Unidades duales: compra en rollo/kg y consumo en metros
3. Ingreso de compra: proveedor, rollos y costo
4. Inventario: consulta de stock de telas
5. Movimientos: consumo, merma y retazos (ajustes)
6. Proveedores de materia prima
7. Pagos a proveedores: registrar y consultar
8. Códigos de material y etiquetas

### 6. Manual de Talleres (audience: admin/producción) — 신규 카드
1. Concepto general: etapas del flujo de talleres
2. Talleres (vendors): alta y datos
3. Ficha de costos (BOM): materiales y consumo por producto
4. Ticket de corte: crear y seguir un corte
5. Envíos a taller: remitos y seguimiento
6. Recepción de prendas terminadas e ingreso a stock
7. Control de mermas y diferencias
8. Liquidación y pagos a talleres
9. Reportes de producción

참고: Talleres 는 기존 `Manual_Talleres_VentaGO_ES.pdf` 가 이미 존재 — docx 개정판으로 대체 예정.

## 단계 (Fases)

- **Fase 1 (완료)**: 주제 계획 + Trello 4개 nota 에 desc/checklist 기록 (pending-card-updates → 06:50 sync 또는 수동 `node tools/trello-sync.js`)
- **Fase 2**: Chrome 으로 운영 앱(ventago.coolsistema.com) 화면 캡처 — 주제당 1~3장, 로그인 세션 필요. 캡처는 `docs/manual-captures/<area>/` 에 저장
- **Fase 3**: docx 작성 (매뉴얼당 ES+KO 2개, 총 8개) — 캡처 삽입 + 단계별 설명. Ventas → Producto → Stock → Admin 순
- **Fase 4**: 배포 — `public/manuales/` + manifest.json 갱신, 체크리스트 tildar + 카드 hechosPending. (선택) MinIO 절대 URL 지원 개선
