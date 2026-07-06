// Manual de Materia Prima — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/materia-prima/<capture>.png

module.exports = {
  area: 'MateriaPrima',
  fileBase: 'Manual_MateriaPrima_VentaGO',
  captureDir: 'materia-prima',
  title: { es: 'Manual de Materia Prima', ko: '원자재(Materia Prima) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Telas, unidades duales, movimientos y pagos a proveedores',
    ko: 'VentaGO — 원단, 이중 단위, 이동, 공급자 결제 가이드',
  },
  intro: {
    es: 'Este manual explica la gestión de materia prima (telas): alta de materiales con variantes de color, compra en rollos o kilos con consumo en metros, movimientos de inventario (consumo, merma, retazos), proveedores y sus pagos.',
    ko: '이 매뉴얼은 원자재(원단) 관리를 설명합니다: 색상 변형이 있는 자재 등록, 롤/kg 구매와 미터 소비(이중 단위), 재고 이동(소비, 로스, 자투리), 공급자와 결제까지 다룹니다.',
  },
  topics: [
    {
      id: 'alta-materiales',
      title: { es: 'Alta de materiales: telas madre y colores', ko: '자재 등록: 원단 마스터와 색상' },
      capture: 'mp-01-alta',
      intro: {
        es: 'Cada tela se registra una vez como «tela madre» con sus variantes de color. El código de material identifica tela + color.',
        ko: '원단은 «텔라 마드레(원단 마스터)»로 한 번 등록하고 색상 변형을 추가합니다. 자재 코드는 원단+색상을 식별합니다.',
      },
      steps: [
        {
          es: 'Entre a «Materia prima» y cree la tela con su nombre, composición y proveedor habitual.',
          ko: '«Materia prima»에서 원단 이름, 혼용률, 주 공급자를 입력해 등록합니다.',
        },
        {
          es: 'Agregue los colores de la tela: cada color es una variante con su propio código y stock.',
          ko: '원단의 색상을 추가합니다. 색상마다 고유 코드와 재고를 가진 변형이 됩니다.',
        },
        {
          es: 'Defina la unidad de compra (rollo o kg) y el rendimiento en metros.',
          ko: '구매 단위(롤/kg)와 미터 환산 수율을 정의합니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'unidades',
      title: { es: 'Unidades duales: rollo/kg ↔ metros', ko: '이중 단위: 롤/kg ↔ 미터' },
      capture: 'mp-02-unidades',
      intro: {
        es: 'Las telas se compran en rollos o kilos, pero la producción consume metros. VentaGO guarda la verdad del stock en la unidad de consumo (metros) y convierte automáticamente al ingresar compras.',
        ko: '원단은 롤/kg로 구매하지만 생산은 미터로 소비합니다. VentaGO는 재고의 기준을 소비 단위(미터)로 저장하고, 구매 입고 시 자동 환산합니다.',
      },
      steps: [
        {
          es: 'Al ingresar una compra, cargue la cantidad en la unidad de compra (por ejemplo 3 rollos o 25 kg).',
          ko: '구매 입고 시 구매 단위 수량(예: 3롤, 25kg)을 입력합니다.',
        },
        {
          es: 'El sistema convierte a metros con el rendimiento configurado y suma al stock.',
          ko: '시스템이 설정된 수율로 미터로 환산해 재고에 더합니다.',
        },
        {
          es: 'Si el rendimiento real difiere (rollo más corto), ajuste los metros al ingresar.',
          ko: '실제 수율이 다르면(롤이 짧으면) 입고 시 미터를 수정하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'compras',
      title: { es: 'Ingreso de compra: proveedor, rollos y costo', ko: '구매 입고: 공급자, 롤, 원가' },
      capture: 'mp-03-compras',
      intro: {
        es: 'Cada ingreso registra proveedor, cantidad, costo unitario y fecha, alimentando el stock y la cuenta del proveedor.',
        ko: '입고마다 공급자, 수량, 단가, 날짜를 기록하며 재고와 공급자 계정에 반영됩니다.',
      },
      steps: [
        {
          es: 'Cree el ingreso eligiendo proveedor y tela/color.',
          ko: '공급자와 원단/색상을 선택해 입고를 생성합니다.',
        },
        {
          es: 'Cargue cantidad (unidad de compra), costo y observaciones (número de remito).',
          ko: '수량(구매 단위), 원가, 비고(송장 번호)를 입력합니다.',
        },
        {
          es: 'Confirme: el stock en metros aumenta y la deuda con el proveedor queda registrada.',
          ko: '확정하면 미터 재고가 늘고 공급자 부채가 기록됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'inventario',
      title: { es: 'Inventario: consulta de stock de telas', ko: '재고: 원단 재고 조회' },
      capture: 'mp-04-inventario',
      intro: {
        es: 'La pantalla de inventario muestra el saldo en metros por tela y color, con su valorización.',
        ko: '재고 화면은 원단·색상별 미터 잔량과 평가액을 보여줍니다.',
      },
      steps: [
        {
          es: 'Filtre por tela, color o proveedor para encontrar el material.',
          ko: '원단, 색상, 공급자로 필터링해 자재를 찾습니다.',
        },
        {
          es: 'Revise el saldo antes de planificar cortes de producción.',
          ko: '생산 재단을 계획하기 전에 잔량을 확인하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'movimientos',
      title: { es: 'Movimientos: consumo, merma y retazos', ko: '이동: 소비, 로스(merma), 자투리(retazo)' },
      capture: 'mp-05-movimientos',
      intro: {
        es: 'Todos los cambios de stock quedan como movimientos: consumo de producción, merma (pérdida) y retazos que vuelven como ajuste.',
        ko: '모든 재고 변화는 이동으로 기록됩니다: 생산 소비, 로스(merma), 그리고 조정으로 되돌아오는 자투리(retazo).',
      },
      steps: [
        {
          es: 'El consumo se genera desde el ticket de corte de talleres (metros usados).',
          ko: '소비는 탈레르 재단 티켓에서 생성됩니다(사용 미터).',
        },
        {
          es: 'La merma registrada se descuenta del stock como pérdida.',
          ko: '기록된 로스는 손실로 재고에서 차감됩니다.',
        },
        {
          es: 'Los retazos aprovechables se reingresan con un ajuste positivo.',
          ko: '사용 가능한 자투리는 플러스 조정으로 재입고합니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'proveedores',
      title: { es: 'Proveedores de materia prima', ko: '원자재 공급자' },
      capture: 'mp-06-proveedores',
      intro: {
        es: 'Los proveedores de tela se administran con sus datos de contacto y condiciones, separados de los proveedores de mercadería.',
        ko: '원단 공급자는 연락처와 거래 조건과 함께 관리되며 완제품 공급자와 구분됩니다.',
      },
      steps: [
        {
          es: 'Registre el proveedor con nombre, CUIT y contacto.',
          ko: '이름, CUIT, 연락처로 공급자를 등록합니다.',
        },
        {
          es: 'Asocie las telas que le compra para agilizar los ingresos.',
          ko: '거래 원단을 연결해 두면 입고 등록이 빨라집니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'pagos',
      title: { es: 'Pagos a proveedores', ko: '공급자 결제' },
      capture: 'mp-07-pagos',
      intro: {
        es: 'La sección «Pagos» muestra la deuda por proveedor y permite registrar pagos parciales o totales.',
        ko: '«Pagos» 섹션에서 공급자별 부채를 확인하고 부분/전액 결제를 기록합니다.',
      },
      steps: [
        {
          es: 'Abra «Materia prima → Pagos» y elija el proveedor.',
          ko: '«Materia prima → Pagos»에서 공급자를 선택합니다.',
        },
        {
          es: 'Registre el pago con fecha, monto y medio (efectivo, transferencia).',
          ko: '날짜, 금액, 수단(현금/이체)과 함께 결제를 기록합니다.',
        },
        {
          es: 'El saldo pendiente se actualiza y queda el historial de pagos.',
          ko: '미결제 잔액이 갱신되고 결제 이력이 남습니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'codigos',
      title: { es: 'Códigos de material y etiquetas', ko: '자재 코드와 라벨' },
      capture: 'mp-08-codigos',
      intro: {
        es: 'Cada tela/color tiene un código propio que puede imprimirse en etiqueta para identificar rollos en el depósito.',
        ko: '원단/색상마다 고유 코드가 있으며 라벨로 출력해 창고의 롤을 식별할 수 있습니다.',
      },
      steps: [
        {
          es: 'Consulte el código del material en su detalle.',
          ko: '자재 상세에서 코드를 확인합니다.',
        },
        {
          es: 'Imprima la etiqueta con el agente Zebra para pegarla en el rollo.',
          ko: 'Zebra 에이전트로 라벨을 출력해 롤에 부착하세요.',
        },
      ],
      tips: [],
    },
  ],
};
