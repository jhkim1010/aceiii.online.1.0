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

// 유틸: 제목
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
function tipBox(text) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [9360],
    rows: [new TableRow({ children: [new TableCell({
      borders, width: { size: 9360, type: WidthType.DXA },
      shading: { fill: "FFF3CD", type: ShadingType.CLEAR },
      margins: { top: 100, bottom: 100, left: 200, right: 200 },
      children: [new Paragraph({ children: [
        new TextRun({ text: "\u26A0 Consejo: ", bold: true, size: 20, font: "Arial", color: "856404" }),
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

// 키보드 단축키 테이블
function shortcutTable(rows) {
  return new Table({
    width: { size: 9360, type: WidthType.DXA },
    columnWidths: [2800, 6560],
    rows: [
      new TableRow({ children: [
        new TableCell({ borders, width: { size: 2800, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "Tecla", bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
        new TableCell({ borders, width: { size: 6560, type: WidthType.DXA }, shading: { fill: PRIMARY, type: ShadingType.CLEAR }, margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun({ text: "Acci\u00F3n", bold: true, size: 20, font: "Arial", color: "FFFFFF" })] })] }),
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

// ====================== 문서 구성 ======================

const doc = new Document({
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
          children: [new TextRun({ text: "ACE III 2.0", size: 72, bold: true, font: "Arial", color: PRIMARY })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 100 },
          children: [new TextRun({ text: "Ver. Online", size: 36, font: "Arial", color: GRAY })],
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
          children: [new TextRun({ text: "Manual de Usuario", size: 48, bold: true, font: "Arial", color: DARK })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 100 },
          children: [new TextRun({ text: "Sistema de Punto de Venta", size: 28, font: "Arial", color: GRAY })],
        }),
        spacer(), spacer(), spacer(), spacer(), spacer(), spacer(), spacer(),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: "Versi\u00F3n 2.0 \u2014 Marzo 2026", size: 22, font: "Arial", color: GRAY })],
        }),
        new Paragraph({ children: [new PageBreak()] }),
      ],
    },
    // ===== Contenido principal =====
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
              new TextRun({ text: "ACE III 2.0 \u2014 Manual de Usuario", size: 18, font: "Arial", color: GRAY }),
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
              new TextRun({ text: "P\u00E1gina ", size: 18, font: "Arial", color: GRAY }),
              new TextRun({ children: [PageNumber.CURRENT], size: 18, font: "Arial", color: GRAY }),
            ],
          })],
        }),
      },
      children: [
        // ===== 1. INTRODUCCIÓN =====
        heading1("1. Introducci\u00F3n"),
        para("Bienvenido a ACE III 2.0, su sistema integral de Punto de Venta (POS) dise\u00F1ado para gestionar ventas, productos, clientes, inventario y reportes de manera eficiente."),
        para("Este manual le guiar\u00E1 a trav\u00E9s de todas las funcionalidades del sistema, organizado por los cuatro m\u00F3dulos principales:"),
        spacer(),
        bullet("Ventas (V) \u2014 Punto de venta, gesti\u00F3n de clientes y gastos"),
        bullet("PControl (P) \u2014 Gesti\u00F3n de productos, precios e inventario"),
        bullet("Admin (A) \u2014 Administraci\u00F3n de tiendas, usuarios y cajas"),
        bullet("Reportes (R) \u2014 Informes de ventas, stock y productos"),
        spacer(),

        heading2("1.1 Requisitos del sistema"),
        bullet("Navegador web moderno (Chrome, Firefox, Edge, Safari)"),
        bullet("Conexi\u00F3n a Internet estable"),
        bullet("Resoluci\u00F3n de pantalla m\u00EDnima recomendada: 1280 x 720"),
        spacer(),

        heading2("1.2 Inicio de sesi\u00F3n"),
        step("Abra su navegador e ingrese la direcci\u00F3n del sistema."),
        step("Ingrese su correo electr\u00F3nico o nombre de usuario."),
        step("Ingrese su contrase\u00F1a."),
        step("Haga clic en \"Iniciar Sesi\u00F3n\"."),
        spacer(),
        tipBox("Si olvid\u00F3 su contrase\u00F1a, haga clic en \"Olvidaste tu contrase\u00F1a\" para recuperarla."),
        spacer(),

        heading2("1.3 Navegaci\u00F3n general"),
        para("La interfaz se divide en dos \u00E1reas principales:"),
        bullet("Barra lateral (Sidebar) \u2014 Men\u00FA de navegaci\u00F3n con los m\u00F3dulos y submen\u00FAs"),
        bullet("\u00C1rea de contenido \u2014 Pantalla principal donde se muestra cada funci\u00F3n"),
        spacer(),
        para("El m\u00F3dulo activo se resalta con un color m\u00E1s intenso en la barra lateral. Puede fijar o auto-ocultar la barra lateral con el \u00EDcono de pin en la parte superior."),
        spacer(),

        // ===== 2. VENTAS =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("2. M\u00F3dulo de Ventas"),
        para("El m\u00F3dulo de Ventas es el coraz\u00F3n del sistema POS. Aqu\u00ED realiza todas las operaciones de venta, gestiona clientes y controla gastos."),
        spacer(),

        heading2("2.1 Dashboard de Ventas"),
        para("El panel principal muestra un resumen en tiempo real:"),
        bullet("Ventas del d\u00EDa \u2014 Total de ventas con comparaci\u00F3n respecto al d\u00EDa anterior"),
        bullet("Ingresos del d\u00EDa \u2014 Monto total de ingresos con gr\u00E1fico"),
        bullet("Gastos del d\u00EDa \u2014 Control de egresos"),
        bullet("Descuentos aplicados \u2014 Total de descuentos otorgados"),
        bullet("Facturas pendientes \u2014 Cantidad de facturas por cobrar"),
        bullet("Total de clientes \u2014 N\u00FAmero de clientes registrados"),
        bullet("Tendencia semanal \u2014 Gr\u00E1fico de ventas de la semana"),
        bullet("Productos m\u00E1s vendidos \u2014 Ranking de los art\u00EDculos m\u00E1s populares"),
        spacer(),

        heading2("2.2 Nueva Venta (POS)"),
        para("La pantalla principal de ventas se divide en dos columnas:"),
        spacer(),
        heading3("Columna izquierda: Cliente y Productos"),
        para("Informaci\u00F3n de Cliente (compacto):"),
        bullet("En modo compacto se muestran 4 campos en una l\u00EDnea: Documento, Nombre, Vendedor y Provincia"),
        bullet("Al ingresar 9 o m\u00E1s d\u00EDgitos en el campo Documento, el formulario se expande autom\u00E1ticamente mostrando todos los campos del cliente"),
        spacer(),
        infoBox("Modo compacto", "Documento < 9 d\u00EDgitos: solo 4 campos visibles. M\u00E1s espacio para la lista de productos."),
        spacer(),
        para("Informaci\u00F3n de Cliente (expandido):"),
        bullet("L\u00EDnea 1: Documento (CUIT/DNI), Nombre completo, Nombre de fantas\u00EDa"),
        bullet("L\u00EDnea 2: Vendedor asignado, Condici\u00F3n IVA, Transporte, Tel\u00E9fono"),
        bullet("L\u00EDnea 3: Direcci\u00F3n, Localidad, Provincia, Pa\u00EDs"),
        bullet("L\u00EDnea 4: Observaciones, Email, Bot\u00F3n Reset, Bot\u00F3n Nuevo/Editar"),
        spacer(),

        heading3("B\u00FAsqueda y selecci\u00F3n de productos"),
        step("En el campo de b\u00FAsqueda, escriba el nombre, c\u00F3digo o SKU del producto."),
        step("Seleccione el producto de la lista desplegable."),
        step("Ajuste la cantidad deseada."),
        step("Seleccione el tipo de precio si hay m\u00FAltiples opciones."),
        step("El producto se agrega autom\u00E1ticamente a la tabla de art\u00EDculos."),
        spacer(),

        heading3("Venta R\u00E1pida (sin c\u00F3digo)"),
        para("Para vender productos sin c\u00F3digo registrado:"),
        step("Active el switch \"Venta R\u00E1pida\" en la secci\u00F3n de productos."),
        step("Ingrese el nombre del producto manualmente."),
        step("Ingrese el precio unitario."),
        step("Ajuste la cantidad."),
        step("Haga clic en \"Agregar\" para a\u00F1adir a la lista."),
        spacer(),
        tipBox("La Venta R\u00E1pida utiliza un producto gen\u00E9rico interno. El nombre personalizado aparece en la factura."),
        spacer(),

        heading3("Tabla de art\u00EDculos"),
        para("Muestra los productos agregados con columnas:"),
        bullet("Cantidad \u2014 Unidades del producto"),
        bullet("Producto \u2014 Nombre y tipo de precio"),
        bullet("Precio \u2014 Precio unitario"),
        bullet("Total \u2014 Precio x Cantidad"),
        bullet("Acciones \u2014 Editar o eliminar el art\u00EDculo"),
        spacer(),

        heading3("Proceso de pago"),
        step("Verifique que tiene una caja y terminal seleccionados (Iniciar Caja)."),
        step("Agregue todos los productos deseados."),
        step("Haga clic en \"Pagar\" (o presione F11)."),
        step("Seleccione el/los m\u00E9todo(s) de pago (Efectivo, Tarjeta, Transferencia, etc.)."),
        step("Ingrese el monto para cada m\u00E9todo de pago."),
        step("Cuando el total pagado coincida con el total de la factura, haga clic en \"Generar Venta\"."),
        spacer(),

        shortcutTable([
          ["F11", "Abrir/confirmar modal de pago"],
          ["Esc", "Limpiar toda la venta actual"],
        ]),
        spacer(),

        heading3("Columna derecha: Lista de clientes"),
        para("Muestra la lista de clientes registrados para b\u00FAsqueda r\u00E1pida. Al seleccionar un cliente, sus datos se cargan autom\u00E1ticamente en el formulario."),
        spacer(),

        heading2("2.3 Historial de Ventas"),
        para("Acceda al listado completo de todas las ventas realizadas:"),
        bullet("Filtrar por fecha, estado o cliente"),
        bullet("Ver detalle completo de cada venta"),
        bullet("Informaci\u00F3n del cliente, productos, m\u00E9todos de pago"),
        bullet("Descuentos y recargos aplicados"),
        spacer(),

        heading2("2.4 Gesti\u00F3n de Gastos"),
        para("Registre y controle los gastos del negocio:"),
        step("Vaya a la secci\u00F3n Gastos."),
        step("Haga clic en \"Nuevo Gasto\"."),
        step("Complete la descripci\u00F3n, monto, fecha y categor\u00EDa."),
        step("Seleccione la sucursal correspondiente."),
        step("Guarde el gasto."),
        spacer(),

        heading2("2.5 Configuraci\u00F3n de Ventas"),
        para("Personalice los par\u00E1metros de venta:"),
        bullet("M\u00E9todos de pago \u2014 Crear y gestionar tipos de pago (efectivo, tarjeta, transferencia, cheque)"),
        bullet("Descuentos \u2014 Configurar reglas de descuento (porcentaje o monto fijo)"),
        bullet("Recargos \u2014 Definir recargos adicionales"),
        bullet("Categor\u00EDas de gasto \u2014 Organizar gastos por categor\u00EDa"),
        bullet("Subcategor\u00EDas de gasto \u2014 Subcategorizar para mayor control"),
        spacer(),

        // ===== 3. PCONTROL =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("3. M\u00F3dulo de Productos (PControl)"),
        para("Gestione todo el cat\u00E1logo de productos, precios, categor\u00EDas e inventario."),
        spacer(),

        heading2("3.1 Dashboard de Productos"),
        para("Vista r\u00E1pida del estado de su inventario:"),
        bullet("Productos con stock bajo (menor al m\u00EDnimo configurado)"),
        bullet("Productos reci\u00E9n creados"),
        bullet("Alertas de stock"),
        bullet("Accesos directos a configuraciones"),
        spacer(),

        heading2("3.2 Gesti\u00F3n de Productos"),
        para("Administre su cat\u00E1logo completo de productos:"),
        spacer(),
        heading3("Crear un nuevo producto"),
        step("Vaya a Productos y haga clic en \"Nuevo Producto\"."),
        step("Complete los datos b\u00E1sicos: nombre, SKU, c\u00F3digo de barras."),
        step("Seleccione la categor\u00EDa y subcategor\u00EDa."),
        step("Asigne un proveedor (opcional)."),
        step("Configure los precios seg\u00FAn los tipos de precio disponibles."),
        step("Defina el stock inicial."),
        step("Guarde el producto."),
        spacer(),

        heading3("Variantes de producto"),
        para("Los productos pueden tener variantes por:"),
        bullet("Colores \u2014 Diferentes opciones de color"),
        bullet("Talles/Tallas \u2014 Diferentes medidas"),
        para("Los productos con variantes se denominan \"productos padre\" y contienen sub-productos para cada combinaci\u00F3n."),
        spacer(),

        heading2("3.3 Gesti\u00F3n de Precios"),
        para("Configure m\u00FAltiples tipos de precio para cada producto:"),
        bullet("Tipo de precio \u2014 Crear categor\u00EDas (Minorista, Mayorista, Especial, etc.)"),
        bullet("Reglas por cantidad \u2014 Precios escalonados seg\u00FAn volumen de compra"),
        bullet("Modificador r\u00E1pido \u2014 Ajuste masivo de precios por porcentaje"),
        bullet("Importaci\u00F3n/Exportaci\u00F3n \u2014 Manejo masivo de precios via Excel"),
        spacer(),

        heading2("3.4 Configuraci\u00F3n de Productos"),
        para("Defina las dimensiones y clasificaciones de su cat\u00E1logo:"),
        spacer(),

        heading3("Categor\u00EDas y Subcategor\u00EDas"),
        step("Vaya a Configuraci\u00F3n de Productos."),
        step("En la pesta\u00F1a \"Categor\u00EDas\", cree las categor\u00EDas principales (ej: Ropa, Calzado, Accesorios)."),
        step("En \"Subcategor\u00EDas\", cree divisiones m\u00E1s espec\u00EDficas (ej: Remeras, Pantalones, Zapatillas)."),
        step("Configure la cantidad de d\u00EDgitos para los c\u00F3digos autom\u00E1ticos."),
        spacer(),

        heading3("Otras configuraciones"),
        bullet("Proveedores \u2014 Gestione su lista de proveedores"),
        bullet("Colores \u2014 Defina la paleta de colores disponibles"),
        bullet("Talles \u2014 Configure las opciones de talle"),
        bullet("Temporadas \u2014 Clasifique por temporada (Primavera/Verano, Oto\u00F1o/Invierno)"),
        bullet("Origen \u2014 Pa\u00EDs de origen de los productos"),
        spacer(),
        tipBox("Cada dimensi\u00F3n (categor\u00EDa, color, talle) tiene un n\u00FAmero de d\u00EDgitos configurable que se usa para generar c\u00F3digos de producto autom\u00E1ticos."),
        spacer(),

        // ===== 4. ADMIN =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("4. M\u00F3dulo de Administraci\u00F3n"),
        para("Gestione la configuraci\u00F3n general del sistema, tiendas, usuarios, sucursales y cajas registradoras."),
        spacer(),

        heading2("4.1 Gesti\u00F3n de Tiendas"),
        para("Administre las tiendas del sistema:"),
        bullet("Crear nueva tienda con datos fiscales (CUIT, r\u00E9gimen tributario)"),
        bullet("Editar informaci\u00F3n de la tienda"),
        bullet("Ver usuarios asignados a cada tienda"),
        bullet("Gestionar sucursales por tienda"),
        bullet("Activar o desactivar tiendas"),
        spacer(),

        heading2("4.2 Gesti\u00F3n de Usuarios"),
        para("Administre los usuarios que acceden al sistema:"),
        spacer(),
        heading3("Crear un nuevo usuario"),
        step("Vaya a Usuarios y haga clic en \"Nuevo Usuario\"."),
        step("Ingrese nombre, correo electr\u00F3nico y nombre de usuario."),
        step("Asigne un rol (Administrador, Gerente, Vendedor, etc.)."),
        step("Seleccione la tienda a la que pertenece."),
        step("Establezca la contrase\u00F1a."),
        step("Guarde el usuario."),
        spacer(),

        heading3("Roles disponibles"),
        bullet("Superadmin \u2014 Acceso total a todas las funciones y tiendas"),
        bullet("Admin \u2014 Gesti\u00F3n completa de una tienda espec\u00EDfica"),
        bullet("Gerente \u2014 Acceso administrativo limitado"),
        bullet("Vendedor \u2014 Acceso al m\u00F3dulo de ventas"),
        bullet("Roles personalizados \u2014 Permisos granulares configurables"),
        spacer(),

        heading2("4.3 Sucursales"),
        para("Cada tienda puede tener m\u00FAltiples sucursales:"),
        bullet("Crear y editar sucursales con direcci\u00F3n y responsable"),
        bullet("Asignar cajas registradoras a cada sucursal"),
        bullet("Asignar terminales de pago a cada caja"),
        bullet("Activar o desactivar sucursales"),
        spacer(),

        heading2("4.4 Cajas Registradoras"),
        para("Gestione las operaciones de caja:"),
        spacer(),
        heading3("Iniciar Caja"),
        step("Al ingresar al sistema, haga clic en \"Iniciar Caja\" en la barra superior."),
        step("Seleccione la Caja y Terminal asignados a su sucursal."),
        step("Confirme la apertura de caja."),
        spacer(),
        infoBox("Importante", "Debe iniciar caja antes de poder realizar ventas. Sin caja activa, el bot\u00F3n \"Pagar\" estar\u00E1 deshabilitado."),
        spacer(),

        heading3("Operaciones de Caja"),
        bullet("Dep\u00F3sitos \u2014 Registrar ingresos de efectivo a la caja"),
        bullet("Retiros \u2014 Registrar extracciones de efectivo"),
        bullet("Resumen \u2014 Ver balance actual, total de ingresos y egresos"),
        bullet("Historial \u2014 Lista completa de operaciones del d\u00EDa"),
        spacer(),

        heading3("Control de Cajas"),
        para("Vista administrativa de todas las cajas de la tienda:"),
        bullet("Estado de cada caja (abierta/cerrada)"),
        bullet("Balance actual"),
        bullet("Detalle de transacciones"),
        bullet("Apertura y cierre de cajas"),
        spacer(),

        heading2("4.5 Auditor\u00EDa"),
        para("Revise el registro de actividades del sistema:"),
        bullet("Historial de acciones de cada usuario"),
        bullet("Cambios realizados en el sistema"),
        bullet("Filtros por fecha y tipo de acci\u00F3n"),
        bullet("B\u00FAsqueda de eventos espec\u00EDficos"),
        spacer(),

        heading2("4.6 Permisos"),
        para("Configure los permisos de acceso de forma granular:"),
        bullet("Asignar m\u00F3dulos espec\u00EDficos a cada rol"),
        bullet("Habilitar/deshabilitar funciones individuales"),
        bullet("Control de acceso a nivel de acci\u00F3n (ver, crear, editar, eliminar)"),
        spacer(),

        // ===== 5. REPORTES =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("5. M\u00F3dulo de Reportes"),
        para("Genere informes detallados para analizar el rendimiento de su negocio."),
        spacer(),

        heading2("5.1 Reportes de Ventas"),
        para("Analice sus ventas con filtros avanzados:"),
        bullet("Filtrar por rango de fechas"),
        bullet("B\u00FAsqueda por producto o cliente"),
        bullet("Desglose de cada venta con art\u00EDculos y pagos"),
        bullet("Exportar a Excel para an\u00E1lisis externo"),
        bullet("Paginaci\u00F3n para grandes vol\u00FAmenes de datos"),
        spacer(),

        heading2("5.2 Reportes de Stock"),
        para("Controle su inventario:"),
        bullet("Niveles de stock por sucursal"),
        bullet("Productos con stock bajo o agotados"),
        bullet("Historial de movimientos de stock"),
        bullet("Exportar a Excel"),
        spacer(),

        heading2("5.3 Reportes de Productos"),
        para("Analice el rendimiento de su cat\u00E1logo:"),
        bullet("Cantidad vendida por producto"),
        bullet("Productos m\u00E1s y menos vendidos"),
        bullet("An\u00E1lisis por per\u00EDodo"),
        bullet("Exportar a Excel"),
        spacer(),

        // ===== 6. TALLERES =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("6. M\u00F3dulo de Talleres"),
        para("Gestione la subcontrataci\u00F3n de trabajo a talleres externos."),
        spacer(),

        heading2("6.1 Proveedores de Taller"),
        bullet("Registre talleres/proveedores de servicios"),
        bullet("Gestione informaci\u00F3n de contacto"),
        bullet("Controle el estado de cada proveedor"),
        spacer(),

        heading2("6.2 Pedidos de Subcontrataci\u00F3n"),
        bullet("Crear \u00F3rdenes de trabajo para talleres"),
        bullet("Seguimiento del estado de cada pedido"),
        bullet("Asignar pedidos a talleres espec\u00EDficos"),
        bullet("Controlar entregas y liquidaciones"),
        spacer(),

        // ===== 7. ASISTENTE AI =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("7. Asistente Inteligente (AI)"),
        para("ACE III 2.0 incluye un asistente virtual integrado que puede ayudarle con cualquier consulta sobre el uso del sistema."),
        spacer(),

        heading2("7.1 C\u00F3mo usar el Asistente"),
        step("Haga clic en el \u00EDcono de chat flotante en la esquina inferior derecha."),
        step("Escriba su pregunta en espa\u00F1ol."),
        step("Presione Enter o haga clic en el bot\u00F3n de env\u00EDo."),
        step("El asistente responder\u00E1 con informaci\u00F3n relevante."),
        spacer(),

        heading3("Ejemplos de preguntas"),
        bullet("\"\u00BFC\u00F3mo hago una venta r\u00E1pida sin c\u00F3digo?\""),
        bullet("\"\u00BFC\u00F3mo inicio la caja registradora?\""),
        bullet("\"\u00BFC\u00F3mo creo un nuevo producto?\""),
        bullet("\"\u00BFC\u00F3mo aplico un descuento a una venta?\""),
        bullet("\"\u00BFC\u00F3mo exporto el reporte de ventas a Excel?\""),
        spacer(),
        tipBox("El asistente aprende de la documentaci\u00F3n del sistema. Cuanto m\u00E1s espec\u00EDfica sea su pregunta, mejor ser\u00E1 la respuesta."),
        spacer(),

        // ===== 8. PREGUNTAS FRECUENTES =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("8. Preguntas Frecuentes"),
        spacer(),

        heading3("\u00BFPor qu\u00E9 no puedo hacer una venta?"),
        para("Verifique que: (1) Tiene una caja y terminal iniciados, (2) Ha seleccionado un cliente, (3) Ha agregado al menos un producto, (4) El total pagado coincide con el total de la factura."),
        spacer(),

        heading3("\u00BFQu\u00E9 significa \"No existen cajas asociadas a esta sucursal\"?"),
        para("Su sucursal no tiene cajas registradoras configuradas. Contacte al administrador para que cree una caja y terminal en la secci\u00F3n Admin > Sucursales."),
        spacer(),

        heading3("\u00BFC\u00F3mo cambio mi contrase\u00F1a?"),
        para("Vaya a su Perfil de usuario y utilice la opci\u00F3n de cambiar contrase\u00F1a."),
        spacer(),

        heading3("\u00BFPuedo vender sin c\u00F3digo de producto?"),
        para("S\u00ED, utilice la funci\u00F3n \"Venta R\u00E1pida\". Active el switch en la secci\u00F3n de productos e ingrese manualmente el nombre y precio del art\u00EDculo."),
        spacer(),

        heading3("\u00BFC\u00F3mo exporto datos a Excel?"),
        para("En las secciones de Reportes, encontrar\u00E1 un bot\u00F3n de exportaci\u00F3n a Excel. Haga clic para descargar los datos filtrados."),
        spacer(),

        heading3("\u00BFQu\u00E9 hago si el sistema est\u00E1 lento?"),
        para("Verifique su conexi\u00F3n a Internet. Si el problema persiste, limpie la cach\u00E9 del navegador o contacte al soporte t\u00E9cnico."),
        spacer(),

        // ===== SOPORTE =====
        new Paragraph({ children: [new PageBreak()] }),
        heading1("9. Soporte T\u00E9cnico"),
        para("Si necesita ayuda adicional:"),
        spacer(),
        bullet("Use el Asistente AI integrado para consultas r\u00E1pidas"),
        bullet("Contacte al administrador de su tienda"),
        bullet("Env\u00EDe un correo al equipo de soporte"),
        spacer(),
        spacer(),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { before: 400 },
          border: { top: { style: BorderStyle.SINGLE, size: 4, color: PRIMARY, space: 20 } },
          children: [new TextRun({ text: "ACE III 2.0 \u2014 Sistema de Punto de Venta", size: 20, font: "Arial", color: GRAY, italics: true })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: "\u00A9 2026 \u2014 Todos los derechos reservados", size: 18, font: "Arial", color: GRAY })],
        }),
      ],
    },
  ],
});

// 생성
const outputPath = "/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/Manual_Usuario_ACE_III_2.0.docx";
Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync(outputPath, buffer);
  console.log("Manual generado: " + outputPath);
  console.log("Tama\u00F1o: " + (buffer.length / 1024).toFixed(1) + " KB");
});
