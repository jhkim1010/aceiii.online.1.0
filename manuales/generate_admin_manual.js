const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, HeadingLevel,
  BorderStyle, WidthType, ShadingType, PageNumber, PageBreak,
  TabStopType, TabStopPosition, TableOfContents,
} = require('docx');

// 색상 팔레트
const PRIMARY = "2E75B6";
const DARK = "1B4F72";
const LIGHT_BG = "E8F0FE";
const ACCENT = "27AE60";
const GRAY = "666666";
const LIGHT_GRAY = "F5F5F5";

// 테이블 테두리
const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };
const noBorder = { style: BorderStyle.NONE, size: 0 };
const noBorders = { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder };

// 번호 매기기 설정
const numberingConfig = [
  {
    reference: "bullets",
    levels: [{
      level: 0, format: LevelFormat.BULLET, text: "\u2022",
      alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: 720, hanging: 360 } } }
    }]
  },
  {
    reference: "bullets2",
    levels: [{
      level: 0, format: LevelFormat.BULLET, text: "\u25CB",
      alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: 1080, hanging: 360 } } }
    }]
  },
  {
    reference: "steps",
    levels: [{
      level: 0, format: LevelFormat.DECIMAL, text: "%1.",
      alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: 720, hanging: 360 } } }
    }]
  },
];

// 유틸리티 함수
function heading1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 400, after: 200 },
    children: [new TextRun({ text, bold: true, size: 32, font: "Arial", color: DARK })],
  });
}
function heading2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 300, after: 150 },
    children: [new TextRun({ text, bold: true, size: 26, font: "Arial", color: PRIMARY })],
  });
}
function heading3(text) {
  return new Paragraph({
    spacing: { before: 200, after: 100 },
    children: [new TextRun({ text, bold: true, size: 22, font: "Arial", color: DARK })],
  });
}
function para(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120 },
    ...opts,
    children: [new TextRun({ text, size: 21, font: "Arial", color: opts.color || "333333" })],
  });
}
function bullet(text) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({ text, size: 21, font: "Arial" })],
  });
}
function bullet2(text) {
  return new Paragraph({
    numbering: { reference: "bullets2", level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({ text, size: 21, font: "Arial", color: GRAY })],
  });
}
function step(text) {
  return new Paragraph({
    numbering: { reference: "steps", level: 0 },
    spacing: { after: 80 },
    children: [new TextRun({ text, size: 21, font: "Arial" })],
  });
}
function tipBox(label, text) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [9360],
    rows: [new TableRow({ children: [new TableCell({
      borders, width: { size: 9360, type: WidthType.DXA },
      shading: { fill: "FFF3CD", type: ShadingType.CLEAR },
      margins: { top: 100, bottom: 100, left: 200, right: 200 },
      children: [new Paragraph({ children: [
        new TextRun({ text: `\u26A0 ${label}: `, bold: true, size: 20, font: "Arial", color: "856404" }),
        new TextRun({ text, size: 20, font: "Arial", color: "856404" }),
      ]})],
    })]})],
  });
}
function infoBox(title, text) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [9360],
    rows: [new TableRow({ children: [new TableCell({
      borders, width: { size: 9360, type: WidthType.DXA },
      shading: { fill: LIGHT_BG, type: ShadingType.CLEAR },
      margins: { top: 100, bottom: 100, left: 200, right: 200 },
      children: [new Paragraph({ children: [
        new TextRun({ text: title + ": ", bold: true, size: 20, font: "Arial", color: DARK }),
        new TextRun({ text, size: 20, font: "Arial", color: PRIMARY }),
      ]})],
    })]})],
  });
}
function spacer() {
  return new Paragraph({ spacing: { after: 100 }, children: [] });
}

// 2열 정보 테이블
function infoTable(headerLeft, headerRight, rows) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [3500, 5860],
    rows: [
      new TableRow({ children: [
        new TableCell({ borders, width: { size: 3500, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: headerLeft, bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
        new TableCell({ borders, width: { size: 5860, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: headerRight, bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
      ]}),
      ...rows.map(([left, right], i) => new TableRow({ children: [
        new TableCell({ borders, width: { size: 3500, type: WidthType.DXA }, shading: { fill: i % 2 === 0 ? LIGHT_GRAY : "FFFFFF", type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: left, bold: true, size: 20, font: "Arial" })] })] }),
        new TableCell({ borders, width: { size: 5860, type: WidthType.DXA }, shading: { fill: i % 2 === 0 ? LIGHT_GRAY : "FFFFFF", type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: right, size: 20, font: "Arial" })] })] }),
      ]}))
    ]
  });
}

// ====================== 한국어 매뉴얼 콘텐츠 ======================
function buildKoreanContent() {
  return [
    // ===== 1장. 시스템 소개 =====
    heading1("1. 시스템 소개"),
    para("VentaGO는 다중 지점 소매점을 위한 통합 판매 관리 시스템(POS + ERP)입니다. 판매, 상품, 재고, 리포트, 관리 기능을 하나의 플랫폼에서 제공합니다."),
    spacer(),

    heading2("1.1 관리자 역할과 책임"),
    para("이 매뉴얼은 관리자(Admin, Superadmin, Gerente) 역할을 위한 가이드입니다."),
    spacer(),
    infoTable("역할", "설명", [
      ["Superadmin", "전체 시스템 접근 권한. 모든 매장과 기능을 관리"],
      ["Admin", "특정 매장의 전체 관리 권한"],
      ["Gerente (매니저)", "제한된 관리 권한. 일상 운영 관리"],
    ]),
    spacer(),

    heading2("1.2 시스템 주요 모듈"),
    bullet("판매 (Venta) \u2014 POS 인터페이스, 결제, 경비 관리"),
    bullet("상품 (Producto) \u2014 상품 등록, 가격, 재고 관리"),
    bullet("리포트 (Reportes) \u2014 판매, 재고, 경비 분석"),
    bullet("관리 (Admin) \u2014 매장, 사용자, 권한, 감사 로그"),
    spacer(),

    heading2("1.3 화면 구성"),
    para("시스템 인터페이스는 다음과 같이 구성됩니다:"),
    bullet("사이드바 (Sidebar) \u2014 좌측 메뉴. 현재 모듈에 따라 자동 변경"),
    bullet("상단바 (Top Bar) \u2014 금전 등록기 상태, 알림, 프로필 접근"),
    bullet("메인 영역 \u2014 선택한 기능의 콘텐츠 표시"),
    bullet("대시보드 \u2014 각 모듈의 핵심 지표 요약"),
    spacer(),
    tipBox("참고", "사이드바는 사용자 역할과 현재 위치에 따라 자동으로 메뉴가 변경됩니다."),
    spacer(),

    heading2("1.4 시스템 요구사항"),
    bullet("최신 웹 브라우저 (Chrome, Firefox, Edge, Safari)"),
    bullet("안정적인 인터넷 연결"),
    bullet("권장 해상도: 1280 x 720 이상"),
    spacer(),

    // ===== 2장. 로그인 및 계정 관리 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("2. 로그인 및 계정 관리"),
    spacer(),

    heading2("2.1 로그인"),
    step("브라우저에서 시스템 주소를 입력합니다."),
    step("이메일 또는 사용자명을 입력합니다."),
    step("비밀번호를 입력합니다."),
    step("\"Iniciar Sesi\u00F3n\" (로그인) 버튼을 클릭합니다."),
    spacer(),

    heading2("2.2 비밀번호 재설정"),
    step("로그인 화면에서 \"Olvidaste tu contrase\u00F1a\" (비밀번호 찾기)를 클릭합니다."),
    step("등록된 이메일 주소를 입력합니다."),
    step("이메일로 전송된 링크를 통해 새 비밀번호를 설정합니다."),
    spacer(),

    heading2("2.3 프로필 설정"),
    para("상단 우측의 프로필 아이콘을 클릭하여 개인 설정에 접근할 수 있습니다:"),
    bullet("개인 정보 수정 (이름, 이메일)"),
    bullet("비밀번호 변경"),
    bullet("다크모드 전환"),
    spacer(),

    // ===== 3장. 초기 설정 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("3. 초기 설정 (최초 1회)"),
    para("시스템을 사용하기 전에 아래 항목들을 순서대로 설정해야 합니다. 이 설정은 최초 1회만 수행하면 됩니다."),
    spacer(),
    infoBox("중요", "아래 순서를 지켜서 설정하세요. 각 단계는 이전 단계에 의존합니다."),
    spacer(),

    heading2("3.1 매장(Tienda) 정보 등록"),
    para("시스템의 최상위 단위인 매장을 설정합니다."),
    step("Admin > Tiendas (매장)으로 이동합니다."),
    step("매장 정보를 입력합니다: 이름, CUIT (세금 번호), 주소, 과세 유형"),
    step("매장을 활성화합니다."),
    spacer(),

    heading2("3.2 지점(Sucursal) 생성 및 관리"),
    para("매장 아래에 하나 이상의 지점을 생성합니다."),
    step("Admin > Sucursales (지점)으로 이동합니다."),
    step("\"Nueva Sucursal\" (새 지점)을 클릭합니다."),
    step("지점 이름, 주소, 담당자를 입력합니다."),
    step("메인 지점 여부를 설정합니다."),
    step("저장합니다."),
    spacer(),
    tipBox("참고", "지점은 상품 재고, 금전 등록기, 사용자가 배정되는 기본 단위입니다."),
    spacer(),

    heading2("3.3 결제 수단(M\u00E9todo de Pago) 설정"),
    para("판매 시 사용할 결제 수단을 등록합니다."),
    step("Configuraci\u00F3n (설정) > Ventas (판매)로 이동합니다."),
    step("M\u00E9todos de Pago (결제 수단) 탭을 선택합니다."),
    step("결제 수단을 추가합니다 (현금, 카드, 이체, 수표 등)."),
    step("각 결제 수단의 유형을 설정합니다 (소매/도매/전체)."),
    spacer(),

    heading2("3.4 금전 등록기(Caja Registradora) 등록"),
    para("각 지점에 금전 등록기를 등록합니다."),
    step("Admin > Sucursales (지점)에서 해당 지점을 선택합니다."),
    step("Cajas Registradoras (금전 등록기) 섹션에서 새 등록기를 추가합니다."),
    step("등록기 이름을 입력합니다."),
    step("저장합니다."),
    spacer(),

    heading2("3.5 터미널(Terminal) 설정"),
    para("금전 등록기에 결제 터미널을 연결합니다."),
    step("등록기 설정에서 Terminal (터미널) 추가를 클릭합니다."),
    step("터미널 이름과 정보를 입력합니다."),
    step("저장합니다."),
    spacer(),
    infoBox("중요", "금전 등록기와 터미널이 없으면 판매를 진행할 수 없습니다."),
    spacer(),

    heading2("3.6 경비 카테고리(Categor\u00EDa de Gastos) 설정"),
    para("경비를 분류하기 위한 카테고리를 설정합니다."),
    step("Configuraci\u00F3n (설정) > Ventas (판매)로 이동합니다."),
    step("Categor\u00EDas de Gastos (경비 카테고리) 탭을 선택합니다."),
    step("카테고리를 추가합니다 (운영비, 임대료, 급여, 기타 등)."),
    step("필요한 경우 하위 카테고리를 생성합니다."),
    spacer(),

    // ===== 4장. 사용자 및 권한 관리 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("4. 사용자 및 권한 관리"),
    spacer(),

    heading2("4.1 사용자(Usuario) 생성"),
    step("Admin > Usuarios (사용자)로 이동합니다."),
    step("\"Nuevo Usuario\" (새 사용자)를 클릭합니다."),
    step("이름, 이메일, 사용자명을 입력합니다."),
    step("소속 매장을 선택합니다."),
    step("초기 비밀번호를 설정합니다."),
    step("저장합니다."),
    spacer(),

    heading2("4.2 역할(Role) 생성 및 할당"),
    para("역할은 사용자에게 부여할 권한 그룹입니다."),
    spacer(),
    heading3("기본 역할"),
    infoTable("역할", "접근 범위", [
      ["Superadmin", "모든 앱, 모든 모듈, 모든 매장"],
      ["Admin", "소속 매장의 모든 앱과 모듈"],
      ["Gerente", "소속 매장의 제한된 관리 기능"],
      ["Vendedor", "판매 모듈만 접근 가능"],
    ]),
    spacer(),

    heading3("커스텀 역할 생성"),
    step("Admin > Permisos (권한)으로 이동합니다."),
    step("\"Nuevo Rol\" (새 역할)을 클릭합니다."),
    step("역할 이름과 설명을 입력합니다."),
    step("해당 역할에 접근 가능한 앱, 모듈, 기능을 선택합니다."),
    step("저장합니다."),
    spacer(),

    heading2("4.3 권한(Permiso) 설정"),
    para("VentaGO의 권한 시스템은 3단계 계층으로 구성됩니다:"),
    spacer(),
    infoTable("계층", "설명", [
      ["앱 (App)", "최상위 모듈 단위 (판매, 상품, 관리, 리포트)"],
      ["모듈 (Module)", "앱 내의 기능 그룹 (예: 새 판매, 상품 목록)"],
      ["기능 (Function)", "개별 동작 (예: 생성, 수정, 삭제, 조회)"],
    ]),
    spacer(),
    para("각 역할에 대해 앱 > 모듈 > 기능 단위로 세밀한 권한 부여가 가능합니다."),
    spacer(),

    heading2("4.4 사용자 상태 관리"),
    para("사용자 상태를 변경하여 접근을 제어합니다:"),
    spacer(),
    infoTable("상태", "설명", [
      ["Active (활성)", "정상 접근 가능"],
      ["Inactive (비활성)", "접근 불가. 필요 시 재활성화"],
      ["Trial (체험)", "제한된 기간 동안 접근"],
      ["Suspended (정지)", "일시적 접근 차단"],
    ]),
    spacer(),

    heading2("4.5 판매원(Vendedor) 등록"),
    para("판매원은 시스템 로그인 사용자와 별개로, 판매 시 기록을 위한 인물입니다."),
    step("Admin 또는 판매 설정에서 Vendedores (판매원)으로 이동합니다."),
    step("이름과 정보를 입력합니다."),
    step("저장합니다."),
    spacer(),
    tipBox("참고", "판매원은 로그인 계정이 아닌, 매출 귀속을 위한 기록입니다. 하나의 로그인 사용자가 여러 판매원의 매출을 등록할 수 있습니다."),
    spacer(),

    // ===== 5장. 상품 관리 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("5. 상품 관리 (Producto)"),
    para("판매를 시작하기 위해서는 먼저 상품이 등록되어 있어야 합니다."),
    spacer(),

    heading2("5.1 카테고리 / 서브카테고리 생성"),
    step("Configuraci\u00F3n Productos (상품 설정)으로 이동합니다."),
    step("\"Categor\u00EDas\" (카테고리) 탭에서 주요 분류를 생성합니다 (예: 의류, 신발, 액세서리)."),
    step("\"Subcategor\u00EDas\" (서브카테고리) 탭에서 세부 분류를 생성합니다 (예: 티셔츠, 바지, 운동화)."),
    spacer(),

    heading2("5.2 상품 속성 설정"),
    para("상품에 부여할 속성들을 미리 등록합니다:"),
    bullet("색상 (Colores) \u2014 사용할 색상 목록 등록"),
    bullet("사이즈 (Talles) \u2014 사용할 사이즈 목록 등록"),
    bullet("시즌 (Temporadas) \u2014 봄/여름, 가을/겨울 등 시즌 분류"),
    bullet("원산지 (Origen) \u2014 원산지 국가 등록"),
    spacer(),

    heading2("5.3 공급업체(Proveedor) 등록"),
    step("Configuraci\u00F3n Productos > Proveedores (공급업체)로 이동합니다."),
    step("업체 이름, 연락처, 주소를 입력합니다."),
    step("저장합니다."),
    spacer(),

    heading2("5.4 상품(Producto) 등록"),
    spacer(),
    heading3("기본 상품 등록"),
    step("Productos (상품)으로 이동합니다."),
    step("\"Nuevo Producto\" (새 상품)를 클릭합니다."),
    step("이름, SKU, 바코드를 입력합니다."),
    step("카테고리, 서브카테고리를 선택합니다."),
    step("공급업체를 선택합니다 (선택사항)."),
    step("가격을 설정합니다."),
    step("초기 재고를 입력합니다."),
    step("저장합니다."),
    spacer(),

    heading3("변형 상품(Variante) 관리"),
    para("하나의 상품에 색상, 사이즈 조합별 변형을 만들 수 있습니다."),
    bullet("부모 상품 \u2014 변형의 기본이 되는 상품"),
    bullet("자식 상품 \u2014 각 색상/사이즈 조합의 개별 상품"),
    para("변형 상품은 각각 독립된 재고와 가격을 가집니다."),
    spacer(),

    heading3("일반 상품(Gen\u00E9rico) 설정"),
    para("코드 없이 빠르게 판매할 때 사용하는 일반 상품입니다. 판매 시 \"빠른 판매\" 기능으로 이름과 가격을 직접 입력합니다."),
    spacer(),

    heading2("5.5 지점별 상품 배정"),
    para("상품을 특정 지점에 배정하여 해당 지점에서만 판매 가능하게 합니다."),
    step("상품 상세 화면에서 Sucursales (지점) 탭을 선택합니다."),
    step("배정할 지점을 선택합니다."),
    step("저장합니다."),
    spacer(),

    heading2("5.6 재고(Stock) 입력 및 관리"),
    para("지점별로 재고를 관리합니다."),
    bullet("상품 상세 화면에서 각 지점의 현재 재고를 확인"),
    bullet("재고 수량을 직접 수정 가능"),
    bullet("판매 시 자동으로 재고가 차감됨"),
    spacer(),
    tipBox("참고", "재고가 0인 상품도 판매 화면에 표시됩니다. 재고 부족 경고를 위해 최소 재고 수준을 설정하세요."),
    spacer(),

    heading2("5.7 가격 유형(Tipo de Precio) 및 가격 설정"),
    para("다양한 가격 체계를 설정할 수 있습니다:"),
    bullet("가격 유형 생성 (소매, 도매, 특별가 등)"),
    bullet("상품별로 각 가격 유형에 대한 가격 설정"),
    bullet("대량 가격 조정 (비율로 일괄 변경)"),
    bullet("엑셀 가져오기/내보내기를 통한 대량 관리"),
    spacer(),

    heading2("5.8 할인(Descuento) 설정"),
    para("세 가지 단위의 할인을 설정할 수 있습니다:"),
    spacer(),
    infoTable("할인 유형", "설명", [
      ["상품별 할인", "특정 상품에 직접 할인율/할인액 적용"],
      ["서브카테고리별 할인", "서브카테고리 전체에 할인 적용"],
      ["결제수단별 할인", "특정 결제 수단 사용 시 추가 할인"],
    ]),
    spacer(),
    para("각 할인은 적용 기간(시작일~종료일)을 설정할 수 있습니다."),
    spacer(),

    heading2("5.9 상품 설정"),
    para("Configuraci\u00F3n Productos (상품 설정)에서 관리하는 항목:"),
    bullet("카테고리 / 서브카테고리 관리"),
    bullet("색상, 사이즈, 시즌, 원산지 관리"),
    bullet("공급업체 관리"),
    bullet("자동 코드 생성 자릿수 설정"),
    spacer(),

    // ===== 6장. 금고 관리 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("6. 금고 관리 (Caja Fuerte)"),
    para("금고(Caja Fuerte)는 지점 단위의 현금 보관소입니다. 금전 등록기의 현금이 금고로 이동합니다."),
    spacer(),

    heading2("6.1 지점별 금고 개요"),
    para("각 지점에는 하나의 금고가 자동으로 생성됩니다."),
    bullet("현재 잔고 실시간 표시"),
    bullet("입출금 이력 관리"),
    bullet("금전 등록기 마감 시 자동 입금"),
    spacer(),

    heading2("6.2 입금(Ingreso) / 출금(Retiro)"),
    spacer(),
    heading3("입금"),
    step("Caja Fuerte (금고) 화면으로 이동합니다."),
    step("\"Ingreso\" (입금)를 클릭합니다."),
    step("금액과 사유를 입력합니다."),
    step("확인합니다."),
    spacer(),

    heading3("출금"),
    step("Caja Fuerte (금고) 화면으로 이동합니다."),
    step("\"Retiro\" (출금)를 클릭합니다."),
    step("금액과 사유를 입력합니다."),
    step("확인합니다."),
    spacer(),

    heading2("6.3 금전 등록기 \u2192 금고 연동"),
    para("금전 등록기 마감(Cierre de Caja) 시 잔액이 자동으로 금고에 입금됩니다."),
    bullet("자동 마감 (auto_cierre) \u2014 시스템이 자동으로 처리"),
    bullet("수동 마감 (manual) \u2014 관리자가 직접 마감"),
    bullet("관리자 출금 (admin_retiro) \u2014 관리자가 금고에서 직접 출금"),
    spacer(),

    heading2("6.4 잔고 조회 및 이력"),
    para("금고 화면에서 다음을 확인할 수 있습니다:"),
    bullet("현재 잔고"),
    bullet("날짜별 입출금 이력"),
    bullet("출처별 분류 (자동 마감 / 수동 / 관리자)"),
    bullet("담당자 정보"),
    spacer(),

    // ===== 7장. 판매 관리 (관리자 관점) =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("7. 판매 관리 (관리자 관점)"),
    para("관리자는 판매 현황을 모니터링하고 설정을 관리합니다."),
    spacer(),

    heading2("7.1 판매 현황 모니터링"),
    para("Ventas (판매) 목록에서 모든 판매를 조회할 수 있습니다:"),
    bullet("날짜, 상태, 고객별 필터링"),
    bullet("판매 상세 정보 확인 (상품, 결제, 할인)"),
    bullet("판매 상태별 분류 (초안, 송장 발행, 결제 대기, 결제 완료)"),
    spacer(),

    heading2("7.2 판매 상태 관리"),
    para("판매의 생명주기는 다음과 같습니다:"),
    spacer(),
    infoTable("상태", "설명", [
      ["Draft (초안)", "아직 확정되지 않은 판매"],
      ["Invoiced (송장 발행)", "송장이 발행된 상태"],
      ["Pending Payment (결제 대기)", "결제를 기다리는 상태"],
      ["Paid (결제 완료)", "결제가 완료된 최종 상태"],
    ]),
    spacer(),

    heading2("7.3 경비(Gastos) 관리"),
    para("등록된 경비를 관리합니다:"),
    bullet("경비 목록 조회 및 검색"),
    bullet("경비 상세 확인 (금액, 카테고리, 담당자, 날짜)"),
    bullet("경비 수정 및 삭제"),
    spacer(),

    heading2("7.4 금전 등록기 상태 확인"),
    para("Control de Caja (금전 등록기 관리)에서 모든 등록기를 모니터링합니다:"),
    bullet("등록기별 열림/닫힘 상태"),
    bullet("현재 잔고"),
    bullet("오늘의 거래 내역"),
    bullet("등록기 열기 및 마감"),
    spacer(),

    heading2("7.5 판매 설정"),
    para("Configuraci\u00F3n Ventas (판매 설정)에서 관리하는 항목:"),
    bullet("결제 수단 생성 및 관리"),
    bullet("할인 규칙 설정"),
    bullet("추가 요금(Recargo) 규칙 설정"),
    bullet("경비 카테고리 관리"),
    spacer(),

    // ===== 8장. 리포트 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("8. 리포트 (Reportes)"),
    para("데이터 기반의 경영 의사결정을 위한 다양한 리포트를 제공합니다."),
    spacer(),

    heading2("8.1 대시보드 개요"),
    para("리포트 대시보드에서 핵심 지표를 한눈에 확인합니다:"),
    bullet("일/주/월 매출 요약"),
    bullet("전일 대비 변동"),
    bullet("주요 경고 및 알림"),
    spacer(),

    heading2("8.2 판매 리포트"),
    para("다양한 관점에서 판매를 분석합니다:"),
    bullet("기간별 \u2014 일별, 주별, 월별 매출 추이"),
    bullet("지점별 \u2014 지점 간 실적 비교"),
    bullet("판매원별 \u2014 판매원 성과 분석"),
    bullet("상품별 \u2014 인기 상품 및 판매 추이"),
    bullet("엑셀 내보내기 지원"),
    spacer(),

    heading2("8.3 경비 리포트"),
    bullet("카테고리별 경비 분석"),
    bullet("기간별 경비 추이"),
    bullet("지점별 경비 비교"),
    spacer(),

    heading2("8.4 재고 리포트"),
    bullet("지점별 재고 현황"),
    bullet("재고 부족 / 품절 상품 목록"),
    bullet("재고 이동 이력"),
    bullet("엑셀 내보내기 지원"),
    spacer(),

    heading2("8.5 계정/정산 리포트"),
    bullet("결제 수단별 매출 요약"),
    bullet("미수금 현황"),
    bullet("일별 정산 내역"),
    spacer(),

    heading2("8.6 지점별 매출 분석"),
    para("Admin > Ventas (매출)에서 지점별 매출을 상세 분석합니다:"),
    bullet("지점별 일일/월별 매출"),
    bullet("지점 간 성과 비교"),
    bullet("상세 판매 내역 드릴다운"),
    spacer(),

    // ===== 9장. 감사 및 모니터링 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("9. 감사 및 모니터링"),
    spacer(),

    heading2("9.1 감사 로그(Audit Log) 조회"),
    para("Admin > Auditor\u00EDa (감사)에서 시스템의 모든 변경 사항을 추적합니다:"),
    bullet("사용자별 활동 이력"),
    bullet("날짜 및 액션 유형별 필터링"),
    bullet("변경 전/후 데이터 확인"),
    bullet("특정 이벤트 검색"),
    spacer(),
    infoBox("참고", "감사 로그는 Superadmin만 접근 가능합니다."),
    spacer(),

    heading2("9.2 금전 등록기 상태 모니터링"),
    para("실시간으로 모든 금전 등록기의 상태를 확인합니다:"),
    bullet("열린 등록기 목록 및 담당자"),
    bullet("등록기별 현재 잔고"),
    bullet("비정상적인 금액 변동 감지"),
    spacer(),

    heading2("9.3 사용자 활동 추적"),
    bullet("마지막 로그인 시간 확인"),
    bullet("사용자별 판매 건수 확인"),
    bullet("비활성 사용자 식별"),
    spacer(),

    // ===== 부록 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("부록"),
    spacer(),

    heading2("A. 용어 사전 (한국어-스페인어 대조)"),
    spacer(),
    infoTable("한국어", "스페인어 (Espa\u00F1ol)", [
      ["매장", "Tienda"],
      ["지점", "Sucursal"],
      ["상품", "Producto"],
      ["판매", "Venta"],
      ["새 판매", "Nueva Venta"],
      ["금전 등록기", "Caja Registradora"],
      ["금고", "Caja Fuerte"],
      ["경비", "Gastos"],
      ["결제 수단", "M\u00E9todo de Pago"],
      ["할인", "Descuento"],
      ["추가 요금", "Recargo"],
      ["재고", "Stock"],
      ["가격", "Precio"],
      ["고객", "Cliente"],
      ["판매원", "Vendedor"],
      ["카테고리", "Categor\u00EDa"],
      ["서브카테고리", "Subcategor\u00EDa"],
      ["공급업체", "Proveedor"],
      ["리포트", "Reportes"],
      ["사용자", "Usuario"],
      ["역할", "Rol"],
      ["권한", "Permiso"],
      ["감사 로그", "Auditor\u00EDa"],
      ["대시보드", "Dashboard"],
      ["설정", "Configuraci\u00F3n"],
    ]),
    spacer(),

    heading2("B. 오류 메시지 및 해결 방법"),
    spacer(),
    heading3("\"No existen cajas asociadas a esta sucursal\""),
    para("해결: Admin > Sucursales에서 해당 지점에 금전 등록기와 터미널을 추가하세요."),
    spacer(),
    heading3("판매(Pagar) 버튼이 비활성화됨"),
    para("해결: 상단바에서 \"Iniciar Caja\" (금전 등록기 시작)를 클릭하여 등록기를 열어야 합니다."),
    spacer(),
    heading3("상품 검색 결과 없음"),
    para("해결: (1) 상품이 현재 지점에 배정되어 있는지 확인, (2) 상품 상태가 Active인지 확인"),
    spacer(),
    heading3("권한 없음 (Unauthorized)"),
    para("해결: 사용자의 역할에 해당 기능의 권한이 부여되어 있는지 Admin > Permisos에서 확인하세요."),
    spacer(),

    heading2("C. 자주 묻는 질문 (FAQ)"),
    spacer(),
    heading3("시스템이 느린 경우"),
    para("인터넷 연결을 확인하세요. 문제가 지속되면 브라우저 캐시를 삭제하거나 기술 지원팀에 문의하세요."),
    spacer(),
    heading3("데이터를 엑셀로 내보내려면?"),
    para("리포트 섹션에서 필터링 후 Excel 내보내기 버튼을 클릭합니다."),
    spacer(),
    heading3("비밀번호를 잊어버린 경우"),
    para("로그인 화면의 \"Olvidaste tu contrase\u00F1a\" 링크를 사용하거나, Superadmin에게 비밀번호 재설정을 요청하세요."),
    spacer(),

    // 하단 서명
    spacer(),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 400 },
      border: { top: { style: BorderStyle.SINGLE, size: 4, color: PRIMARY, space: 20 } },
      children: [new TextRun({ text: "VentaGO \u2014 \uD1B5\uD569 \uD310\uB9E4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C", size: 20, font: "Arial", color: GRAY, italics: true })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "\u00A9 2026 \u2014 All rights reserved", size: 18, font: "Arial", color: GRAY })],
    }),
  ];
}

// ====================== 스페인어 매뉴얼 콘텐츠 ======================
function buildSpanishContent() {
  return [
    // ===== 1. INTRODUCCI\u00D3N =====
    heading1("1. Introducci\u00F3n al Sistema"),
    para("VentaGO es un sistema integral de gesti\u00F3n de ventas (POS + ERP) dise\u00F1ado para tiendas minoristas con m\u00FAltiples sucursales. Ofrece funcionalidades de ventas, productos, inventario, reportes y administraci\u00F3n en una sola plataforma."),
    spacer(),

    heading2("1.1 Rol y responsabilidades del Administrador"),
    para("Este manual est\u00E1 dirigido a los roles de administraci\u00F3n (Admin, Superadmin, Gerente)."),
    spacer(),
    infoTable("Rol", "Descripci\u00F3n", [
      ["Superadmin", "Acceso total al sistema. Gestiona todas las tiendas y funciones"],
      ["Admin", "Gesti\u00F3n completa de una tienda espec\u00EDfica"],
      ["Gerente", "Acceso administrativo limitado. Gesti\u00F3n operativa diaria"],
    ]),
    spacer(),

    heading2("1.2 M\u00F3dulos principales"),
    bullet("Ventas (Venta) \u2014 Interfaz POS, pagos, gesti\u00F3n de gastos"),
    bullet("Productos (Producto) \u2014 Cat\u00E1logo, precios, inventario"),
    bullet("Reportes \u2014 An\u00E1lisis de ventas, stock, gastos"),
    bullet("Administraci\u00F3n (Admin) \u2014 Tiendas, usuarios, permisos, auditor\u00EDa"),
    spacer(),

    heading2("1.3 Estructura de la interfaz"),
    para("La interfaz del sistema se compone de:"),
    bullet("Barra lateral (Sidebar) \u2014 Men\u00FA izquierdo. Cambia autom\u00E1ticamente seg\u00FAn el m\u00F3dulo"),
    bullet("Barra superior (Top Bar) \u2014 Estado de caja, notificaciones, perfil"),
    bullet("\u00C1rea principal \u2014 Contenido de la funci\u00F3n seleccionada"),
    bullet("Dashboard \u2014 Resumen de indicadores clave por m\u00F3dulo"),
    spacer(),
    tipBox("Nota", "La barra lateral cambia autom\u00E1ticamente seg\u00FAn el rol del usuario y la ubicaci\u00F3n actual."),
    spacer(),

    heading2("1.4 Requisitos del sistema"),
    bullet("Navegador web moderno (Chrome, Firefox, Edge, Safari)"),
    bullet("Conexi\u00F3n a Internet estable"),
    bullet("Resoluci\u00F3n recomendada: 1280 x 720 o superior"),
    spacer(),

    // ===== 2. INICIO DE SESI\u00D3N =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("2. Inicio de Sesi\u00F3n y Gesti\u00F3n de Cuenta"),
    spacer(),

    heading2("2.1 Iniciar sesi\u00F3n"),
    step("Abra su navegador e ingrese la direcci\u00F3n del sistema."),
    step("Ingrese su correo electr\u00F3nico o nombre de usuario."),
    step("Ingrese su contrase\u00F1a."),
    step("Haga clic en \"Iniciar Sesi\u00F3n\"."),
    spacer(),

    heading2("2.2 Restablecer contrase\u00F1a"),
    step("En la pantalla de login, haga clic en \"Olvidaste tu contrase\u00F1a\"."),
    step("Ingrese su direcci\u00F3n de correo electr\u00F3nico registrada."),
    step("Siga el enlace enviado por correo para establecer una nueva contrase\u00F1a."),
    spacer(),

    heading2("2.3 Configuraci\u00F3n de perfil"),
    para("Acceda a su perfil haciendo clic en el icono de usuario en la esquina superior derecha:"),
    bullet("Modificar informaci\u00F3n personal (nombre, email)"),
    bullet("Cambiar contrase\u00F1a"),
    bullet("Alternar modo oscuro"),
    spacer(),

    // ===== 3. CONFIGURACI\u00D3N INICIAL =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("3. Configuraci\u00F3n Inicial (Primera vez)"),
    para("Antes de comenzar a usar el sistema, debe completar los siguientes pasos en orden. Esta configuraci\u00F3n se realiza solo una vez."),
    spacer(),
    infoBox("Importante", "Siga el orden indicado. Cada paso depende del anterior."),
    spacer(),

    heading2("3.1 Registro de Tienda"),
    para("La tienda es la unidad principal del sistema."),
    step("Vaya a Admin > Tiendas."),
    step("Ingrese la informaci\u00F3n de la tienda: nombre, CUIT, direcci\u00F3n, tipo de contribuyente."),
    step("Active la tienda."),
    spacer(),

    heading2("3.2 Creaci\u00F3n de Sucursales"),
    para("Cree una o m\u00E1s sucursales dentro de la tienda."),
    step("Vaya a Admin > Sucursales."),
    step("Haga clic en \"Nueva Sucursal\"."),
    step("Ingrese nombre, direcci\u00F3n y responsable de la sucursal."),
    step("Defina si es la sucursal principal."),
    step("Guarde."),
    spacer(),
    tipBox("Nota", "La sucursal es la unidad base donde se asignan productos, cajas registradoras y usuarios."),
    spacer(),

    heading2("3.3 Configuraci\u00F3n de M\u00E9todos de Pago"),
    para("Registre los m\u00E9todos de pago que se usar\u00E1n en las ventas."),
    step("Vaya a Configuraci\u00F3n > Ventas."),
    step("Seleccione la pesta\u00F1a M\u00E9todos de Pago."),
    step("Agregue m\u00E9todos de pago (efectivo, tarjeta, transferencia, cheque, etc.)."),
    step("Defina el tipo de cada m\u00E9todo (minorista/mayorista/ambos)."),
    spacer(),

    heading2("3.4 Registro de Cajas Registradoras"),
    para("Registre cajas registradoras en cada sucursal."),
    step("En Admin > Sucursales, seleccione la sucursal correspondiente."),
    step("En la secci\u00F3n Cajas Registradoras, agregue una nueva caja."),
    step("Ingrese el nombre de la caja."),
    step("Guarde."),
    spacer(),

    heading2("3.5 Configuraci\u00F3n de Terminales"),
    para("Asocie terminales de pago a las cajas registradoras."),
    step("En la configuraci\u00F3n de la caja, haga clic en agregar Terminal."),
    step("Ingrese el nombre e informaci\u00F3n del terminal."),
    step("Guarde."),
    spacer(),
    infoBox("Importante", "Sin caja registradora y terminal configurados, no ser\u00E1 posible realizar ventas."),
    spacer(),

    heading2("3.6 Configuraci\u00F3n de Categor\u00EDas de Gastos"),
    para("Configure las categor\u00EDas para clasificar los gastos del negocio."),
    step("Vaya a Configuraci\u00F3n > Ventas."),
    step("Seleccione la pesta\u00F1a Categor\u00EDas de Gastos."),
    step("Agregue categor\u00EDas (operativos, alquiler, sueldos, otros, etc.)."),
    step("Cree subcategor\u00EDas si es necesario."),
    spacer(),

    // ===== 4. USUARIOS Y PERMISOS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("4. Gesti\u00F3n de Usuarios y Permisos"),
    spacer(),

    heading2("4.1 Crear Usuario"),
    step("Vaya a Admin > Usuarios."),
    step("Haga clic en \"Nuevo Usuario\"."),
    step("Ingrese nombre, email y nombre de usuario."),
    step("Seleccione la tienda a la que pertenece."),
    step("Establezca la contrase\u00F1a inicial."),
    step("Guarde."),
    spacer(),

    heading2("4.2 Roles: Creaci\u00F3n y Asignaci\u00F3n"),
    para("Los roles definen qu\u00E9 funciones puede usar cada usuario."),
    spacer(),
    heading3("Roles predefinidos"),
    infoTable("Rol", "Alcance de acceso", [
      ["Superadmin", "Todas las apps, m\u00F3dulos y tiendas"],
      ["Admin", "Todas las apps y m\u00F3dulos de su tienda"],
      ["Gerente", "Funciones administrativas limitadas de su tienda"],
      ["Vendedor", "Solo m\u00F3dulo de ventas"],
    ]),
    spacer(),

    heading3("Crear un rol personalizado"),
    step("Vaya a Admin > Permisos."),
    step("Haga clic en \"Nuevo Rol\"."),
    step("Ingrese nombre y descripci\u00F3n del rol."),
    step("Seleccione las apps, m\u00F3dulos y funciones accesibles."),
    step("Guarde."),
    spacer(),

    heading2("4.3 Sistema de Permisos"),
    para("El sistema de permisos de VentaGO tiene una jerarqu\u00EDa de 3 niveles:"),
    spacer(),
    infoTable("Nivel", "Descripci\u00F3n", [
      ["App", "Unidad de m\u00F3dulo principal (Ventas, Productos, Admin, Reportes)"],
      ["M\u00F3dulo", "Grupo de funciones dentro de una app (ej: Nueva Venta, Lista de Productos)"],
      ["Funci\u00F3n", "Acci\u00F3n individual (ej: crear, editar, eliminar, ver)"],
    ]),
    spacer(),
    para("Puede otorgar permisos granulares a cada rol a nivel de App > M\u00F3dulo > Funci\u00F3n."),
    spacer(),

    heading2("4.4 Gesti\u00F3n de Estado de Usuarios"),
    para("Controle el acceso modificando el estado del usuario:"),
    spacer(),
    infoTable("Estado", "Descripci\u00F3n", [
      ["Active (Activo)", "Acceso normal al sistema"],
      ["Inactive (Inactivo)", "Sin acceso. Se puede reactivar"],
      ["Trial (Prueba)", "Acceso por tiempo limitado"],
      ["Suspended (Suspendido)", "Bloqueo temporal de acceso"],
    ]),
    spacer(),

    heading2("4.5 Registro de Vendedores"),
    para("Los vendedores son personas registradas para atribuir ventas, independientes de las cuentas de usuario del sistema."),
    step("Vaya a la configuraci\u00F3n de vendedores en Admin o Ventas."),
    step("Ingrese nombre e informaci\u00F3n del vendedor."),
    step("Guarde."),
    spacer(),
    tipBox("Nota", "Un vendedor no es una cuenta de login. Es un registro para atribuir ventas. Un mismo usuario puede registrar ventas de diferentes vendedores."),
    spacer(),

    // ===== 5. PRODUCTOS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("5. Gesti\u00F3n de Productos"),
    para("Para comenzar a vender, primero debe tener productos registrados en el sistema."),
    spacer(),

    heading2("5.1 Crear Categor\u00EDas y Subcategor\u00EDas"),
    step("Vaya a Configuraci\u00F3n de Productos."),
    step("En la pesta\u00F1a \"Categor\u00EDas\", cree las clasificaciones principales (ej: Ropa, Calzado, Accesorios)."),
    step("En \"Subcategor\u00EDas\", cree clasificaciones m\u00E1s espec\u00EDficas (ej: Remeras, Pantalones, Zapatillas)."),
    spacer(),

    heading2("5.2 Configurar Atributos de Producto"),
    para("Registre los atributos que se asignar\u00E1n a los productos:"),
    bullet("Colores \u2014 Lista de colores disponibles"),
    bullet("Talles \u2014 Lista de talles disponibles"),
    bullet("Temporadas \u2014 Clasificaci\u00F3n estacional (Primavera/Verano, Oto\u00F1o/Invierno)"),
    bullet("Origen \u2014 Pa\u00EDs de origen"),
    spacer(),

    heading2("5.3 Registrar Proveedores"),
    step("Vaya a Configuraci\u00F3n de Productos > Proveedores."),
    step("Ingrese nombre, contacto y direcci\u00F3n del proveedor."),
    step("Guarde."),
    spacer(),

    heading2("5.4 Registrar Productos"),
    spacer(),
    heading3("Producto b\u00E1sico"),
    step("Vaya a Productos."),
    step("Haga clic en \"Nuevo Producto\"."),
    step("Ingrese nombre, SKU y c\u00F3digo de barras."),
    step("Seleccione categor\u00EDa y subcategor\u00EDa."),
    step("Asigne un proveedor (opcional)."),
    step("Configure los precios."),
    step("Ingrese el stock inicial."),
    step("Guarde."),
    spacer(),

    heading3("Variantes de producto"),
    para("Puede crear variantes de un producto por combinaci\u00F3n de color y talle."),
    bullet("Producto padre \u2014 El producto base de las variantes"),
    bullet("Productos hijos \u2014 Cada combinaci\u00F3n color/talle como producto individual"),
    para("Cada variante tiene su propio stock y precio independiente."),
    spacer(),

    heading3("Producto gen\u00E9rico"),
    para("Producto especial para ventas r\u00E1pidas sin c\u00F3digo. En la pantalla de venta se usa la funci\u00F3n \"Venta R\u00E1pida\" para ingresar nombre y precio manualmente."),
    spacer(),

    heading2("5.5 Asignaci\u00F3n de Productos por Sucursal"),
    para("Asigne productos a sucursales espec\u00EDficas para que solo est\u00E9n disponibles en esas ubicaciones."),
    step("En la vista detalle del producto, seleccione la pesta\u00F1a Sucursales."),
    step("Seleccione las sucursales donde estar\u00E1 disponible."),
    step("Guarde."),
    spacer(),

    heading2("5.6 Gesti\u00F3n de Stock"),
    para("Administre el inventario por sucursal."),
    bullet("Consulte el stock actual de cada sucursal en la vista detalle del producto"),
    bullet("Modifique cantidades de stock directamente"),
    bullet("El stock se descuenta autom\u00E1ticamente al realizar ventas"),
    spacer(),
    tipBox("Nota", "Los productos con stock 0 siguen apareciendo en la pantalla de ventas. Configure un nivel m\u00EDnimo de stock para recibir alertas."),
    spacer(),

    heading2("5.7 Tipos de Precio y Configuraci\u00F3n"),
    para("Configure m\u00FAltiples esquemas de precios:"),
    bullet("Crear tipos de precio (Minorista, Mayorista, Especial, etc.)"),
    bullet("Asignar precios por tipo a cada producto"),
    bullet("Ajuste masivo de precios por porcentaje"),
    bullet("Importar/Exportar precios via Excel"),
    spacer(),

    heading2("5.8 Configuraci\u00F3n de Descuentos"),
    para("Se pueden configurar descuentos en tres niveles:"),
    spacer(),
    infoTable("Tipo de descuento", "Descripci\u00F3n", [
      ["Por producto", "Descuento directo aplicado a un producto espec\u00EDfico"],
      ["Por subcategor\u00EDa", "Descuento aplicado a toda una subcategor\u00EDa"],
      ["Por m\u00E9todo de pago", "Descuento adicional al usar un m\u00E9todo de pago espec\u00EDfico"],
    ]),
    spacer(),
    para("Cada descuento puede tener un per\u00EDodo de vigencia (fecha inicio - fecha fin)."),
    spacer(),

    heading2("5.9 Configuraci\u00F3n de Productos"),
    para("En Configuraci\u00F3n de Productos se gestionan:"),
    bullet("Categor\u00EDas y subcategor\u00EDas"),
    bullet("Colores, talles, temporadas, origen"),
    bullet("Proveedores"),
    bullet("Cantidad de d\u00EDgitos para c\u00F3digos autom\u00E1ticos"),
    spacer(),

    // ===== 6. CAJA FUERTE =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("6. Caja Fuerte"),
    para("La Caja Fuerte es la b\u00F3veda de efectivo a nivel de sucursal. El efectivo de las cajas registradoras se transfiere a la Caja Fuerte."),
    spacer(),

    heading2("6.1 Descripci\u00F3n general"),
    para("Cada sucursal tiene una Caja Fuerte asignada autom\u00E1ticamente."),
    bullet("Saldo actual en tiempo real"),
    bullet("Historial de ingresos y retiros"),
    bullet("Ingreso autom\u00E1tico al cerrar cajas registradoras"),
    spacer(),

    heading2("6.2 Ingresos y Retiros"),
    spacer(),
    heading3("Registrar un ingreso"),
    step("Vaya a la pantalla de Caja Fuerte."),
    step("Haga clic en \"Ingreso\"."),
    step("Ingrese el monto y el motivo."),
    step("Confirme."),
    spacer(),

    heading3("Registrar un retiro"),
    step("Vaya a la pantalla de Caja Fuerte."),
    step("Haga clic en \"Retiro\"."),
    step("Ingrese el monto y el motivo."),
    step("Confirme."),
    spacer(),

    heading2("6.3 Integraci\u00F3n Caja Registradora \u2192 Caja Fuerte"),
    para("Al cerrar una caja registradora, el saldo se transfiere autom\u00E1ticamente a la Caja Fuerte."),
    bullet("Cierre autom\u00E1tico (auto_cierre) \u2014 Procesado por el sistema"),
    bullet("Cierre manual \u2014 Realizado por el administrador"),
    bullet("Retiro administrativo (admin_retiro) \u2014 Retiro directo de la Caja Fuerte"),
    spacer(),

    heading2("6.4 Consulta de saldo e historial"),
    para("En la pantalla de Caja Fuerte puede consultar:"),
    bullet("Saldo actual"),
    bullet("Historial de operaciones por fecha"),
    bullet("Clasificaci\u00F3n por origen (cierre autom\u00E1tico / manual / administrativo)"),
    bullet("Informaci\u00F3n del responsable"),
    spacer(),

    // ===== 7. GESTI\u00D3N DE VENTAS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("7. Gesti\u00F3n de Ventas (Vista Administrador)"),
    para("Como administrador, puede monitorear las ventas y gestionar la configuraci\u00F3n."),
    spacer(),

    heading2("7.1 Monitoreo de ventas"),
    para("En la lista de Ventas puede consultar todas las transacciones:"),
    bullet("Filtrar por fecha, estado o cliente"),
    bullet("Ver detalle de cada venta (productos, pagos, descuentos)"),
    bullet("Clasificar por estado (Borrador, Facturado, Pendiente de Pago, Pagado)"),
    spacer(),

    heading2("7.2 Estados de una venta"),
    para("El ciclo de vida de una venta es:"),
    spacer(),
    infoTable("Estado", "Descripci\u00F3n", [
      ["Draft (Borrador)", "Venta a\u00FAn no confirmada"],
      ["Invoiced (Facturado)", "Factura emitida"],
      ["Pending Payment (Pago Pendiente)", "Esperando el pago"],
      ["Paid (Pagado)", "Pago completado, estado final"],
    ]),
    spacer(),

    heading2("7.3 Gesti\u00F3n de Gastos"),
    para("Administre los gastos registrados:"),
    bullet("Consultar y buscar gastos"),
    bullet("Ver detalle (monto, categor\u00EDa, responsable, fecha)"),
    bullet("Editar y eliminar gastos"),
    spacer(),

    heading2("7.4 Estado de Cajas Registradoras"),
    para("En Control de Caja puede monitorear todas las cajas registradoras:"),
    bullet("Estado abierta/cerrada de cada caja"),
    bullet("Saldo actual"),
    bullet("Transacciones del d\u00EDa"),
    bullet("Apertura y cierre de cajas"),
    spacer(),

    heading2("7.5 Configuraci\u00F3n de Ventas"),
    para("En Configuraci\u00F3n de Ventas se gestionan:"),
    bullet("M\u00E9todos de pago"),
    bullet("Reglas de descuento"),
    bullet("Reglas de recargo"),
    bullet("Categor\u00EDas de gastos"),
    spacer(),

    // ===== 8. REPORTES =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("8. Reportes"),
    para("Genere informes detallados para tomar decisiones basadas en datos."),
    spacer(),

    heading2("8.1 Dashboard de Reportes"),
    para("El dashboard de reportes muestra indicadores clave:"),
    bullet("Resumen de ventas diario/semanal/mensual"),
    bullet("Variaci\u00F3n respecto al per\u00EDodo anterior"),
    bullet("Alertas y notificaciones principales"),
    spacer(),

    heading2("8.2 Reportes de Ventas"),
    para("Analice sus ventas desde m\u00FAltiples perspectivas:"),
    bullet("Por per\u00EDodo \u2014 Tendencia diaria, semanal, mensual"),
    bullet("Por sucursal \u2014 Comparaci\u00F3n entre sucursales"),
    bullet("Por vendedor \u2014 Rendimiento individual"),
    bullet("Por producto \u2014 Productos m\u00E1s vendidos y tendencias"),
    bullet("Exportar a Excel"),
    spacer(),

    heading2("8.3 Reportes de Gastos"),
    bullet("An\u00E1lisis de gastos por categor\u00EDa"),
    bullet("Tendencia de gastos por per\u00EDodo"),
    bullet("Comparaci\u00F3n de gastos por sucursal"),
    spacer(),

    heading2("8.4 Reportes de Stock"),
    bullet("Stock actual por sucursal"),
    bullet("Productos con stock bajo o agotados"),
    bullet("Historial de movimientos de stock"),
    bullet("Exportar a Excel"),
    spacer(),

    heading2("8.5 Reportes de Cuentas"),
    bullet("Resumen de ventas por m\u00E9todo de pago"),
    bullet("Cuentas por cobrar"),
    bullet("Liquidaciones diarias"),
    spacer(),

    heading2("8.6 An\u00E1lisis de Ventas por Sucursal"),
    para("En Admin > Ventas puede analizar las ventas detalladas por sucursal:"),
    bullet("Ventas diarias/mensuales por sucursal"),
    bullet("Comparaci\u00F3n de rendimiento entre sucursales"),
    bullet("Drill-down a detalle de ventas individuales"),
    spacer(),

    // ===== 9. AUDITOR\u00CDA =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("9. Auditor\u00EDa y Monitoreo"),
    spacer(),

    heading2("9.1 Registro de Auditor\u00EDa"),
    para("En Admin > Auditor\u00EDa puede rastrear todos los cambios del sistema:"),
    bullet("Historial de actividad por usuario"),
    bullet("Filtros por fecha y tipo de acci\u00F3n"),
    bullet("Datos antes/despu\u00E9s de cada cambio"),
    bullet("B\u00FAsqueda de eventos espec\u00EDficos"),
    spacer(),
    infoBox("Nota", "El registro de auditor\u00EDa solo es accesible para Superadmin."),
    spacer(),

    heading2("9.2 Monitoreo de Cajas Registradoras"),
    para("Supervise en tiempo real el estado de todas las cajas:"),
    bullet("Lista de cajas abiertas y sus responsables"),
    bullet("Saldo actual de cada caja"),
    bullet("Detecci\u00F3n de movimientos at\u00EDpicos"),
    spacer(),

    heading2("9.3 Seguimiento de Actividad de Usuarios"),
    bullet("Verificar \u00FAltimo inicio de sesi\u00F3n"),
    bullet("Consultar cantidad de ventas por usuario"),
    bullet("Identificar usuarios inactivos"),
    spacer(),

    // ===== AP\u00C9NDICE =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("Ap\u00E9ndice"),
    spacer(),

    heading2("A. Glosario"),
    spacer(),
    infoTable("T\u00E9rmino", "Descripci\u00F3n", [
      ["Tienda", "Entidad principal del negocio"],
      ["Sucursal", "Ubicaci\u00F3n f\u00EDsica o l\u00F3gica dentro de una tienda"],
      ["Caja Registradora", "Terminal de cobro asignado a una sucursal"],
      ["Caja Fuerte", "B\u00F3veda de efectivo a nivel de sucursal"],
      ["Producto Padre", "Producto base que tiene variantes (color/talle)"],
      ["Producto Gen\u00E9rico", "Producto especial para ventas r\u00E1pidas sin c\u00F3digo"],
      ["PriceType", "Tipo de precio (Minorista, Mayorista, etc.)"],
      ["ACL", "Lista de Control de Acceso - sistema de permisos"],
      ["Venta Suspendida", "Venta pausada que puede retomarse m\u00E1s tarde"],
    ]),
    spacer(),

    heading2("B. Mensajes de Error y Soluciones"),
    spacer(),
    heading3("\"No existen cajas asociadas a esta sucursal\""),
    para("Soluci\u00F3n: En Admin > Sucursales, agregue una caja registradora y terminal a la sucursal correspondiente."),
    spacer(),
    heading3("Bot\u00F3n \"Pagar\" deshabilitado"),
    para("Soluci\u00F3n: Haga clic en \"Iniciar Caja\" en la barra superior para abrir una caja registradora."),
    spacer(),
    heading3("Producto no aparece en la b\u00FAsqueda"),
    para("Soluci\u00F3n: (1) Verifique que el producto est\u00E9 asignado a la sucursal actual, (2) Verifique que el estado sea Activo."),
    spacer(),
    heading3("Acceso denegado (Unauthorized)"),
    para("Soluci\u00F3n: Verifique que el rol del usuario tenga los permisos necesarios en Admin > Permisos."),
    spacer(),

    heading2("C. Preguntas Frecuentes (FAQ)"),
    spacer(),
    heading3("El sistema est\u00E1 lento"),
    para("Verifique su conexi\u00F3n a Internet. Si el problema persiste, limpie la cach\u00E9 del navegador o contacte al soporte t\u00E9cnico."),
    spacer(),
    heading3("\u00BFC\u00F3mo exporto datos a Excel?"),
    para("En las secciones de Reportes, aplique los filtros deseados y haga clic en el bot\u00F3n de exportaci\u00F3n a Excel."),
    spacer(),
    heading3("Olvid\u00E9 mi contrase\u00F1a"),
    para("Use el enlace \"Olvidaste tu contrase\u00F1a\" en la pantalla de login, o solicite al Superadmin que restablezca su contrase\u00F1a."),
    spacer(),

    // 하단 서명
    spacer(),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 400 },
      border: { top: { style: BorderStyle.SINGLE, size: 4, color: PRIMARY, space: 20 } },
      children: [new TextRun({ text: "VentaGO \u2014 Sistema Integral de Gesti\u00F3n de Ventas", size: 20, font: "Arial", color: GRAY, italics: true })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "\u00A9 2026 \u2014 Todos los derechos reservados", size: 18, font: "Arial", color: GRAY })],
    }),
  ];
}

// ====================== 문서 빌드 ======================
function buildDocument(lang) {
  const isKorean = lang === "ko";

  const titleText = isKorean ? "VentaGO" : "VentaGO";
  const subtitleText = isKorean ? "\uAD00\uB9AC\uC790 \uB9E4\uB274\uC5BC" : "Manual del Administrador";
  const systemDesc = isKorean ? "\uD1B5\uD569 \uD310\uB9E4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C" : "Sistema Integral de Gesti\u00F3n de Ventas";
  const versionText = isKorean ? "\uBC84\uC804 1.0 \u2014 2026\uB144 3\uC6D4" : "Versi\u00F3n 1.0 \u2014 Marzo 2026";
  const headerText = isKorean ? "VentaGO \u2014 \uAD00\uB9AC\uC790 \uB9E4\uB274\uC5BC" : "VentaGO \u2014 Manual del Administrador";
  const pageText = isKorean ? "\uD398\uC774\uC9C0 " : "P\u00E1gina ";

  return new Document({
    styles: {
      default: { document: { run: { font: "Arial", size: 22 } } },
      paragraphStyles: [
        { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { size: 32, bold: true, font: "Arial", color: DARK },
          paragraph: { spacing: { before: 400, after: 200 }, outlineLevel: 0 } },
        { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { size: 26, bold: true, font: "Arial", color: PRIMARY },
          paragraph: { spacing: { before: 300, after: 150 }, outlineLevel: 1 } },
      ]
    },
    numbering: { config: numberingConfig },
    sections: [
      // ===== 표지 =====
      {
        properties: {
          page: {
            size: { width: 12240, height: 15840 },
            margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
          },
        },
        children: [
          spacer(), spacer(), spacer(), spacer(), spacer(), spacer(),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            spacing: { after: 200 },
            children: [new TextRun({ text: titleText, size: 72, bold: true, font: "Arial", color: PRIMARY })],
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            spacing: { after: 100 },
            children: [new TextRun({ text: "Ver. 1.0", size: 36, font: "Arial", color: GRAY })],
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            spacing: { after: 400 },
            border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: PRIMARY, space: 20 } },
            children: [],
          }),
          spacer(),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            spacing: { after: 200 },
            children: [new TextRun({ text: subtitleText, size: 48, bold: true, font: "Arial", color: DARK })],
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            spacing: { after: 100 },
            children: [new TextRun({ text: systemDesc, size: 28, font: "Arial", color: GRAY })],
          }),
          spacer(), spacer(), spacer(), spacer(), spacer(), spacer(), spacer(),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: versionText, size: 22, font: "Arial", color: GRAY })],
          }),
          new Paragraph({ children: [new PageBreak()] }),
        ],
      },
      // ===== 본문 =====
      {
        properties: {
          page: {
            size: { width: 12240, height: 15840 },
            margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
          },
        },
        headers: {
          default: new Header({
            children: [new Paragraph({
              border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: PRIMARY, space: 8 } },
              tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
              children: [
                new TextRun({ text: headerText, size: 18, font: "Arial", color: GRAY }),
              ],
            })],
          }),
        },
        footers: {
          default: new Footer({
            children: [new Paragraph({
              alignment: AlignmentType.CENTER,
              border: { top: { style: BorderStyle.SINGLE, size: 2, color: "DDDDDD", space: 8 } },
              children: [
                new TextRun({ text: pageText, size: 18, font: "Arial", color: GRAY }),
                new TextRun({ children: [PageNumber.CURRENT], size: 18, font: "Arial", color: GRAY }),
              ],
            })],
          }),
        },
        children: isKorean ? buildKoreanContent() : buildSpanishContent(),
      },
    ],
  });
}

// ====================== 생성 실행 ======================
async function main() {
  const basePath = "/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/manuales";

  // 한국어 버전
  const koDoc = buildDocument("ko");
  const koBuffer = await Packer.toBuffer(koDoc);
  const koPath = `${basePath}/Manual_Administrador_VentaGO_KO.docx`;
  fs.writeFileSync(koPath, koBuffer);
  console.log(`[KO] \uC0DD\uC131 \uC644\uB8CC: ${koPath} (${(koBuffer.length / 1024).toFixed(1)} KB)`);

  // 스페인어 버전
  const esDoc = buildDocument("es");
  const esBuffer = await Packer.toBuffer(esDoc);
  const esPath = `${basePath}/Manual_Administrador_VentaGO_ES.docx`;
  fs.writeFileSync(esPath, esBuffer);
  console.log(`[ES] Generado: ${esPath} (${(esBuffer.length / 1024).toFixed(1)} KB)`);
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
