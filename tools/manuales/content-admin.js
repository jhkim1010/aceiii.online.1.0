// Manual de Admin — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/admin/<capture>.png

module.exports = {
  area: 'Admin',
  fileBase: 'Manual_Admin_VentaGO',
  captureDir: 'admin',
  title: { es: 'Manual de Administración', ko: '관리(Admin) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Organización, usuarios, seguridad y configuración',
    ko: 'VentaGO — 조직 구조, 사용자, 보안, 설정 가이드',
  },
  intro: {
    es: 'Este manual está dirigido a dueños y administradores. Cubre la estructura de la tienda (sucursales, cajas, terminales), la gestión de usuarios y permisos, la seguridad de sesiones, los gastos, los agentes de impresión y los tableros de control.',
    ko: '이 매뉴얼은 매장 소유자와 관리자를 위한 것입니다. 매장 구조(지점, 카하, 터미널), 사용자·권한 관리, 세션 보안, 지출, 프린터 에이전트, 대시보드를 다룹니다.',
  },
  topics: [
    {
      id: 'estructura',
      title: { es: 'Estructura: tienda → sucursal → caja → terminal', ko: '구조: 매장 → 지점 → 카하 → 터미널' },
      capture: 'admin-01-estructura',
      intro: {
        es: 'VentaGO organiza la operación en cuatro niveles: la tienda (empresa), sus sucursales, las cajas de cada sucursal y los terminales (puestos) de cada caja. Al crear una sucursal, se genera automáticamente una caja y un terminal por defecto.',
        ko: 'VentaGO는 운영을 4단계로 구성합니다: 매장(회사) → 지점 → 지점별 카하 → 카하별 터미널(포스 자리). 지점을 만들면 기본 카하와 터미널이 자동 생성됩니다.',
      },
      steps: [
        {
          es: 'Entre a «Sucursales» para ver y administrar las sucursales de la tienda.',
          ko: '«Sucursales» 메뉴에서 매장의 지점을 확인·관리합니다.',
        },
        {
          es: 'Cree una sucursal nueva con su nombre y dirección; la caja y el terminal por defecto se crean solos.',
          ko: '이름과 주소로 새 지점을 만들면 기본 카하·터미널이 자동 생성됩니다.',
        },
        {
          es: 'Agregue cajas o terminales adicionales solo si la sucursal tiene más de un puesto de cobro.',
          ko: '결제 포스가 둘 이상인 지점에만 카하/터미널을 추가하세요.',
        },
      ],
      tips: [
        {
          es: 'El terminal es la unidad a la que se asignan impresoras (comandera y Zebra).',
          ko: '터미널은 프린터(코만데라·Zebra)가 지정되는 단위입니다.',
        },
      ],
    },
    {
      id: 'usuarios',
      title: { es: 'Usuarios, roles y permisos', ko: '사용자, 역할, 권한' },
      capture: 'admin-02-usuarios',
      intro: {
        es: 'Cada empleado tiene su usuario con un rol (vendedor, gerente, administrador…). El rol define qué menús y acciones puede usar.',
        ko: '직원마다 역할(판매원, 매니저, 관리자 등)이 있는 계정을 갖습니다. 역할이 사용 가능한 메뉴와 액션을 결정합니다.',
      },
      steps: [
        {
          es: 'Entre a «Usuarios» y cree el usuario con su correo, nombre y sucursal asignada.',
          ko: '«Usuarios»에서 이메일, 이름, 소속 지점을 입력해 계정을 만듭니다.',
        },
        {
          es: 'Asigne el rol adecuado. Los permisos finos (por función) se administran en la pantalla de roles.',
          ko: '적절한 역할을 지정합니다. 세부 권한(기능 단위)은 역할 화면에서 관리합니다.',
        },
        {
          es: 'Para dar de baja a un empleado, desactive su usuario: el historial de sus operaciones se conserva.',
          ko: '퇴사자는 계정을 비활성화하세요. 해당 직원의 거래 이력은 보존됩니다.',
        },
      ],
      tips: [
        {
          es: 'Dé permisos de anulación de ventas y ajustes de stock solo a encargados.',
          ko: '판매 취소·재고 조정 권한은 책임자에게만 부여하세요.',
        },
      ],
    },
    {
      id: 'seguridad',
      title: { es: 'Seguridad de sesión: dispositivos e IPs', ko: '세션 보안: 디바이스와 IP' },
      capture: 'admin-03-seguridad',
      intro: {
        es: 'VentaGO bloquea el doble inicio de sesión: al entrar desde otro equipo, la sesión anterior se cierra. Además, cada computadora (huella del navegador) y cada conexión (IP pública) deben estar registradas.',
        ko: 'VentaGO는 중복 로그인을 차단합니다. 다른 기기에서 로그인하면 기존 세션이 종료됩니다. 또한 각 컴퓨터(브라우저 지문)와 회선(공인 IP)은 등록되어야 합니다.',
      },
      steps: [
        {
          es: 'Cuando un empleado usa una PC nueva, el sistema pide registrar el terminal: verifique que la sucursal elegida sea correcta.',
          ko: '직원이 새 PC를 쓰면 터미널 등록 창이 뜹니다. 선택한 지점이 맞는지 확인하세요.',
        },
        {
          es: 'Cuando cambia el internet de la sucursal (IP nueva), autorice el registro de la IP.',
          ko: '지점 인터넷이 바뀌어 IP가 새로 잡히면 IP 등록을 승인하세요.',
        },
        {
          es: 'Ante avisos de «sesión expirada» frecuentes, revise si dos personas comparten el mismo usuario.',
          ko: '«세션 만료» 알림이 잦으면 두 사람이 같은 계정을 쓰는지 확인하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'configuracion',
      title: { es: 'Configuración de la tienda: logo y datos', ko: '매장 설정: 로고와 기본 정보' },
      capture: 'admin-04-configuracion',
      intro: {
        es: 'En «Configuración» se cargan el logo, el alias comercial y los datos de la tienda que aparecen en la barra lateral y en los tickets.',
        ko: '«Configuración»에서 로고, 상호 별칭, 매장 정보를 등록합니다. 사이드바와 영수증에 표시됩니다.',
      },
      steps: [
        {
          es: 'Suba el logo (imagen cuadrada recomendada): se muestra en la barra lateral y en la pantalla de inicio de sesión de su equipo.',
          ko: '로고(정사각형 권장)를 업로드하면 사이드바 등에 표시됩니다.',
        },
        {
          es: 'Complete alias, dirección y datos fiscales usados en la impresión de tickets.',
          ko: '별칭, 주소, 세무 정보를 입력하세요. 영수증 출력에 사용됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'gastos',
      title: { es: 'Gastos: categorías y registro', ko: '지출: 카테고리와 기록' },
      capture: 'admin-05-gastos',
      intro: {
        es: 'El módulo «Gastos» registra las salidas de dinero (alquiler, servicios, compras menores) con su categoría, para verlas luego en los reportes financieros.',
        ko: '«Gastos» 모듈은 임대료, 공과금, 소모품 등 지출을 카테고리와 함께 기록해 재무 보고서에 반영합니다.',
      },
      steps: [
        {
          es: 'Defina primero las categorías de gasto (alquiler, luz, limpieza…).',
          ko: '먼저 지출 카테고리(임대, 전기, 청소 등)를 정의합니다.',
        },
        {
          es: 'Registre cada gasto con fecha, monto, categoría y sucursal; adjunte comprobante si corresponde.',
          ko: '지출마다 날짜, 금액, 카테고리, 지점을 기록하고 필요시 증빙을 첨부합니다.',
        },
        {
          es: 'Los gastos pagados desde la caja se descuentan del arqueo del día.',
          ko: '금전함에서 지급한 지출은 당일 정산에서 차감됩니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'agentes',
      title: { es: 'Agentes de impresión (comandera y Zebra)', ko: '프린터 에이전트(코만데라·Zebra)' },
      capture: 'admin-06-agentes',
      intro: {
        es: 'Los agentes son programas instalados en una PC de la sucursal que conectan las impresoras con VentaGO: el agente térmico imprime tickets/comandas y el agente Zebra imprime etiquetas. Cada agente se autentica con su API Key.',
        ko: '에이전트는 지점 PC에 설치되어 프린터를 VentaGO와 연결하는 프로그램입니다. 열감지 에이전트는 영수증/주방 주문서를, Zebra 에이전트는 라벨을 출력합니다. 에이전트마다 고유 API Key로 인증합니다.',
      },
      steps: [
        {
          es: 'En «Sucursales → Impresora», cree el agente (térmico o Zebra) con una etiqueta descriptiva: se genera su API Key.',
          ko: '«Sucursales → Impresora»에서 에이전트(열감지/Zebra)를 설명 라벨과 함께 생성하면 API Key가 발급됩니다.',
        },
        {
          es: 'Instale la app del agente en la PC de la sucursal (menú Descargas) e ingrese solo la API Key.',
          ko: '지점 PC에 에이전트 앱(다운로드 메뉴)을 설치하고 API Key만 입력합니다.',
        },
        {
          es: 'Verifique el estado «en línea» y haga una impresión de prueba desde la misma pantalla.',
          ko: '«온라인» 상태를 확인하고 같은 화면에서 테스트 출력을 실행하세요.',
        },
        {
          es: 'Asigne en cada terminal qué agente térmico y qué agente Zebra usa (mapeo por terminal).',
          ko: '터미널별로 사용할 열감지/Zebra 에이전트를 지정합니다(터미널 매핑).',
        },
      ],
      tips: [
        {
          es: 'Una sucursal puede tener varios agentes (por ejemplo comandera de cocina y de barra).',
          ko: '한 지점에 에이전트 여러 개(주방용·바용 코만데라 등)를 둘 수 있습니다.',
        },
      ],
    },
    {
      id: 'clientes',
      title: { es: 'Clientes: cuentas corrientes y créditos', ko: '고객: 외상 계정과 크레딧' },
      capture: 'admin-07-clientes',
      intro: {
        es: 'Los clientes registrados pueden comprar a cuenta corriente (crédito) y mantener saldo a favor. El módulo de cuentas corrientes muestra deudas, pagos y movimientos.',
        ko: '등록 고객은 외상(크레딧) 구매와 적립 잔액(a favor)을 사용할 수 있습니다. 외상 계정 모듈에서 부채, 결제, 이동 내역을 확인합니다.',
      },
      steps: [
        {
          es: 'Registre al cliente con su documento (CUIT/DNI) para habilitar cuenta corriente.',
          ko: '외상 거래를 하려면 고객을 서류 번호(CUIT/DNI)와 함께 등록하세요.',
        },
        {
          es: 'Consulte la deuda en «Cuentas corrientes» y registre los pagos que el cliente hace.',
          ko: '«Cuentas corrientes»에서 부채를 확인하고 고객의 상환을 기록합니다.',
        },
        {
          es: 'Las devoluciones pueden dejarse como saldo a favor para futuras compras.',
          ko: '반품 금액은 다음 구매를 위한 적립 잔액으로 남길 수 있습니다.',
        },
      ],
      tips: [
        {
          es: 'Cargue siempre el documento del cliente: sin CUIT/DNI válido no se comparte entre sucursales.',
          ko: '고객 서류 번호를 꼭 입력하세요. 유효한 CUIT/DNI가 없으면 지점 간 공유가 되지 않습니다.',
        },
      ],
    },
    {
      id: 'dashboards',
      title: { es: 'Dashboards: lectura de indicadores', ko: '대시보드: 지표 읽기' },
      capture: 'admin-08-dashboards',
      intro: {
        es: 'Los tableros muestran ventas por día, sucursal y vendedor, productos más vendidos y evolución de la caja, para decidir con datos.',
        ko: '대시보드는 일별·지점별·판매원별 매출, 인기 상품, 금전함 추이를 보여줘 데이터 기반 의사결정을 돕습니다.',
      },
      steps: [
        {
          es: 'Entre a «Dashboards» y elija el período y la sucursal a analizar.',
          ko: '«Dashboards»에서 분석할 기간과 지점을 선택합니다.',
        },
        {
          es: 'Compare ventas contra días o semanas anteriores para detectar tendencias.',
          ko: '이전 일/주와 비교해 추세를 파악하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'auditoria',
      title: { es: 'Auditoría de acciones', ko: '작업 감사(Audit)' },
      capture: 'admin-09-auditoria',
      intro: {
        es: 'El registro de auditoría guarda quién hizo qué y cuándo (altas, cambios de precio, anulaciones), útil para revisar operaciones sensibles.',
        ko: '감사 로그는 누가 언제 무엇을 했는지(등록, 가격 변경, 취소) 기록합니다. 민감한 작업 검토에 유용합니다.',
      },
      steps: [
        {
          es: 'Entre al registro de auditoría y filtre por usuario, módulo o fecha.',
          ko: '감사 로그에서 사용자, 모듈, 날짜로 필터링합니다.',
        },
        {
          es: 'Revise especialmente anulaciones de ventas y cambios masivos de precios.',
          ko: '특히 판매 취소와 대량 가격 변경을 정기적으로 검토하세요.',
        },
      ],
      tips: [],
    },
  ],
};
