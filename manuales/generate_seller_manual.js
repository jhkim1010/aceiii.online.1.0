const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, HeadingLevel,
  BorderStyle, WidthType, ShadingType, PageNumber, PageBreak,
  TabStopType, TabStopPosition,
} = require('docx');

// 색상 팔레트
const PRIMARY = "2E75B6";
const DARK = "1B4F72";
const LIGHT_BG = "E8F0FE";
const GRAY = "666666";
const LIGHT_GRAY = "F5F5F5";

// 테이블 테두리
const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };

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
function shortcutTable(headerLeft, headerRight, rows) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [2800, 6560],
    rows: [
      new TableRow({ children: [
        new TableCell({ borders, width: { size: 2800, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: headerLeft, bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
        new TableCell({ borders, width: { size: 6560, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: headerRight, bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
      ]}),
      ...rows.map(([key, action], i) => new TableRow({ children: [
        new TableCell({ borders, width: { size: 2800, type: WidthType.DXA }, shading: { fill: i % 2 === 0 ? LIGHT_GRAY : "FFFFFF", type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: key, bold: true, size: 20, font: "Courier New" })] })] }),
        new TableCell({ borders, width: { size: 6560, type: WidthType.DXA }, shading: { fill: i % 2 === 0 ? LIGHT_GRAY : "FFFFFF", type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: action, size: 20, font: "Arial" })] })] }),
      ]}))
    ]
  });
}
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

// ====================== 한국어 매뉴얼 ======================
function buildKoreanContent() {
  return [
    // ===== 1장. 시작하기 =====
    heading1("1. 시작하기"),
    para("VentaGO는 매장의 판매를 관리하는 시스템입니다. 이 매뉴얼은 판매원(Vendedor)이 일상 업무를 수행하는 데 필요한 기능만을 안내합니다."),
    spacer(),

    heading2("1.1 로그인"),
    step("브라우저에서 시스템 주소를 입력합니다."),
    step("이메일 또는 사용자명을 입력합니다."),
    step("비밀번호를 입력합니다."),
    step("\"Iniciar Sesi\u00F3n\" (로그인) 버튼을 클릭합니다."),
    spacer(),
    tipBox("참고", "비밀번호를 잊어버린 경우 \"Olvidaste tu contrase\u00F1a\" (비밀번호 찾기) 링크를 클릭하거나 관리자에게 문의하세요."),
    spacer(),

    heading2("1.2 로그아웃"),
    step("우측 상단의 프로필 아이콘을 클릭합니다."),
    step("\"Cerrar Sesi\u00F3n\" (로그아웃)을 선택합니다."),
    spacer(),
    infoBox("중요", "퇴근 시 반드시 로그아웃하세요. 금전 등록기를 먼저 마감한 후 로그아웃합니다."),
    spacer(),

    heading2("1.3 화면 구성 이해"),
    para("로그인 후 보이는 화면은 다음과 같이 구성됩니다:"),
    bullet("사이드바 (좌측) \u2014 메뉴 탐색. 판매 관련 메뉴가 표시됩니다"),
    bullet("상단바 \u2014 금전 등록기 상태, 알림, 프로필 접근"),
    bullet("메인 영역 \u2014 현재 작업 화면 (판매, 판매 목록 등)"),
    spacer(),

    // ===== 2장. 영업 시작 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("2. 영업 시작"),
    para("판매를 하기 전에 반드시 금전 등록기(Caja)를 열어야 합니다."),
    spacer(),

    heading2("2.1 금전 등록기(Caja) 열기"),
    step("로그인 후 시스템이 자동으로 금전 등록기 상태를 확인합니다."),
    step("등록기가 열려 있지 않으면 팝업이 나타납니다."),
    step("상단바의 \"Iniciar Caja\" (금전 등록기 시작) 버튼을 클릭합니다."),
    step("사용할 Caja (금전 등록기)를 선택합니다."),
    step("사용할 Terminal (터미널)을 선택합니다."),
    step("확인을 클릭합니다."),
    spacer(),
    infoBox("중요", "금전 등록기를 열지 않으면 \"Pagar\" (결제) 버튼이 비활성화됩니다. 반드시 먼저 등록기를 열어주세요."),
    spacer(),

    heading2("2.2 터미널 상태 확인"),
    para("상단바에서 현재 등록기와 터미널 상태를 확인할 수 있습니다:"),
    bullet("열린 등록기 이름"),
    bullet("연결된 터미널 이름"),
    bullet("오늘 오픈한 등록기 목록"),
    spacer(),

    // ===== 3장. 새 판매 (핵심) =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("3. 새 판매 (Nueva Venta)"),
    para("이 장은 가장 핵심적인 일상 업무인 판매 과정을 설명합니다."),
    spacer(),

    heading2("3.1 POS 화면 구성"),
    para("새 판매 화면은 두 영역으로 나뉩니다:"),
    spacer(),
    heading3("좌측: 고객 정보 + 상품"),
    bullet("상단 \u2014 고객 정보 입력 영역 (문서번호, 이름, 판매원, 지역)"),
    bullet("중간 \u2014 상품 검색 및 추가 영역"),
    bullet("하단 \u2014 추가된 상품 목록 (수량, 가격, 소계)"),
    spacer(),
    heading3("우측: 고객 목록"),
    para("등록된 고객 목록이 표시됩니다. 고객을 선택하면 자동으로 정보가 채워집니다."),
    spacer(),

    heading2("3.2 상품 검색 및 추가"),
    step("상품 검색창에 상품 이름, 코드 또는 SKU를 입력합니다."),
    step("드롭다운 목록에서 상품을 선택합니다."),
    step("수량을 조정합니다."),
    step("가격 유형이 여러 개인 경우 적절한 가격을 선택합니다."),
    step("상품이 자동으로 아래 목록에 추가됩니다."),
    spacer(),

    heading2("3.3 수량 변경"),
    para("상품 목록에서 수량을 변경하는 방법:"),
    bullet("수량 필드를 직접 클릭하여 숫자를 수정합니다"),
    bullet("총액이 자동으로 재계산됩니다"),
    bullet("상품을 삭제하려면 해당 행의 삭제 아이콘을 클릭합니다"),
    spacer(),

    heading2("3.4 할인 적용"),
    para("판매에 할인을 적용하는 방법:"),
    bullet("상품별 할인 \u2014 이미 설정된 할인이 자동 적용됩니다"),
    bullet("판매 전체 할인 \u2014 결제 화면에서 추가 할인을 입력합니다"),
    bullet("결제수단 할인 \u2014 특정 결제 수단 선택 시 자동 적용됩니다"),
    spacer(),

    heading2("3.5 추가 요금(Recargo) 적용"),
    para("필요한 경우 판매에 추가 요금을 적용할 수 있습니다."),
    bullet("결제 화면에서 Recargo (추가 요금) 항목에 금액을 입력합니다"),
    bullet("총액에 추가 요금이 반영됩니다"),
    spacer(),

    heading2("3.6 고객(Cliente) 연결"),
    para("판매에 고객을 연결하는 방법:"),
    spacer(),
    heading3("기존 고객 선택"),
    step("우측 고객 목록에서 해당 고객을 클릭합니다."),
    step("고객 정보가 상단 영역에 자동으로 입력됩니다."),
    spacer(),
    heading3("문서번호로 검색"),
    step("고객 정보 영역의 Documento (문서번호) 필드에 번호를 입력합니다."),
    step("9자리 이상 입력 시 상세 정보 입력 필드가 자동으로 확장됩니다."),
    step("기존 고객이면 자동으로 정보가 채워지고, 새 고객이면 정보를 입력합니다."),
    spacer(),

    heading2("3.7 판매원 지정"),
    para("판매를 특정 판매원에게 귀속시킬 수 있습니다."),
    step("고객 정보 영역의 Vendedor (판매원) 필드에서 판매원을 선택합니다."),
    spacer(),

    heading2("3.8 결제 처리"),
    para("모든 상품을 추가한 후 결제를 진행합니다."),
    spacer(),
    step("\"Pagar\" (결제) 버튼을 클릭합니다 (또는 F11 키)."),
    step("결제 수단을 선택합니다 (현금, 카드, 이체 등)."),
    step("각 결제 수단에 금액을 입력합니다."),
    step("여러 결제 수단을 조합할 수 있습니다 (예: 현금 일부 + 카드 일부)."),
    step("결제 금액이 총액과 일치하면 \"Generar Venta\" (판매 생성) 버튼이 활성화됩니다."),
    step("\"Generar Venta\"를 클릭하여 판매를 완료합니다."),
    spacer(),

    shortcutTable("단축키", "기능", [
      ["F11", "결제 창 열기/확인"],
      ["Esc", "현재 판매 전체 초기화"],
    ]),
    spacer(),

    heading2("3.9 영수증 출력"),
    para("판매가 완료되면 영수증 출력 여부를 선택할 수 있습니다."),
    bullet("자동 출력 \u2014 설정에 따라 완료 즉시 자동 출력"),
    bullet("수동 출력 \u2014 판매 상세 화면에서 인쇄 버튼 클릭"),
    spacer(),
    tipBox("참고", "영수증 출력에는 프린트 에이전트(Print Agent)가 실행 중이어야 합니다. 출력되지 않는 경우 관리자에게 문의하세요."),
    spacer(),

    heading3("빠른 판매 (Venta R\u00E1pida)"),
    para("코드가 없는 상품을 판매해야 할 때 사용합니다."),
    step("상품 영역에서 \"Venta R\u00E1pida\" (빠른 판매) 스위치를 켭니다."),
    step("상품 이름을 직접 입력합니다."),
    step("단가를 입력합니다."),
    step("수량을 조정합니다."),
    step("\"Agregar\" (추가) 버튼을 클릭합니다."),
    spacer(),
    tipBox("참고", "빠른 판매는 내부 일반 상품(Gen\u00E9rico)을 사용합니다. 입력한 이름이 영수증에 표시됩니다."),
    spacer(),

    // ===== 4장. 판매 관리 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("4. 판매 관리"),
    spacer(),

    heading2("4.1 판매 일시 중지(Suspender) 및 재개"),
    para("진행 중인 판매를 일시적으로 저장하고 나중에 다시 이어서 할 수 있습니다."),
    spacer(),
    heading3("판매 일시 중지"),
    step("판매 중 상단의 \"Suspender\" (일시 중지) 버튼을 클릭합니다."),
    step("현재까지 추가된 상품, 할인, 추가 요금, 고객 정보가 모두 저장됩니다."),
    step("새로운 판매를 시작할 수 있습니다."),
    spacer(),

    heading3("중지된 판매 재개"),
    step("\"Ventas Suspendidas\" (중지된 판매) 목록에서 해당 판매를 선택합니다."),
    step("저장된 모든 정보가 복원됩니다."),
    step("이어서 상품을 추가하거나 결제를 진행합니다."),
    spacer(),
    tipBox("참고", "중지된 판매는 다른 판매원도 재개할 수 있습니다. 고객이 돌아왔을 때 어떤 판매원이든 이어서 진행 가능합니다."),
    spacer(),

    heading2("4.2 판매 목록 조회"),
    para("Ventas (판매) 메뉴에서 완료된 판매를 조회합니다:"),
    bullet("날짜별 필터링"),
    bullet("고객 이름으로 검색"),
    bullet("판매 상태별 분류"),
    spacer(),

    heading2("4.3 판매 상세 확인"),
    para("판매 목록에서 특정 판매를 클릭하면 상세 정보를 볼 수 있습니다:"),
    bullet("구매한 상품 목록 (이름, 수량, 단가, 소계)"),
    bullet("적용된 할인 및 추가 요금"),
    bullet("사용한 결제 수단 및 금액"),
    bullet("고객 정보"),
    bullet("판매 일시 및 담당 판매원"),
    spacer(),

    // ===== 5장. 경비 등록 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("5. 경비 등록"),
    para("매장 운영 중 발생하는 경비를 기록합니다."),
    spacer(),

    heading2("5.1 경비(Gasto) 입력"),
    step("사이드바에서 Gastos (경비)를 선택합니다."),
    step("\"Nuevo Gasto\" (새 경비)를 클릭합니다."),
    step("설명을 입력합니다 (예: 사무용품 구입, 택배비 등)."),
    step("금액을 입력합니다."),
    step("날짜를 선택합니다 (기본값: 오늘)."),
    step("저장합니다."),
    spacer(),

    heading2("5.2 경비 카테고리 선택"),
    para("경비를 올바른 카테고리로 분류합니다:"),
    bullet("카테고리 \u2014 대분류 (운영비, 임대료, 급여 등)"),
    bullet("서브카테고리 \u2014 세부 분류 (사무용품, 청소용품 등)"),
    spacer(),
    tipBox("참고", "경비가 금전 등록기의 현금에서 지출된 경우, \"Afecta Caja\" (등록기 영향) 옵션을 활성화하세요. 등록기 잔고에 자동으로 반영됩니다."),
    spacer(),

    // ===== 6장. 상품 조회 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("6. 상품 조회"),
    para("판매 중 상품 정보를 확인해야 할 때 사용합니다."),
    spacer(),

    heading2("6.1 상품 검색 및 정보 확인"),
    step("사이드바에서 Productos (상품)를 선택합니다."),
    step("검색창에 상품 이름, 코드 또는 SKU를 입력합니다."),
    step("상품을 클릭하면 상세 정보를 확인할 수 있습니다."),
    spacer(),
    para("확인 가능한 정보:"),
    bullet("상품 이름, SKU, 바코드"),
    bullet("카테고리 및 서브카테고리"),
    bullet("색상, 사이즈 (변형 상품인 경우)"),
    bullet("공급업체"),
    spacer(),

    heading2("6.2 재고 확인"),
    para("상품 상세 화면에서 현재 지점의 재고를 확인합니다:"),
    bullet("현재 재고 수량"),
    bullet("다른 지점의 재고 (권한이 있는 경우)"),
    spacer(),

    heading2("6.3 가격 확인"),
    para("상품의 가격 정보를 확인합니다:"),
    bullet("가격 유형별 가격 (소매, 도매 등)"),
    bullet("현재 적용 중인 할인"),
    spacer(),

    // ===== 7장. 영업 종료 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("7. 영업 종료"),
    para("하루 영업을 마무리할 때 반드시 금전 등록기를 마감해야 합니다."),
    spacer(),

    heading2("7.1 금전 등록기 마감"),
    step("중지된 판매(Ventas Suspendidas)가 없는지 확인합니다."),
    step("상단바의 금전 등록기 영역을 클릭합니다."),
    step("\"Cerrar Caja\" (등록기 마감)을 선택합니다."),
    step("오늘의 거래 요약이 표시됩니다."),
    step("내용을 확인하고 마감을 승인합니다."),
    spacer(),
    infoBox("중요", "마감 시 등록기의 현금 잔고가 자동으로 금고(Caja Fuerte)에 입금됩니다."),
    spacer(),

    heading2("7.2 일일 정산 확인"),
    para("마감 후 다음 사항을 확인합니다:"),
    spacer(),
    infoTable("항목", "확인 내용", [
      ["판매 건수", "오늘 완료한 총 판매 수"],
      ["총 매출", "오늘의 총 판매 금액"],
      ["경비", "오늘 등록한 경비 합계"],
      ["결제수단별", "현금, 카드, 이체 등 각 결제 수단별 금액"],
      ["등록기 잔고", "마감 시점의 등록기 잔고 (0이어야 정상)"],
    ]),
    spacer(),

    para("정산 금액에 이상이 있으면 관리자에게 즉시 보고합니다."),
    spacer(),

    // ===== 부록 =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("부록"),
    spacer(),

    heading2("A. 자주 묻는 질문 (FAQ)"),
    spacer(),

    heading3("결제(Pagar) 버튼이 비활성화되어 있습니다"),
    para("금전 등록기를 아직 열지 않았습니다. 상단바에서 \"Iniciar Caja\"를 클릭하여 등록기를 여세요."),
    spacer(),

    heading3("상품 검색에서 아무것도 나오지 않습니다"),
    para("(1) 상품 이름이나 코드를 정확히 입력했는지 확인하세요. (2) 해당 상품이 현재 지점에 배정되어 있는지 관리자에게 확인하세요."),
    spacer(),

    heading3("판매 중간에 고객이 결제를 나중에 하겠다고 합니다"),
    para("\"Suspender\" (일시 중지) 버튼을 눌러 현재 판매를 저장하세요. 고객이 돌아오면 중지된 판매 목록에서 재개할 수 있습니다."),
    spacer(),

    heading3("영수증이 출력되지 않습니다"),
    para("프린트 에이전트(Print Agent)가 실행 중인지 확인하세요. 문제가 지속되면 관리자에게 문의하세요."),
    spacer(),

    heading3("결제 금액을 잘못 입력했습니다"),
    para("판매가 아직 완료되지 않았다면 결제 창에서 금액을 수정할 수 있습니다. 이미 완료된 경우 관리자에게 문의하세요."),
    spacer(),

    heading3("시스템이 느리거나 반응이 없습니다"),
    para("(1) 인터넷 연결을 확인하세요. (2) 브라우저를 새로고침(F5)하세요. (3) 문제가 지속되면 관리자에게 문의하세요."),
    spacer(),

    heading2("B. 오류 발생 시 대처법"),
    spacer(),
    infoTable("상황", "대처", [
      ["\"No existen cajas\" 메시지", "관리자에게 금전 등록기/터미널 설정을 요청"],
      ["결제 버튼 비활성", "Iniciar Caja로 등록기 열기"],
      ["재고 부족 경고", "관리자에게 재고 확인 요청"],
      ["권한 없음 오류", "관리자에게 권한 부여 요청"],
      ["네트워크 오류", "인터넷 연결 확인 후 새로고침"],
    ]),
    spacer(),

    heading2("C. 주요 용어 정리"),
    spacer(),
    infoTable("시스템 용어", "뜻", [
      ["Nueva Venta", "새 판매 (POS 화면)"],
      ["Pagar", "결제하기"],
      ["Generar Venta", "판매 생성/완료"],
      ["Suspender", "판매 일시 중지"],
      ["Iniciar Caja", "금전 등록기 열기"],
      ["Cerrar Caja", "금전 등록기 마감"],
      ["Venta R\u00E1pida", "빠른 판매 (코드 없는 상품)"],
      ["Gastos", "경비"],
      ["Recargo", "추가 요금"],
      ["Descuento", "할인"],
      ["Cliente", "고객"],
      ["Vendedor", "판매원"],
      ["Producto", "상품"],
      ["Stock", "재고"],
      ["Sucursal", "지점"],
    ]),
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

// ====================== 스페인어 매뉴얼 ======================
function buildSpanishContent() {
  return [
    // ===== 1. EMPEZAR =====
    heading1("1. Primeros Pasos"),
    para("VentaGO es el sistema de gesti\u00F3n de ventas de su tienda. Este manual le gu\u00EDa en las funciones que necesita como vendedor para su trabajo diario."),
    spacer(),

    heading2("1.1 Iniciar sesi\u00F3n"),
    step("Abra su navegador e ingrese la direcci\u00F3n del sistema."),
    step("Ingrese su correo electr\u00F3nico o nombre de usuario."),
    step("Ingrese su contrase\u00F1a."),
    step("Haga clic en \"Iniciar Sesi\u00F3n\"."),
    spacer(),
    tipBox("Nota", "Si olvid\u00F3 su contrase\u00F1a, haga clic en \"Olvidaste tu contrase\u00F1a\" o contacte a su administrador."),
    spacer(),

    heading2("1.2 Cerrar sesi\u00F3n"),
    step("Haga clic en el icono de perfil en la esquina superior derecha."),
    step("Seleccione \"Cerrar Sesi\u00F3n\"."),
    spacer(),
    infoBox("Importante", "Al finalizar su turno, cierre primero la caja registradora y luego cierre sesi\u00F3n."),
    spacer(),

    heading2("1.3 Entender la interfaz"),
    para("Despu\u00E9s de iniciar sesi\u00F3n, la pantalla se compone de:"),
    bullet("Barra lateral (izquierda) \u2014 Men\u00FA de navegaci\u00F3n con las opciones de venta"),
    bullet("Barra superior \u2014 Estado de caja, notificaciones, perfil"),
    bullet("\u00C1rea principal \u2014 Pantalla de trabajo actual (ventas, listados, etc.)"),
    spacer(),

    // ===== 2. INICIO DE OPERACIONES =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("2. Inicio de Operaciones"),
    para("Antes de realizar cualquier venta, debe abrir la caja registradora."),
    spacer(),

    heading2("2.1 Abrir la Caja Registradora"),
    step("Al iniciar sesi\u00F3n, el sistema verifica autom\u00E1ticamente el estado de la caja."),
    step("Si no hay caja abierta, aparecer\u00E1 una ventana emergente."),
    step("Haga clic en \"Iniciar Caja\" en la barra superior."),
    step("Seleccione la Caja registradora asignada."),
    step("Seleccione el Terminal de pago."),
    step("Confirme la apertura."),
    spacer(),
    infoBox("Importante", "Sin caja abierta, el bot\u00F3n \"Pagar\" estar\u00E1 deshabilitado. Siempre abra la caja primero."),
    spacer(),

    heading2("2.2 Verificar estado del Terminal"),
    para("En la barra superior puede verificar:"),
    bullet("Nombre de la caja registradora abierta"),
    bullet("Terminal conectado"),
    bullet("Cajas abiertas hoy en esta sucursal"),
    spacer(),

    // ===== 3. NUEVA VENTA =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("3. Nueva Venta"),
    para("Este cap\u00EDtulo describe el proceso de venta, la funci\u00F3n m\u00E1s importante de su trabajo diario."),
    spacer(),

    heading2("3.1 Pantalla POS"),
    para("La pantalla de Nueva Venta se divide en dos \u00E1reas:"),
    spacer(),
    heading3("Izquierda: Cliente y Productos"),
    bullet("Parte superior \u2014 Informaci\u00F3n del cliente (documento, nombre, vendedor, provincia)"),
    bullet("Parte media \u2014 B\u00FAsqueda y selecci\u00F3n de productos"),
    bullet("Parte inferior \u2014 Lista de art\u00EDculos agregados (cantidad, precio, subtotal)"),
    spacer(),
    heading3("Derecha: Lista de Clientes"),
    para("Muestra los clientes registrados. Al seleccionar uno, sus datos se cargan autom\u00E1ticamente."),
    spacer(),

    heading2("3.2 Buscar y agregar productos"),
    step("En el campo de b\u00FAsqueda, escriba el nombre, c\u00F3digo o SKU del producto."),
    step("Seleccione el producto de la lista desplegable."),
    step("Ajuste la cantidad."),
    step("Si hay m\u00FAltiples tipos de precio, seleccione el adecuado."),
    step("El producto se agrega autom\u00E1ticamente a la lista de art\u00EDculos."),
    spacer(),

    heading2("3.3 Modificar cantidades"),
    para("Para cambiar la cantidad de un producto:"),
    bullet("Haga clic directamente en el campo de cantidad y modifique el n\u00FAmero"),
    bullet("El total se recalcula autom\u00E1ticamente"),
    bullet("Para eliminar un producto, haga clic en el icono de eliminar de esa fila"),
    spacer(),

    heading2("3.4 Aplicar descuentos"),
    para("Los descuentos se aplican de diferentes formas:"),
    bullet("Por producto \u2014 Los descuentos configurados se aplican autom\u00E1ticamente"),
    bullet("Descuento general \u2014 Se ingresa en la pantalla de pago"),
    bullet("Por m\u00E9todo de pago \u2014 Se aplica autom\u00E1ticamente al seleccionar el m\u00E9todo"),
    spacer(),

    heading2("3.5 Aplicar recargos"),
    para("Si es necesario agregar un recargo a la venta:"),
    bullet("En la pantalla de pago, ingrese el monto en el campo Recargo"),
    bullet("El total se actualiza con el recargo incluido"),
    spacer(),

    heading2("3.6 Asociar un Cliente"),
    para("Para vincular un cliente a la venta:"),
    spacer(),
    heading3("Seleccionar cliente existente"),
    step("En la lista de clientes (derecha), haga clic en el cliente deseado."),
    step("Sus datos se cargan autom\u00E1ticamente en el formulario superior."),
    spacer(),
    heading3("Buscar por documento"),
    step("En el campo Documento, ingrese el n\u00FAmero de documento del cliente."),
    step("Al ingresar 9 o m\u00E1s d\u00EDgitos, el formulario se expande mostrando todos los campos."),
    step("Si el cliente existe, sus datos se completan autom\u00E1ticamente. Si es nuevo, ingrese la informaci\u00F3n."),
    spacer(),

    heading2("3.7 Asignar Vendedor"),
    para("Para atribuir la venta a un vendedor espec\u00EDfico:"),
    step("En el formulario de cliente, seleccione el vendedor en el campo Vendedor."),
    spacer(),

    heading2("3.8 Procesar el Pago"),
    para("Una vez agregados todos los productos, proceda al pago."),
    spacer(),
    step("Haga clic en \"Pagar\" (o presione F11)."),
    step("Seleccione el m\u00E9todo de pago (Efectivo, Tarjeta, Transferencia, etc.)."),
    step("Ingrese el monto para cada m\u00E9todo."),
    step("Puede combinar m\u00FAltiples m\u00E9todos (ej: parte en efectivo + parte con tarjeta)."),
    step("Cuando el monto pagado iguale el total, se habilita \"Generar Venta\"."),
    step("Haga clic en \"Generar Venta\" para completar la transacci\u00F3n."),
    spacer(),

    shortcutTable("Tecla", "Acci\u00F3n", [
      ["F11", "Abrir/confirmar el modal de pago"],
      ["Esc", "Limpiar toda la venta actual"],
    ]),
    spacer(),

    heading2("3.9 Imprimir recibo"),
    para("Al completar la venta, puede imprimir un recibo."),
    bullet("Impresi\u00F3n autom\u00E1tica \u2014 Seg\u00FAn la configuraci\u00F3n, se imprime al completar"),
    bullet("Impresi\u00F3n manual \u2014 Desde la vista detalle de la venta, haga clic en el bot\u00F3n de imprimir"),
    spacer(),
    tipBox("Nota", "El Print Agent debe estar ejecut\u00E1ndose para imprimir recibos. Si no funciona, contacte al administrador."),
    spacer(),

    heading3("Venta R\u00E1pida (sin c\u00F3digo)"),
    para("Para vender productos que no tienen c\u00F3digo en el sistema:"),
    step("Active el switch \"Venta R\u00E1pida\" en la secci\u00F3n de productos."),
    step("Ingrese el nombre del producto manualmente."),
    step("Ingrese el precio unitario."),
    step("Ajuste la cantidad."),
    step("Haga clic en \"Agregar\"."),
    spacer(),
    tipBox("Nota", "La Venta R\u00E1pida usa un producto gen\u00E9rico interno. El nombre que ingrese aparecer\u00E1 en el recibo."),
    spacer(),

    // ===== 4. GESTI\u00D3N DE VENTAS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("4. Gesti\u00F3n de Ventas"),
    spacer(),

    heading2("4.1 Suspender y retomar ventas"),
    para("Puede guardar temporalmente una venta en curso y retomarla despu\u00E9s."),
    spacer(),
    heading3("Suspender una venta"),
    step("Durante la venta, haga clic en \"Suspender\"."),
    step("Se guardan todos los productos, descuentos, recargos y datos del cliente."),
    step("Puede iniciar una nueva venta."),
    spacer(),

    heading3("Retomar una venta suspendida"),
    step("Abra la lista de \"Ventas Suspendidas\"."),
    step("Seleccione la venta que desea retomar."),
    step("Toda la informaci\u00F3n se restaura autom\u00E1ticamente."),
    step("Contin\u00FAe agregando productos o proceda al pago."),
    spacer(),
    tipBox("Nota", "Las ventas suspendidas pueden ser retomadas por cualquier vendedor. Si un cliente regresa, cualquiera puede continuar la venta."),
    spacer(),

    heading2("4.2 Consultar ventas realizadas"),
    para("En el men\u00FA Ventas puede ver el historial de ventas:"),
    bullet("Filtrar por fecha"),
    bullet("Buscar por nombre de cliente"),
    bullet("Clasificar por estado"),
    spacer(),

    heading2("4.3 Ver detalle de una venta"),
    para("Haga clic en una venta para ver su informaci\u00F3n completa:"),
    bullet("Lista de productos (nombre, cantidad, precio unitario, subtotal)"),
    bullet("Descuentos y recargos aplicados"),
    bullet("M\u00E9todos de pago utilizados y montos"),
    bullet("Datos del cliente"),
    bullet("Fecha, hora y vendedor asignado"),
    spacer(),

    // ===== 5. GASTOS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("5. Registro de Gastos"),
    para("Registre los gastos operativos que ocurran durante su turno."),
    spacer(),

    heading2("5.1 Registrar un gasto"),
    step("En la barra lateral, seleccione Gastos."),
    step("Haga clic en \"Nuevo Gasto\"."),
    step("Ingrese la descripci\u00F3n (ej: compra de \u00FAtiles, env\u00EDo, etc.)."),
    step("Ingrese el monto."),
    step("Seleccione la fecha (por defecto: hoy)."),
    step("Guarde."),
    spacer(),

    heading2("5.2 Seleccionar categor\u00EDa"),
    para("Clasifique cada gasto en su categor\u00EDa correspondiente:"),
    bullet("Categor\u00EDa \u2014 Clasificaci\u00F3n principal (operativos, alquiler, sueldos, etc.)"),
    bullet("Subcategor\u00EDa \u2014 Clasificaci\u00F3n detallada (\u00FAtiles de oficina, limpieza, etc.)"),
    spacer(),
    tipBox("Nota", "Si el gasto se pag\u00F3 con efectivo de la caja registradora, active la opci\u00F3n \"Afecta Caja\". El saldo de la caja se actualizar\u00E1 autom\u00E1ticamente."),
    spacer(),

    // ===== 6. CONSULTA DE PRODUCTOS =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("6. Consulta de Productos"),
    para("Utilice estas funciones cuando necesite verificar informaci\u00F3n de un producto durante una venta."),
    spacer(),

    heading2("6.1 Buscar productos"),
    step("En la barra lateral, seleccione Productos."),
    step("En el campo de b\u00FAsqueda, ingrese nombre, c\u00F3digo o SKU."),
    step("Haga clic en el producto para ver su informaci\u00F3n detallada."),
    spacer(),
    para("Informaci\u00F3n disponible:"),
    bullet("Nombre, SKU, c\u00F3digo de barras"),
    bullet("Categor\u00EDa y subcategor\u00EDa"),
    bullet("Color, talle (para productos con variantes)"),
    bullet("Proveedor"),
    spacer(),

    heading2("6.2 Verificar stock"),
    para("En la vista detalle del producto, consulte el stock:"),
    bullet("Stock actual de su sucursal"),
    bullet("Stock en otras sucursales (si tiene permisos)"),
    spacer(),

    heading2("6.3 Verificar precios"),
    para("Consulte los precios del producto:"),
    bullet("Precio por tipo (Minorista, Mayorista, etc.)"),
    bullet("Descuentos vigentes"),
    spacer(),

    // ===== 7. CIERRE DE OPERACIONES =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("7. Cierre de Operaciones"),
    para("Al finalizar el d\u00EDa, debe cerrar la caja registradora antes de retirarse."),
    spacer(),

    heading2("7.1 Cerrar la Caja Registradora"),
    step("Verifique que no haya ventas suspendidas pendientes."),
    step("Haga clic en el \u00E1rea de caja en la barra superior."),
    step("Seleccione \"Cerrar Caja\"."),
    step("Se muestra el resumen de operaciones del d\u00EDa."),
    step("Revise el resumen y confirme el cierre."),
    spacer(),
    infoBox("Importante", "Al cerrar la caja, el saldo en efectivo se transfiere autom\u00E1ticamente a la Caja Fuerte de la sucursal."),
    spacer(),

    heading2("7.2 Revisi\u00F3n del cierre diario"),
    para("Despu\u00E9s del cierre, verifique:"),
    spacer(),
    infoTable("Concepto", "Qu\u00E9 verificar", [
      ["Cantidad de ventas", "Total de ventas realizadas hoy"],
      ["Total facturado", "Monto total de ventas del d\u00EDa"],
      ["Gastos", "Total de gastos registrados"],
      ["Por m\u00E9todo de pago", "Monto por efectivo, tarjeta, transferencia, etc."],
      ["Saldo de caja", "Saldo al cierre (debe ser 0 normalmente)"],
    ]),
    spacer(),

    para("Si hay diferencias en los montos, informe inmediatamente al administrador."),
    spacer(),

    // ===== AP\u00C9NDICE =====
    new Paragraph({ children: [new PageBreak()] }),
    heading1("Ap\u00E9ndice"),
    spacer(),

    heading2("A. Preguntas Frecuentes"),
    spacer(),

    heading3("El bot\u00F3n \"Pagar\" est\u00E1 deshabilitado"),
    para("No ha abierto la caja registradora. Haga clic en \"Iniciar Caja\" en la barra superior."),
    spacer(),

    heading3("No encuentro un producto en la b\u00FAsqueda"),
    para("(1) Verifique que est\u00E9 escribiendo correctamente el nombre o c\u00F3digo. (2) Es posible que el producto no est\u00E9 asignado a su sucursal. Consulte al administrador."),
    spacer(),

    heading3("El cliente quiere pagar despu\u00E9s"),
    para("Haga clic en \"Suspender\" para guardar la venta actual. Cuando regrese el cliente, ret\u00F3mela desde la lista de Ventas Suspendidas."),
    spacer(),

    heading3("El recibo no se imprime"),
    para("Verifique que el Print Agent est\u00E9 en ejecuci\u00F3n. Si persiste el problema, contacte al administrador."),
    spacer(),

    heading3("Ingres\u00E9 un monto incorrecto en el pago"),
    para("Si la venta a\u00FAn no se complet\u00F3, modifique el monto en la ventana de pago. Si ya se complet\u00F3, contacte al administrador."),
    spacer(),

    heading3("El sistema est\u00E1 lento o no responde"),
    para("(1) Verifique su conexi\u00F3n a Internet. (2) Actualice la p\u00E1gina (F5). (3) Si persiste, contacte al administrador."),
    spacer(),

    heading2("B. Soluci\u00F3n de Problemas"),
    spacer(),
    infoTable("Situaci\u00F3n", "Soluci\u00F3n", [
      ["Mensaje \"No existen cajas\"", "Solicite al administrador que configure caja y terminal"],
      ["Bot\u00F3n Pagar deshabilitado", "Abra la caja con Iniciar Caja"],
      ["Alerta de stock insuficiente", "Informe al administrador para reponer stock"],
      ["Error de permisos", "Solicite al administrador los permisos necesarios"],
      ["Error de red", "Verifique Internet y actualice la p\u00E1gina"],
    ]),
    spacer(),

    heading2("C. Glosario"),
    spacer(),
    infoTable("T\u00E9rmino", "Significado", [
      ["Nueva Venta", "Pantalla principal del punto de venta (POS)"],
      ["Pagar", "Proceder al cobro de la venta"],
      ["Generar Venta", "Completar y registrar la venta"],
      ["Suspender", "Pausar una venta para retomarla despu\u00E9s"],
      ["Iniciar Caja", "Abrir la caja registradora para operar"],
      ["Cerrar Caja", "Cerrar la caja al final del turno"],
      ["Venta R\u00E1pida", "Venta de productos sin c\u00F3digo registrado"],
      ["Gastos", "Registro de egresos operativos"],
      ["Recargo", "Cargo adicional sobre una venta"],
      ["Descuento", "Reducci\u00F3n del precio de venta"],
      ["Cliente", "Persona que realiza la compra"],
      ["Vendedor", "Persona a quien se atribuye la venta"],
      ["Producto", "Art\u00EDculo disponible para la venta"],
      ["Stock", "Cantidad disponible de un producto"],
      ["Sucursal", "Ubicaci\u00F3n f\u00EDsica de la tienda"],
    ]),
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

  const subtitleText = isKorean ? "\uD310\uB9E4\uC6D0 \uB9E4\uB274\uC5BC" : "Manual del Vendedor";
  const systemDesc = isKorean ? "\uD1B5\uD569 \uD310\uB9E4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C" : "Sistema Integral de Gesti\u00F3n de Ventas";
  const versionText = isKorean ? "\uBC84\uC804 1.0 \u2014 2026\uB144 3\uC6D4" : "Versi\u00F3n 1.0 \u2014 Marzo 2026";
  const headerText = isKorean ? "VentaGO \u2014 \uD310\uB9E4\uC6D0 \uB9E4\uB274\uC5BC" : "VentaGO \u2014 Manual del Vendedor";
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
            children: [new TextRun({ text: "VentaGO", size: 72, bold: true, font: "Arial", color: PRIMARY })],
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

// ====================== 실행 ======================
async function main() {
  const basePath = "/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/manuales";

  const koDoc = buildDocument("ko");
  const koBuffer = await Packer.toBuffer(koDoc);
  const koPath = `${basePath}/Manual_Vendedor_VentaGO_KO.docx`;
  fs.writeFileSync(koPath, koBuffer);
  console.log(`[KO] \uC0DD\uC131 \uC644\uB8CC: ${koPath} (${(koBuffer.length / 1024).toFixed(1)} KB)`);

  const esDoc = buildDocument("es");
  const esBuffer = await Packer.toBuffer(esDoc);
  const esPath = `${basePath}/Manual_Vendedor_VentaGO_ES.docx`;
  fs.writeFileSync(esPath, esBuffer);
  console.log(`[ES] Generado: ${esPath} (${(esBuffer.length / 1024).toFixed(1)} KB)`);
}

main().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
