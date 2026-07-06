// Manual de Talleres — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/talleres/<capture>.png

module.exports = {
  area: 'Talleres',
  fileBase: 'Manual_Talleres_VentaGO',
  captureDir: 'talleres',
  title: { es: 'Manual de Talleres', ko: '외주 생산(Talleres) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Producción externa: cortes, envíos, recepción y liquidación',
    ko: 'VentaGO — 외주 생산: 재단, 발송, 수령, 정산 가이드',
  },
  intro: {
    es: 'Este manual cubre el ciclo completo de producción con talleres externos: definición de etapas, ficha de costos (BOM), ticket de corte, envíos y recepciones, control de mermas y liquidación de pagos al taller.',
    ko: '이 매뉴얼은 외주 탈레르 생산 사이클 전체를 다룹니다: 단계(etapa) 정의, 원가표(BOM), 재단 티켓, 발송·수령, 로스 관리, 탈레르 정산까지입니다.',
  },
  topics: [
    {
      id: 'etapas',
      title: { es: 'Concepto general: etapas del flujo', ko: '개념: 생산 흐름의 단계' },
      capture: 'talleres-01-etapas',
      intro: {
        es: 'La producción avanza por etapas (corte, confección, terminación…). Cada prenda en proceso está siempre en una etapa y un taller responsable.',
        ko: '생산은 단계(재단, 봉제, 마무리 등)로 진행됩니다. 공정 중인 제품은 항상 하나의 단계와 담당 탈레르에 속합니다.',
      },
      steps: [
        {
          es: 'Revise las etapas configuradas en «Talleres»: representan su flujo real de producción.',
          ko: '«Talleres»에 설정된 단계를 확인하세요. 실제 생산 흐름을 반영해야 합니다.',
        },
        {
          es: 'Cada movimiento entre etapas queda registrado con fecha y responsable.',
          ko: '단계 간 이동은 날짜·담당자와 함께 기록됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'vendors',
      title: { es: 'Talleres (vendors): alta y datos', ko: '탈레르(공방) 등록과 정보' },
      capture: 'talleres-02-vendors',
      intro: {
        es: 'Cada taller externo se registra con sus datos, especialidad y tarifas por prenda.',
        ko: '외주 탈레르는 정보, 전문 분야, 벌당 단가와 함께 등록합니다.',
      },
      steps: [
        {
          es: 'Cree el taller con nombre, contacto y tipo de trabajo (corte, confección…).',
          ko: '이름, 연락처, 작업 유형(재단, 봉제 등)으로 탈레르를 등록합니다.',
        },
        {
          es: 'Cargue las tarifas acordadas por prenda o por trabajo para la liquidación.',
          ko: '정산을 위해 합의된 벌당/작업당 단가를 입력합니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'bom',
      title: { es: 'Ficha de costos (BOM)', ko: '원가표(BOM)' },
      capture: 'talleres-03-bom',
      intro: {
        es: 'La ficha de costos define qué materiales y cuánto consume cada producto (tela, avíos) más los costos de trabajo, para calcular el costo real de la prenda.',
        ko: '원가표(BOM)는 제품별 자재(원단, 부자재) 소요량과 작업비를 정의해 실제 원가를 계산합니다.',
      },
      steps: [
        {
          es: 'Abra la ficha de costos del producto y agregue los materiales con su consumo por prenda (por ejemplo 1,2 m de tela).',
          ko: '제품의 원가표를 열어 자재와 벌당 소요량(예: 원단 1.2m)을 추가합니다.',
        },
        {
          es: 'Agregue los costos de trabajo por etapa (corte, confección).',
          ko: '단계별 작업비(재단, 봉제)를 추가합니다.',
        },
        {
          es: 'El costo total se recalcula con los precios vigentes de los materiales.',
          ko: '자재 최신 단가로 총원가가 재계산됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'corte',
      title: { es: 'Ticket de corte', ko: '재단 티켓(Ticket de corte)' },
      capture: 'talleres-04-corte',
      intro: {
        es: 'El ticket de corte inicia la producción: define el producto, las cantidades por variante y descuenta la tela consumida del inventario de materia prima.',
        ko: '재단 티켓이 생산의 시작입니다. 제품과 변형별 수량을 정하고, 소비된 원단을 원자재 재고에서 차감합니다.',
      },
      steps: [
        {
          es: 'Cree el ticket eligiendo el producto y las cantidades por color/talla a producir.',
          ko: '생산할 제품과 색상/사이즈별 수량을 선택해 티켓을 만듭니다.',
        },
        {
          es: 'Cargue los metros de tela realmente usados y la merma del corte.',
          ko: '실제 사용한 원단 미터와 재단 로스를 입력합니다.',
        },
        {
          es: 'Confirme: el consumo se descuenta de materia prima y las prendas quedan «en proceso».',
          ko: '확정하면 원자재에서 소비가 차감되고 제품은 «공정 중» 상태가 됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'envios',
      title: { es: 'Envíos a taller', ko: '탈레르 발송' },
      capture: 'talleres-05-envios',
      intro: {
        es: 'Los envíos documentan qué se manda a cada taller (prendas cortadas, materiales) con remito para su seguimiento.',
        ko: '발송은 각 탈레르에 보내는 것(재단물, 자재)을 송장과 함께 문서화해 추적을 가능하게 합니다.',
      },
      steps: [
        {
          es: 'Cree el envío eligiendo taller, etapa y las prendas/cantidades que van.',
          ko: '탈레르, 단계, 보낼 제품·수량을 선택해 발송을 생성합니다.',
        },
        {
          es: 'Imprima el remito para que viaje con la mercadería.',
          ko: '상품과 함께 이동할 송장을 출력하세요.',
        },
        {
          es: 'El tablero muestra qué está en poder de cada taller y hace cuánto tiempo.',
          ko: '보드에서 탈레르별 보유 물량과 경과일을 확인할 수 있습니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'recepcion',
      title: { es: 'Recepción e ingreso a stock', ko: '수령과 재고 입고' },
      capture: 'talleres-06-recepcion',
      intro: {
        es: 'Al volver del taller, se registra la recepción: las prendas terminadas ingresan al stock de la sucursal elegida.',
        ko: '탈레르에서 돌아오면 수령을 기록합니다. 완성품은 선택한 지점 재고로 입고됩니다.',
      },
      steps: [
        {
          es: 'Registre la recepción contra el envío correspondiente, cargando cantidades recibidas por variante.',
          ko: '해당 발송 건에 대해 변형별 수령 수량을 입력해 수령을 기록합니다.',
        },
        {
          es: 'Elija la sucursal de destino: el stock del producto aumenta allí.',
          ko: '입고 지점을 선택하면 그 지점의 상품 재고가 증가합니다.',
        },
        {
          es: 'Las prendas terminadas ya pueden etiquetarse (Zebra) y venderse.',
          ko: '완성품은 바로 라벨(Zebra) 출력 후 판매할 수 있습니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'mermas',
      title: { es: 'Control de mermas y diferencias', ko: '로스·차이 관리' },
      capture: 'talleres-07-mermas',
      intro: {
        es: 'Comparar lo enviado contra lo recibido detecta pérdidas, fallas y demoras por taller.',
        ko: '발송 수량과 수령 수량을 비교해 탈레르별 손실, 불량, 지연을 파악합니다.',
      },
      steps: [
        {
          es: 'Revise las diferencias por envío: prendas falladas o faltantes.',
          ko: '발송 건별 차이(불량·부족)를 검토합니다.',
        },
        {
          es: 'Registre las fallas para descontarlas de la liquidación si corresponde.',
          ko: '불량은 기록해 필요시 정산에서 차감하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'liquidacion',
      title: { es: 'Liquidación y pagos al taller', ko: '탈레르 정산과 지급' },
      capture: 'talleres-08-liquidacion',
      intro: {
        es: 'La liquidación calcula lo adeudado a cada taller según las prendas recibidas y las tarifas acordadas.',
        ko: '정산은 수령한 수량과 합의 단가로 탈레르별 지급액을 계산합니다.',
      },
      steps: [
        {
          es: 'Genere la liquidación del período por taller: lista prendas recibidas × tarifa.',
          ko: '기간별 탈레르 정산을 생성합니다(수령 수량 × 단가).',
        },
        {
          es: 'Registre el pago y quede el saldo actualizado.',
          ko: '지급을 기록하면 잔액이 갱신됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'reportes',
      title: { es: 'Reportes de producción', ko: '생산 보고서' },
      capture: 'talleres-09-reportes',
      intro: {
        es: 'Los reportes muestran producción por período, costos reales contra ficha y desempeño por taller.',
        ko: '보고서는 기간별 생산량, 원가표 대비 실제 원가, 탈레르별 성과를 보여줍니다.',
      },
      steps: [
        {
          es: 'Compare el costo real (materiales + trabajo) contra el costo de la ficha.',
          ko: '실제 원가(자재+작업)를 원가표와 비교하세요.',
        },
        {
          es: 'Evalúe talleres por tiempos de entrega y porcentaje de fallas.',
          ko: '납기와 불량률로 탈레르를 평가하세요.',
        },
      ],
      tips: [],
    },
  ],
};
