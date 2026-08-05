// Manual de Ventas — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/ventas/<capture>.png 존재 시 자동 삽입, 없으면 자리표시자.

module.exports = {
  area: 'Ventas',
  fileBase: 'Manual_Ventas_VentaGO',
  captureDir: 'ventas',
  title: { es: 'Manual de Ventas', ko: '판매(Ventas) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Guía operativa para vendedores',
    ko: 'VentaGO — 판매원용 운영 가이드',
  },
  intro: {
    es: 'Este manual explica el flujo completo de ventas en VentaGO: desde el inicio de sesión hasta el cierre de caja, incluyendo ventas con variantes (código madre), medios de pago, ventas suspendidas y el modo restaurante. Cada tema incluye capturas de pantalla reales del sistema.',
    ko: '이 매뉴얼은 VentaGO의 판매 흐름 전체를 설명합니다: 로그인부터 금전함 마감까지, 변형 상품(코드 마드레) 판매, 결제 수단, 판매 보류, 식당 모드를 포함합니다. 각 주제에는 실제 시스템 화면 캡처가 포함됩니다.',
  },
  topics: [
    {
      id: 'login',
      title: { es: 'Iniciar sesión y registro de terminal', ko: '로그인과 터미널 등록' },
      capture: 'ventas-01-login',
      intro: {
        es: 'VentaGO permite una sola sesión activa por usuario. La primera vez que se usa una computadora nueva o una conexión de internet nueva, el sistema pide registrar el terminal y la sucursal.',
        ko: 'VentaGO는 사용자당 하나의 활성 세션만 허용합니다. 새 컴퓨터나 새 인터넷 회선에서 처음 접속하면 시스템이 터미널과 지점 등록을 요구합니다.',
      },
      steps: [
        {
          es: 'Abra el navegador y entre a app.coolsistema.com. Ingrese su usuario y contraseña.',
          ko: '브라우저에서 app.coolsistema.com 에 접속해 아이디와 비밀번호를 입력합니다.',
        },
        {
          es: 'Si es la primera vez en esta PC, aparecerá el aviso de registro de terminal: elija la sucursal y la caja que corresponden a este puesto.',
          ko: '이 PC에서 처음 접속하는 경우 터미널 등록 창이 나타납니다. 이 자리에 해당하는 지점(sucursal)과 카하(caja)를 선택하세요.',
        },
        {
          es: 'Si la conexión de internet es nueva, el sistema pedirá asociar la IP a una sucursal. Confirme con el administrador antes de registrar.',
          ko: '인터넷 회선이 새 것이면 IP를 지점에 연결하라는 창이 나타납니다. 등록 전에 관리자에게 확인하세요.',
        },
        {
          es: 'Si aparece el mensaje «Sesión expirada», significa que alguien inició sesión con su usuario en otro equipo. Vuelva a iniciar sesión; la otra sesión se cerrará automáticamente.',
          ko: '«Sesión expirada(세션 만료)» 메시지가 보이면 다른 기기에서 같은 계정으로 로그인한 것입니다. 다시 로그인하면 다른 세션은 자동 종료됩니다.',
        },
      ],
      tips: [
        {
          es: 'No comparta su usuario: cada vendedor debe tener el suyo, porque las ventas y la caja se registran por usuario.',
          ko: '계정을 공유하지 마세요. 판매와 금전함 기록이 사용자별로 남기 때문에 판매원마다 본인 계정을 사용해야 합니다.',
        },
      ],
    },
    {
      id: 'pos',
      title: { es: 'Pantalla Nueva Venta: buscar y agregar artículos', ko: 'Nueva Venta 화면: 상품 검색과 담기' },
      capture: 'ventas-02-nueva-venta',
      intro: {
        es: 'La pantalla «Nueva venta» es el punto de venta (POS). Permite buscar artículos por código, por nombre o con lector de código de barras.',
        ko: '«Nueva venta» 화면이 POS(판매 시점) 화면입니다. 코드, 상품명 또는 바코드 스캐너로 상품을 검색할 수 있습니다.',
      },
      steps: [
        {
          es: 'Entre al menú «Nueva venta». El cursor queda en el campo de búsqueda: escanee el código de barras o escriba el código o nombre del artículo.',
          ko: '«Nueva venta» 메뉴로 들어갑니다. 커서가 검색창에 있으므로 바코드를 스캔하거나 상품 코드/이름을 입력하세요.',
        },
        {
          es: 'Seleccione el artículo en la lista de resultados. Se agrega al carrito con cantidad 1.',
          ko: '검색 결과에서 상품을 선택합니다. 수량 1로 장바구니에 추가됩니다.',
        },
        {
          es: 'Para cambiar la cantidad, edite el número en la columna de cantidad. Para quitar un artículo, use el ícono de eliminar de esa fila.',
          ko: '수량을 바꾸려면 수량 칸의 숫자를 수정하세요. 상품을 빼려면 해당 행의 삭제 아이콘을 누릅니다.',
        },
        {
          es: 'El total se actualiza automáticamente a medida que agrega artículos.',
          ko: '상품을 담을 때마다 합계가 자동으로 갱신됩니다.',
        },
      ],
      tips: [
        {
          es: 'Si el artículo no aparece, verifique con el administrador si está cargado y publicado para su sucursal.',
          ko: '상품이 검색되지 않으면 해당 지점에 등록/게시된 상품인지 관리자에게 확인하세요.',
        },
      ],
    },
    {
      id: 'codigo-madre',
      title: { es: 'Vender con código madre (color × talla)', ko: '코드 마드레(색상×사이즈) 판매' },
      capture: 'ventas-03-codigo-madre',
      intro: {
        es: 'Los productos con variantes se manejan con un «código madre». Al seleccionarlo, se abre la tabla de variantes para cargar cantidades por cada combinación de color y talla.',
        ko: '변형(색상/사이즈)이 있는 상품은 «코드 마드레(부모 코드)»로 관리됩니다. 이를 선택하면 색상×사이즈 조합별 수량을 입력하는 변형 표가 열립니다.',
      },
      steps: [
        {
          es: 'Busque el producto por su código madre o nombre y selecciónelo.',
          ko: '코드 마드레 또는 상품명으로 검색해 선택합니다.',
        },
        {
          es: 'En la tabla de variantes (colores en filas, tallas en columnas) escriba la cantidad de cada combinación que lleva el cliente.',
          ko: '변형 표(행=색상, 열=사이즈)에서 고객이 구매하는 조합마다 수량을 입력합니다.',
        },
        {
          es: 'Confirme: las variantes se agregan a la venta. El sistema descuenta el stock de cada variante por separado.',
          ko: '확인하면 변형들이 판매에 추가됩니다. 재고는 변형별로 각각 차감됩니다.',
        },
      ],
      tips: [
        {
          es: 'Aunque una variante figure sin stock, la venta no se bloquea: el stock puede quedar negativo y se corrige luego con un ajuste.',
          ko: '변형 재고가 없어도 판매는 차단되지 않습니다. 재고가 음수가 될 수 있으며 이후 조정으로 바로잡습니다.',
        },
      ],
    },
    {
      id: 'precios',
      title: { es: 'Niveles de precio, descuentos y promociones', ko: '가격 레벨, 할인, 프로모션' },
      capture: 'ventas-04-precios',
      intro: {
        es: 'Cada artículo puede tener varios niveles de precio (por ejemplo: minorista, mayorista). Además se pueden aplicar descuentos y promociones en la venta.',
        ko: '상품마다 여러 가격 레벨(예: 소매가, 도매가)을 가질 수 있습니다. 판매 시 할인과 프로모션도 적용할 수 있습니다.',
      },
      steps: [
        {
          es: 'En la venta, seleccione el tipo de precio que corresponde al cliente (si su rol lo permite).',
          ko: '판매 화면에서 고객에게 해당하는 가격 유형을 선택합니다(권한이 있는 경우).',
        },
        {
          es: 'Para aplicar un descuento, use el campo de descuento del artículo o del total, según lo habilitado por el administrador.',
          ko: '할인은 관리자가 허용한 범위에서 상품별 또는 합계 할인 칸을 사용합니다.',
        },
        {
          es: 'Las promociones activas (por ejemplo 2×1) se aplican automáticamente y los artículos bonificados aparecen marcados.',
          ko: '활성 프로모션(예: 2×1)은 자동 적용되며 증정 상품은 표시가 붙습니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'pagos',
      title: { es: 'Medios de pago y pago mixto', ko: '결제 수단과 복합 결제' },
      capture: 'ventas-05-pagos',
      intro: {
        es: 'Al generar la venta se elige el medio de pago: efectivo, QR de MercadoPago, cuenta corriente (crédito), saldo a favor, u otros configurados. También se puede dividir el pago entre varios medios.',
        ko: '판매 생성 시 결제 수단을 선택합니다: 현금, MercadoPago QR, 외상(크레딧), 적립 잔액(a favor) 등. 여러 수단으로 나눠서 결제할 수도 있습니다.',
      },
      steps: [
        {
          es: 'Presione «Generar venta». Se abre el modal de pago con el total.',
          ko: '«Generar venta»를 누르면 합계가 표시된 결제 창이 열립니다.',
        },
        {
          es: 'Elija el medio de pago. Para efectivo, ingrese el monto recibido y el sistema calcula el vuelto.',
          ko: '결제 수단을 선택합니다. 현금이면 받은 금액을 입력하면 거스름돈이 자동 계산됩니다.',
        },
        {
          es: 'Para QR MercadoPago, muestre el código al cliente y espere la confirmación automática del pago.',
          ko: 'MercadoPago QR은 고객에게 코드를 보여주고 결제 자동 확인을 기다립니다.',
        },
        {
          es: 'Para pago mixto, cargue un monto por cada medio hasta cubrir el total.',
          ko: '복합 결제는 수단별 금액을 합계가 채워질 때까지 나눠 입력합니다.',
        },
        {
          es: 'Para venta a cuenta corriente (crédito), seleccione el cliente registrado; la deuda queda asociada a su cuenta.',
          ko: '외상 판매는 등록된 고객을 선택합니다. 부채가 고객 계정에 기록됩니다.',
        },
      ],
      tips: [
        {
          es: 'El ticket se imprime automáticamente si la comandera está configurada (vea el tema de impresión).',
          ko: '프린터가 설정돼 있으면 영수증이 자동 출력됩니다(출력 주제 참고).',
        },
      ],
    },
    {
      id: 'suspender',
      title: { es: 'Suspender y retomar una venta', ko: '판매 보류와 재개' },
      capture: 'ventas-06-suspender',
      intro: {
        es: 'Si el cliente necesita interrumpir la compra (por ejemplo, va a buscar otro producto), la venta puede suspenderse y retomarse después sin perder los artículos cargados.',
        ko: '고객이 구매를 잠시 중단해야 할 때(예: 다른 상품을 가지러 감) 담아둔 상품을 잃지 않고 판매를 보류했다가 나중에 재개할 수 있습니다.',
      },
      steps: [
        {
          es: 'Con artículos en el carrito, presione «Suspender venta». La venta queda guardada en la lista de suspendidas.',
          ko: '장바구니에 상품이 있는 상태에서 «Suspender venta»를 누르면 보류 목록에 저장됩니다.',
        },
        {
          es: 'Para retomarla, abra la lista de ventas suspendidas y seleccione la venta. Los artículos vuelven al carrito.',
          ko: '재개하려면 보류 판매 목록을 열어 해당 판매를 선택합니다. 상품이 장바구니로 복원됩니다.',
        },
        {
          es: 'Complete la venta normalmente con «Generar venta».',
          ko: '이후 «Generar venta»로 정상적으로 판매를 완료합니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'historial',
      title: { es: 'Historial: anular, devolver y reimprimir', ko: '판매 내역: 취소, 반품, 재출력' },
      capture: 'ventas-07-historial',
      intro: {
        es: 'El menú «Ventas» muestra el historial. Desde ahí se puede ver el detalle, anular una venta, registrar devoluciones y reimprimir tickets.',
        ko: '«Ventas» 메뉴에서 판매 내역을 확인합니다. 상세 보기, 판매 취소, 반품 등록, 영수증 재출력이 가능합니다.',
      },
      steps: [
        {
          es: 'Entre al menú «Ventas» y filtre por fecha, sucursal o vendedor para encontrar la operación.',
          ko: '«Ventas» 메뉴에서 날짜/지점/판매원 필터로 해당 거래를 찾습니다.',
        },
        {
          es: 'Abra el detalle para ver artículos, pagos y estado de la venta.',
          ko: '상세를 열어 상품, 결제, 판매 상태를 확인합니다.',
        },
        {
          es: 'Para anular o devolver, use la acción correspondiente; el stock se reintegra automáticamente.',
          ko: '취소/반품은 해당 액션을 사용합니다. 재고는 자동으로 복구됩니다.',
        },
        {
          es: 'Para reimprimir el ticket, use el botón de impresión de la fila.',
          ko: '영수증 재출력은 행의 출력 버튼을 사용합니다.',
        },
      ],
      tips: [
        {
          es: 'Las anulaciones pueden requerir permiso de administrador según la configuración de su tienda.',
          ko: '매장 설정에 따라 취소에는 관리자 권한이 필요할 수 있습니다.',
        },
      ],
    },
    {
      id: 'caja',
      title: { es: 'Apertura y cierre de caja', ko: '금전함 열기와 마감' },
      capture: 'ventas-08-caja',
      intro: {
        es: 'La caja registra todo el movimiento de dinero del turno: apertura con monto inicial, ventas, gastos, retiros y cierre con arqueo.',
        ko: '금전함은 근무 시간의 모든 현금 흐름을 기록합니다: 시재로 열기, 판매, 지출, 인출, 그리고 정산 마감.',
      },
      steps: [
        {
          es: 'Al comenzar el turno, abra la caja desde el menú «Caja» ingresando el monto inicial (fondo de caja).',
          ko: '근무 시작 시 «Caja» 메뉴에서 시재(초기 금액)를 입력해 금전함을 엽니다.',
        },
        {
          es: 'Durante el día, las ventas en efectivo se suman automáticamente. Registre también gastos o retiros si corresponde.',
          ko: '영업 중 현금 판매는 자동 합산됩니다. 지출·인출이 있으면 함께 기록하세요.',
        },
        {
          es: 'Al cerrar, cuente el efectivo físico y cargue el monto: el sistema muestra la diferencia contra lo esperado.',
          ko: '마감 시 실제 현금을 세어 입력하면 시스템이 예상 금액과의 차이를 표시합니다.',
        },
        {
          es: 'El sobrante que se retira puede transferirse a la caja fuerte, donde queda registrado.',
          ko: '인출한 잉여 현금은 금고(caja fuerte)로 이체해 기록으로 남길 수 있습니다.',
        },
      ],
      tips: [
        {
          es: 'El menú «Control de caja» permite al encargado revisar aperturas, cierres y diferencias de todas las cajas.',
          ko: '«Control de caja» 메뉴에서 관리자는 모든 금전함의 개시/마감/차액을 검토할 수 있습니다.',
        },
      ],
    },
    {
      id: 'restaurante',
      title: { es: 'Modo restaurante: salón y mesas', ko: '식당 모드: 살롱과 테이블' },
      capture: 'ventas-09-restaurante',
      intro: {
        es: 'En tiendas con modo restaurante, la venta se organiza por mesas en el plano del salón. Los colores indican el estado: libre, ocupada o por cobrar.',
        ko: '식당 모드 매장에서는 살롱 배치도의 테이블 단위로 판매를 관리합니다. 색상이 상태를 나타냅니다: 빈 테이블, 사용 중, 결제 대기.',
      },
      steps: [
        {
          es: 'Al entrar a «Nueva venta» en una tienda restaurante se abre el salón con las mesas.',
          ko: '식당 매장에서 «Nueva venta»에 들어가면 테이블이 있는 살롱 화면이 열립니다.',
        },
        {
          es: 'Toque una mesa libre u ocupada para tomar o modificar el pedido (comanda). El pedido se envía a la comandera de cocina.',
          ko: '빈/사용 중 테이블을 눌러 주문(코만다)을 받거나 수정합니다. 주문은 주방 프린터로 전송됩니다.',
        },
        {
          es: 'Cuando la comida sale, marque «Servido». La mesa pasa a «Por cobrar» y muestra el tiempo de espera del pago.',
          ko: '음식이 나가면 «Servido»를 표시합니다. 테이블이 «Por cobrar(결제 대기)»로 바뀌고 대기 시간이 표시됩니다.',
        },
        {
          es: 'Toque la mesa en rojo para cobrar. Se puede unir el pago de varias mesas si el cliente lo pide.',
          ko: '붉은색 테이블을 눌러 결제합니다. 고객 요청 시 여러 테이블 합산 결제도 가능합니다.',
        },
      ],
      tips: [
        {
          es: 'El panel derecho «Resumen» muestra mesas activas, platos por servir y montos en tiempo real.',
          ko: '우측 «Resumen» 패널에 활성 테이블, 서빙 대기 음식, 금액이 실시간 표시됩니다.',
        },
      ],
    },
    {
      id: 'impresion',
      title: { es: 'Impresión de tickets (comandera)', ko: '영수증 출력(코만데라)' },
      capture: 'ventas-10-impresion',
      intro: {
        es: 'La impresión usa el agente de impresión instalado en una PC de la sucursal. Cada terminal puede tener asignada su propia impresora.',
        ko: '출력은 지점 PC에 설치된 프린트 에이전트를 사용합니다. 터미널마다 자기 프린터를 지정할 수 있습니다.',
      },
      steps: [
        {
          es: 'Verifique el indicador de impresora en el POS: verde significa agente conectado.',
          ko: 'POS의 프린터 표시등을 확인하세요. 초록색이면 에이전트가 연결된 상태입니다.',
        },
        {
          es: 'Al generar la venta, el ticket sale por la impresora asignada al terminal. Si no hay asignación, imprime la comandera general de la sucursal.',
          ko: '판매 생성 시 터미널에 지정된 프린터로 영수증이 나옵니다. 지정이 없으면 지점 공용 프린터로 출력됩니다.',
        },
        {
          es: 'Si el ticket no sale, avise al administrador para revisar el agente (prueba de impresión desde Sucursales → Impresora).',
          ko: '영수증이 안 나오면 관리자에게 알려 에이전트를 점검하세요(Sucursales → Impresora에서 테스트 출력).',
        },
      ],
      tips: [
        {
          es: 'La venta queda registrada aunque falle la impresión: siempre se puede reimprimir desde el historial.',
          ko: '출력이 실패해도 판매는 기록됩니다. 내역에서 언제든 재출력할 수 있습니다.',
        },
      ],
    },
  ],
};
