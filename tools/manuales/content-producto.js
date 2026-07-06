// Manual de Producto — 콘텐츠 정의 (ES/KO 병기)
// 캡처: docs/manual-captures/producto/<capture>.png

module.exports = {
  area: 'Producto',
  fileBase: 'Manual_Producto_VentaGO',
  captureDir: 'producto',
  title: { es: 'Manual de Producto', ko: '상품(Producto) 매뉴얼' },
  subtitle: {
    es: 'VentaGO — Alta y gestión de artículos, precios y etiquetas',
    ko: 'VentaGO — 상품 등록·관리, 가격, 라벨 가이드',
  },
  intro: {
    es: 'Este manual explica cómo cargar y administrar productos en VentaGO: productos simples, códigos madre con variantes de color y talla, precios por nivel, reposición de stock, etiquetas de código de barras y publicación en la tienda online.',
    ko: '이 매뉴얼은 VentaGO의 상품 등록과 관리를 설명합니다: 단일 상품, 색상·사이즈 변형이 있는 코드 마드레, 가격 레벨, 재입고, 바코드 라벨, 온라인숍 게시까지 다룹니다.',
  },
  topics: [
    {
      id: 'alta-simple',
      title: { es: 'Alta de producto simple', ko: '단일 상품 등록' },
      capture: 'producto-01-alta',
      intro: {
        es: 'Un producto simple no tiene variantes. Se carga desde el menú «Productos» con sus datos básicos, precios y stock inicial.',
        ko: '단일 상품은 변형이 없는 상품입니다. «Productos» 메뉴에서 기본 정보, 가격, 초기 재고를 입력해 등록합니다.',
      },
      steps: [
        {
          es: 'Entre a «Productos» y presione el botón de nuevo producto.',
          ko: '«Productos» 메뉴에서 새 상품 버튼을 누릅니다.',
        },
        {
          es: 'Complete los datos básicos: nombre, categoría, temporada, origen y proveedor. El SKU se genera automáticamente con el prefijo configurado.',
          ko: '기본 정보를 입력합니다: 이름, 카테고리, 시즌, 원산지, 공급자. SKU는 설정된 접두어로 자동 생성됩니다.',
        },
        {
          es: 'Cargue los precios de cada nivel habilitado (por ejemplo Precio 1 minorista, Precio 2 mayorista).',
          ko: '활성화된 가격 레벨별 금액을 입력합니다(예: Precio 1 소매, Precio 2 도매).',
        },
        {
          es: 'Indique el stock inicial por sucursal si corresponde y guarde.',
          ko: '필요하면 지점별 초기 재고를 입력하고 저장합니다.',
        },
      ],
      tips: [
        {
          es: 'Active «publicar» solo cuando el artículo esté listo para venderse.',
          ko: '판매 준비가 된 상품만 «publicar(게시)»를 활성화하세요.',
        },
      ],
    },
    {
      id: 'codigo-madre',
      title: { es: 'Código madre y variantes (colores × tallas)', ko: '코드 마드레와 변형(색상×사이즈)' },
      capture: 'producto-02-codigo-madre',
      intro: {
        es: 'El código madre agrupa un modelo con todas sus combinaciones de color y talla. Cada combinación es una variante con su propio código y stock.',
        ko: '코드 마드레는 한 모델의 모든 색상×사이즈 조합을 묶는 부모 코드입니다. 각 조합은 고유 코드와 재고를 가진 변형이 됩니다.',
      },
      steps: [
        {
          es: 'En el alta de producto, marque la opción de código madre (códigos madres).',
          ko: '상품 등록 시 코드 마드레 옵션을 선택합니다.',
        },
        {
          es: 'Seleccione los colores y las tallas del modelo: el sistema genera la matriz de variantes.',
          ko: '모델의 색상과 사이즈를 선택하면 시스템이 변형 매트릭스를 생성합니다.',
        },
        {
          es: 'Cargue las cantidades por combinación en la tabla de variantes y guarde.',
          ko: '변형 표에 조합별 수량을 입력하고 저장합니다.',
        },
        {
          es: 'Para reponer stock de un modelo existente, seleccione su código madre: el formulario se completa solo y solo debe cargar las cantidades nuevas.',
          ko: '기존 모델 재입고 시 코드 마드레를 선택하면 폼이 자동으로 채워지고 새 수량만 입력하면 됩니다.',
        },
      ],
      tips: [
        {
          es: 'Si al crear artículos nuevos no aparecen tallas o colores nuevos, actualice la página para recargar los catálogos.',
          ko: '새로 만든 사이즈/색상이 목록에 안 보이면 페이지를 새로고침해 카탈로그를 다시 불러오세요.',
        },
      ],
    },
    {
      id: 'catalogos',
      title: { es: 'Catálogos: categorías, tallas, colores y más', ko: '카탈로그: 카테고리, 사이즈, 색상 등' },
      capture: 'producto-03-catalogos',
      intro: {
        es: 'Los catálogos (categorías, subcategorías, tallas, colores, temporadas, orígenes, proveedores) se administran una sola vez y se reutilizan en todos los productos.',
        ko: '카탈로그(카테고리, 하위 카테고리, 사이즈, 색상, 시즌, 원산지, 공급자)는 한 번 등록해 모든 상품에서 재사용합니다.',
      },
      steps: [
        {
          es: 'Entre a la configuración de productos para administrar cada catálogo.',
          ko: '상품 설정 메뉴에서 각 카탈로그를 관리합니다.',
        },
        {
          es: 'Agregue los valores nuevos (por ejemplo una talla o un color) antes de cargar los productos que los usan.',
          ko: '해당 값을 쓰는 상품을 등록하기 전에 새 값(예: 사이즈, 색상)을 먼저 추가하세요.',
        },
        {
          es: 'Evite duplicados con distinta escritura (por ejemplo «Rojo» y «ROJO»): dificultan los reportes.',
          ko: '표기만 다른 중복(예: «Rojo»와 «ROJO»)은 보고서를 어렵게 하므로 피하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'imagenes',
      title: { es: 'Imágenes del producto', ko: '상품 이미지' },
      capture: 'producto-04-imagenes',
      intro: {
        es: 'Cada producto puede tener imágenes que se muestran en el POS y en la tienda online.',
        ko: '상품마다 이미지를 등록해 POS와 온라인숍에 표시할 수 있습니다.',
      },
      steps: [
        {
          es: 'En la edición del producto, use la sección de imágenes para subir los archivos (JPG o PNG).',
          ko: '상품 편집 화면의 이미지 섹션에서 파일(JPG/PNG)을 업로드합니다.',
        },
        {
          es: 'La primera imagen es la principal: se usa como miniatura en listados y en la tienda.',
          ko: '첫 번째 이미지가 대표 이미지로 목록·온라인숍 썸네일에 사용됩니다.',
        },
      ],
      tips: [
        {
          es: 'Use fotos cuadradas y livianas (menos de 1 MB) para que las pantallas carguen rápido.',
          ko: '화면 로딩 속도를 위해 정사각형의 가벼운 사진(1MB 미만)을 권장합니다.',
        },
      ],
    },
    {
      id: 'precios',
      title: { es: 'Gestión de precios', ko: '가격 관리' },
      capture: 'producto-05-precios',
      intro: {
        es: 'El menú «Precios» permite ajustar precios de forma masiva: por porcentaje, por monto fijo, por categoría o por código madre (todas las variantes juntas).',
        ko: '«Precios» 메뉴에서 가격을 일괄 조정합니다: 퍼센트, 고정 금액, 카테고리별 또는 코드 마드레 단위(모든 변형 동시).',
      },
      steps: [
        {
          es: 'Entre al menú «Precios» y filtre los artículos a modificar (por categoría, proveedor o código).',
          ko: '«Precios» 메뉴에서 수정할 상품을 필터링합니다(카테고리, 공급자, 코드).',
        },
        {
          es: 'Elija el tipo de ajuste (porcentaje o monto) y el nivel de precio a modificar.',
          ko: '조정 방식(퍼센트/금액)과 수정할 가격 레벨을 선택합니다.',
        },
        {
          es: 'Con código madre, el cambio se aplica a todas las variantes del modelo en una sola operación.',
          ko: '코드 마드레 단위로는 모델의 모든 변형에 한 번에 적용됩니다.',
        },
        {
          es: 'Revise la vista previa de los precios nuevos antes de confirmar.',
          ko: '확정 전에 새 가격 미리보기를 확인하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'reingreso',
      title: { es: 'Reingreso y reposición de stock', ko: '재입고와 재고 보충' },
      capture: 'producto-06-reingreso',
      intro: {
        es: 'Cuando llega mercadería de un modelo ya cargado, no se crea un producto nuevo: se repone stock usando el código madre existente.',
        ko: '이미 등록된 모델의 상품이 입고되면 새 상품을 만들지 않고 기존 코드 마드레로 재고를 보충합니다.',
      },
      steps: [
        {
          es: 'En el alta/reposición, busque y seleccione el código madre del modelo.',
          ko: '등록/재입고 화면에서 모델의 코드 마드레를 검색해 선택합니다.',
        },
        {
          es: 'El formulario y la matriz de variantes se completan automáticamente con los datos existentes.',
          ko: '폼과 변형 매트릭스가 기존 데이터로 자동 완성됩니다.',
        },
        {
          es: 'Cargue solo las cantidades que ingresan por combinación y confirme.',
          ko: '입고되는 조합별 수량만 입력하고 확정합니다.',
        },
      ],
      tips: [],
    },
    {
      id: 'etiquetas',
      title: { es: 'Etiquetas de código de barras (Zebra)', ko: '바코드 라벨(Zebra)' },
      capture: 'producto-07-etiquetas',
      intro: {
        es: 'Las etiquetas se imprimen con el agente Zebra en tres formatos: 50×25 simple, 50×25 doble y 100×25 cartulina.',
        ko: '라벨은 Zebra 에이전트로 출력하며 3가지 형식이 있습니다: 50×25 단면, 50×25 양면, 100×25 카툴리나.',
      },
      steps: [
        {
          es: 'Desde el listado de productos, seleccione los artículos y use «Imprimir x ZPL».',
          ko: '상품 목록에서 상품을 선택하고 «Imprimir x ZPL»을 사용합니다.',
        },
        {
          es: 'Elija el formato de etiqueta y la cantidad por artículo.',
          ko: '라벨 형식과 상품별 출력 수량을 선택합니다.',
        },
        {
          es: 'Confirme la impresora Zebra de destino (agente en línea) y envíe la impresión.',
          ko: '대상 Zebra 프린터(온라인 에이전트)를 확인하고 출력을 보냅니다.',
        },
      ],
      tips: [
        {
          es: 'Si el agente figura fuera de línea, revise la PC donde está instalado (ícono de la app Zebra Agent).',
          ko: '에이전트가 오프라인이면 설치된 PC(Zebra Agent 앱 아이콘)를 확인하세요.',
        },
      ],
    },
    {
      id: 'importacion',
      title: { es: 'Importación masiva de códigos', ko: '코드 일괄 가져오기' },
      capture: 'producto-08-importacion',
      intro: {
        es: 'Para cargas grandes (por ejemplo migración inicial), VentaGO permite importar productos y códigos desde un archivo.',
        ko: '대량 등록(예: 초기 이관)은 파일에서 상품·코드를 가져오는 기능을 사용합니다.',
      },
      steps: [
        {
          es: 'Prepare el archivo con el formato indicado en la pantalla de importación (columnas de código, nombre, precios, stock).',
          ko: '가져오기 화면에 안내된 형식(코드, 이름, 가격, 재고 컬럼)으로 파일을 준비합니다.',
        },
        {
          es: 'Suba el archivo y revise la vista previa: el sistema marca filas con errores.',
          ko: '파일을 업로드하고 미리보기를 확인합니다. 오류 행은 시스템이 표시합니다.',
        },
        {
          es: 'Confirme la importación y verifique algunos artículos al azar.',
          ko: '가져오기를 확정하고 몇 개 상품을 무작위로 검증하세요.',
        },
      ],
      tips: [],
    },
    {
      id: 'tienda-online',
      title: { es: 'Publicación en la tienda online', ko: '온라인숍 게시' },
      capture: 'producto-09-tienda',
      intro: {
        es: 'Los artículos publicados aparecen en la tienda online de la marca. La publicación se controla por artículo.',
        ko: '게시된 상품은 브랜드 온라인숍에 노출됩니다. 게시 여부는 상품 단위로 관리합니다.',
      },
      steps: [
        {
          es: 'En la edición del producto, active la opción de publicación online.',
          ko: '상품 편집에서 온라인 게시 옵션을 활성화합니다.',
        },
        {
          es: 'Verifique que el artículo tenga imagen, precio y stock: son requisitos para mostrarse bien en la tienda.',
          ko: '이미지·가격·재고가 있는지 확인하세요. 온라인숍에 제대로 표시되기 위한 조건입니다.',
        },
        {
          es: 'Para retirar un artículo de la tienda, desactive la publicación (no hace falta borrarlo).',
          ko: '온라인숍에서 내리려면 게시만 비활성화하면 됩니다(삭제 불필요).',
        },
      ],
      tips: [],
    },
    {
      id: 'parametros',
      title: { es: 'Parámetros: prefijo de SKU', ko: '파라미터: SKU 접두어' },
      capture: 'producto-10-parametros',
      intro: {
        es: 'El prefijo de SKU define cómo empiezan los códigos generados automáticamente (por ejemplo «25» para la temporada 2025).',
        ko: 'SKU 접두어는 자동 생성 코드의 시작 부분을 정합니다(예: 2025 시즌은 «25»).',
      },
      steps: [
        {
          es: 'Entre a la configuración de productos → «Parámetros» y edite «Prefijo para SKU».',
          ko: '상품 설정 → «Parámetros»에서 «Prefijo para SKU»를 수정합니다.',
        },
        {
          es: 'Guarde y verifique creando un producto de prueba: el SKU nuevo debe empezar con el prefijo cargado.',
          ko: '저장 후 테스트 상품을 만들어 새 SKU가 입력한 접두어로 시작하는지 확인합니다.',
        },
      ],
      tips: [
        {
          es: 'Cambiar el prefijo no modifica los códigos ya generados; solo afecta a los productos nuevos.',
          ko: '접두어 변경은 기존 코드에는 영향이 없고 새로 만드는 상품에만 적용됩니다.',
        },
      ],
    },
  ],
};
