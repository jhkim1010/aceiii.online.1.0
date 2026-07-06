// Manual de Stock (Reportajes) — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/stock/<capture>.png

module.exports = {
  area: 'Stock',
  fileBase: 'Manual_Stock_VentaGO',
  captureDir: 'stock',
  title: { es: 'Manual de Stock y Reportes', ko: '재고·보고서(Stock) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Inventario, movimientos entre sucursales y reportes',
    ko: 'VentaGO — 재고, 지점 간 이동, 보고서 가이드',
  },
  intro: {
    es: 'Este manual cubre la gestión de inventario: consulta de stock por sucursal y variante, movimientos entre sucursales, ajustes, y los reportes de ventas, caja y stock valorizado con exportación a Excel.',
    ko: '이 매뉴얼은 재고 관리를 다룹니다: 지점·변형별 재고 조회, 지점 간 이동(movido), 조정, 그리고 매출·금전함·재고 평가 보고서와 Excel 내보내기입니다.',
  },
  topics: [
    {
      id: 'consulta',
      title: { es: 'Consulta de stock por sucursal y variante', ko: '지점·변형별 재고 조회' },
      capture: 'stock-01-consulta',
      intro: {
        es: 'El stock se lleva por variante (color/talla) y por sucursal. Desde productos o reportes se consulta cuántas unidades hay y dónde.',
        ko: '재고는 변형(색상/사이즈)·지점 단위로 관리됩니다. 상품 또는 보고서 화면에서 수량과 위치를 조회합니다.',
      },
      steps: [
        {
          es: 'Busque el artículo en «Productos» y abra su detalle de stock: verá las unidades por sucursal y por variante.',
          ko: '«Productos»에서 상품을 검색해 재고 상세를 열면 지점·변형별 수량이 표시됩니다.',
        },
        {
          es: 'Use los filtros por categoría o proveedor para revisar el stock de una línea completa.',
          ko: '카테고리/공급자 필터로 상품군 전체 재고를 확인할 수 있습니다.',
        },
      ],
      tips: [
        {
          es: 'Un stock negativo indica ventas registradas sin ingreso previo: corríjalo con un ajuste.',
          ko: '재고가 음수면 입고 없이 판매가 기록된 것입니다. 조정으로 바로잡으세요.',
        },
      ],
    },
    {
      id: 'movido',
      title: { es: 'Movimientos entre sucursales (movido)', ko: '지점 간 이동(movido)' },
      capture: 'stock-02-movido',
      intro: {
        es: 'El «movido» traslada mercadería de una sucursal a otra dejando registro: la sucursal origen envía y la destino recibe.',
        ko: '«movido»는 상품을 지점 간 이동시키며 기록을 남깁니다. 출발 지점이 보내고 도착 지점이 받습니다.',
      },
      steps: [
        {
          es: 'Cree el movimiento eligiendo sucursal origen, destino y los artículos con sus cantidades (por variante).',
          ko: '출발/도착 지점과 상품·수량(변형별)을 선택해 이동을 생성합니다.',
        },
        {
          es: 'Confirme el envío: el stock sale de la sucursal origen.',
          ko: '발송을 확정하면 출발 지점 재고에서 차감됩니다.',
        },
        {
          es: 'En la sucursal destino, confirme la recepción para que el stock ingrese.',
          ko: '도착 지점에서 수령을 확정해야 재고가 입고됩니다.',
        },
      ],
      tips: [
        {
          es: 'El movido tampoco se bloquea por falta de stock: las diferencias reales se corrigen con ajustes.',
          ko: 'movido 역시 재고 부족으로 차단되지 않습니다. 실물 차이는 조정으로 처리하세요.',
        },
      ],
    },
    {
      id: 'ajustes',
      title: { es: 'Ajustes de inventario y venta sin stock', ko: '재고 조정과 무재고 판매 정책' },
      capture: 'stock-03-ajustes',
      intro: {
        es: 'Los ajustes corrigen diferencias entre el sistema y el conteo físico. Además, cada tienda define si permite vender artículos sin stock (activado por defecto).',
        ko: '조정은 시스템 재고와 실사 수량의 차이를 바로잡습니다. 또한 매장별로 무재고 판매 허용 여부를 설정할 수 있습니다(기본 허용).',
      },
      steps: [
        {
          es: 'Haga conteos físicos periódicos por categoría o sector.',
          ko: '카테고리/구역별로 주기적으로 실사하세요.',
        },
        {
          es: 'Registre el ajuste (positivo o negativo) con su motivo para dejar trazabilidad.',
          ko: '사유와 함께 조정(+/−)을 기록해 추적성을 남깁니다.',
        },
        {
          es: 'La política «permitir venta sin stock» se cambia en la configuración de la tienda; desactívela solo si su inventario es muy confiable.',
          ko: '«무재고 판매 허용» 정책은 매장 설정에서 변경합니다. 재고 정확도가 매우 높을 때만 끄세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'reportes-ventas',
      title: { es: 'Reportes de ventas', ko: '매출 보고서' },
      capture: 'stock-04-reportes-ventas',
      intro: {
        es: 'Los reportes de ventas muestran totales por período, sucursal, vendedor, producto y medio de pago.',
        ko: '매출 보고서는 기간·지점·판매원·상품·결제수단별 합계를 보여줍니다.',
      },
      steps: [
        {
          es: 'Entre a «Reportes», elija el reporte de ventas y el rango de fechas.',
          ko: '«Reportes»에서 매출 보고서와 날짜 범위를 선택합니다.',
        },
        {
          es: 'Agrupe por sucursal o vendedor para comparar desempeño.',
          ko: '지점/판매원 기준으로 묶어 성과를 비교하세요.',
        },
        {
          es: 'Use el detalle por producto para decidir reposiciones y promociones.',
          ko: '상품별 상세로 재입고와 프로모션을 결정하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'reportes-caja',
      title: { es: 'Reportes de caja y finanzas', ko: '금전함·재무 보고서' },
      capture: 'stock-05-reportes-caja',
      intro: {
        es: 'Estos reportes cruzan ventas, gastos y movimientos de caja para ver el resultado del día o del mes.',
        ko: '이 보고서는 매출, 지출, 금전함 이동을 종합해 일/월 결과를 보여줍니다.',
      },
      steps: [
        {
          es: 'Revise el arqueo diario: apertura, ventas por medio de pago, gastos y cierre.',
          ko: '일일 정산을 검토하세요: 개시, 결제수단별 매출, 지출, 마감.',
        },
        {
          es: 'Controle las diferencias de cierre por caja y por responsable.',
          ko: '카하·담당자별 마감 차액을 관리하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'valorizado',
      title: { es: 'Stock valorizado', ko: '재고 평가액' },
      capture: 'stock-06-valorizado',
      intro: {
        es: 'El stock valorizado multiplica las unidades por su costo o precio para conocer el capital inmovilizado en mercadería.',
        ko: '재고 평가액은 수량×원가(또는 판매가)로 상품에 묶인 자본을 보여줍니다.',
      },
      steps: [
        {
          es: 'Genere el reporte de stock valorizado por sucursal.',
          ko: '지점별 재고 평가 보고서를 생성합니다.',
        },
        {
          es: 'Identifique categorías con exceso de stock para planificar ofertas.',
          ko: '재고 과잉 카테고리를 찾아 할인 계획에 활용하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'materia-prima',
      title: { es: 'Materia prima: telas (rollo/kg ↔ metros)', ko: '원자재: 원단(롤/kg ↔ 미터)' },
      capture: 'stock-07-materia-prima',
      intro: {
        es: 'Para tiendas con producción, el inventario de telas se compra en rollos o kilos pero se consume en metros. VentaGO convierte entre unidades y descuenta mermas.',
        ko: '생산이 있는 매장은 원단을 롤/kg로 구매하고 미터로 소비합니다. VentaGO가 단위를 환산하고 로스(merma)를 차감합니다.',
      },
      steps: [
        {
          es: 'Consulte el inventario de telas en «Materia prima»: saldo en metros por tela y color.',
          ko: '«Materia prima»에서 원단·색상별 미터 잔량을 조회합니다.',
        },
        {
          es: 'Los consumos de producción y los retazos se registran como movimientos.',
          ko: '생산 소비와 자투리(retazo)는 이동 기록으로 남습니다.',
        },
      ],
      tips: [
        {
          es: 'El detalle completo está en el Manual de Materia Prima.',
          ko: '자세한 내용은 Materia Prima 매뉴얼을 참고하세요.',
        },
      ],
    },
    {
      id: 'talleres',
      title: { es: 'Producción y talleres', ko: '생산과 외주 탈레르' },
      capture: 'stock-08-talleres',
      intro: {
        es: 'La producción externa (talleres) genera ingresos de prendas terminadas al stock. Aquí solo se resume; el flujo completo está en el Manual de Talleres.',
        ko: '외주 생산(탈레르)은 완제품 입고로 재고에 반영됩니다. 여기서는 요약만 하며 전체 흐름은 Talleres 매뉴얼에 있습니다.',
      },
      steps: [
        {
          es: 'Verifique que las recepciones de taller ingresen el stock en la sucursal correcta.',
          ko: '탈레르 수령이 올바른 지점 재고로 입고되는지 확인하세요.',
        },
        {
          es: 'Controle mermas y diferencias entre lo enviado y lo recibido.',
          ko: '보낸 수량과 받은 수량의 차이·로스를 관리하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'excel',
      title: { es: 'Exportar reportes a Excel', ko: '보고서 Excel 내보내기' },
      capture: 'stock-09-excel',
      intro: {
        es: 'La mayoría de los listados y reportes se exportan a Excel para análisis propios o para compartir.',
        ko: '대부분의 목록·보고서는 자체 분석이나 공유를 위해 Excel로 내보낼 수 있습니다.',
      },
      steps: [
        {
          es: 'Aplique primero los filtros deseados (fecha, sucursal, categoría).',
          ko: '먼저 원하는 필터(날짜, 지점, 카테고리)를 적용합니다.',
        },
        {
          es: 'Use el botón de exportación: el archivo respeta los filtros aplicados.',
          ko: '내보내기 버튼을 누르면 적용된 필터 그대로 파일이 생성됩니다.',
        },
      ],
      tips: [],
    },
  ],
};
