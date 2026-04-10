import { useState, useMemo, useCallback } from "react";
import {
  Package,
  TrendingUp,
  TrendingDown,
  AlertTriangle,
  Plus,
  Search,
  Filter,
  ChevronRight,
  DollarSign,
  Truck,
  BarChart3,
  Eye,
  Edit,
  ArrowUpCircle,
  ArrowDownCircle,
  Bell,
  Layers,
  Scissors,
  CircleDot,
  Shirt,
  X,
  Check,
  Clock,
  CreditCard,
  FileText,
  ChevronDown,
  MoreVertical,
  ArrowRight,
  Minus,
  Star,
  Phone,
  Mail,
  MapPin,
  Calendar,
  Receipt,
  Wallet,
} from "lucide-react";

// ============================================================
// MATERIAL PRIMA - 의류업 원자재 관리 시스템 UI/UX 프로토타입
// 소형 생산업자 최적화 카드형 대시보드
// ============================================================

// 카테고리 아이콘 매핑
const CATEGORY_ICONS = {
  tela: Shirt,
  boton: CircleDot,
  cierre: Layers,
  hilo: Scissors,
  accesorio: Package,
};

const CATEGORY_COLORS = {
  tela: "#6366f1",
  boton: "#f59e0b",
  cierre: "#10b981",
  hilo: "#ef4444",
  accesorio: "#8b5cf6",
};

const CATEGORY_LABELS = {
  tela: "Tela / 원단",
  boton: "Botón / 단추",
  cierre: "Cierre / 지퍼",
  hilo: "Hilo / 실",
  accesorio: "Accesorio / 부자재",
};

// 샘플 데이터
const SAMPLE_MATERIALS = [
  {
    id: 1,
    code: "TEL-001",
    name: "Algodón Premium",
    category: "tela",
    unit: "m",
    currentStock: 45.5,
    minStock: 20,
    standardPrice: 8500,
    lastPrice: 8200,
    supplier: "Textiles del Sur",
    color: "Blanco",
    origin: "Colombia",
    quality: "Premium",
    lastEntry: "2026-04-08",
    status: "normal",
  },
  {
    id: 2,
    code: "TEL-002",
    name: "Poliéster Stretch",
    category: "tela",
    unit: "m",
    currentStock: 12.0,
    minStock: 15,
    standardPrice: 6200,
    lastPrice: 6500,
    supplier: "ImportTex",
    color: "Negro",
    origin: "China",
    quality: "Estándar",
    lastEntry: "2026-04-02",
    status: "low",
  },
  {
    id: 3,
    code: "BOT-001",
    name: "Botón Nácar 18mm",
    category: "boton",
    unit: "unid",
    currentStock: 2400,
    minStock: 500,
    standardPrice: 120,
    lastPrice: 115,
    supplier: "Botones Express",
    lastEntry: "2026-04-05",
    status: "normal",
  },
  {
    id: 4,
    code: "CIE-001",
    name: "Cierre Metálico 20cm",
    category: "cierre",
    unit: "unid",
    currentStock: 85,
    minStock: 100,
    standardPrice: 950,
    lastPrice: 980,
    supplier: "YKK Distribuidora",
    lastEntry: "2026-03-28",
    status: "critical",
  },
  {
    id: 5,
    code: "HIL-001",
    name: "Hilo Poliéster #40",
    category: "hilo",
    unit: "cono",
    currentStock: 30,
    minStock: 10,
    standardPrice: 3500,
    lastPrice: 3400,
    supplier: "HiloSur",
    color: "Blanco",
    lastEntry: "2026-04-09",
    status: "normal",
  },
  {
    id: 6,
    code: "TEL-003",
    name: "Denim 12oz",
    category: "tela",
    unit: "m",
    currentStock: 0,
    minStock: 10,
    standardPrice: 12000,
    lastPrice: 11800,
    supplier: "Textiles del Sur",
    color: "Azul índigo",
    origin: "Brasil",
    quality: "Premium",
    lastEntry: "2026-03-15",
    status: "out",
  },
  {
    id: 7,
    code: "ACC-001",
    name: "Etiqueta Tejida Logo",
    category: "accesorio",
    unit: "unid",
    currentStock: 5000,
    minStock: 1000,
    standardPrice: 80,
    lastPrice: 75,
    supplier: "EtiquetasPro",
    lastEntry: "2026-04-01",
    status: "normal",
  },
  {
    id: 8,
    code: "BOT-002",
    name: "Botón Metálico Jeans",
    category: "boton",
    unit: "unid",
    currentStock: 320,
    minStock: 300,
    standardPrice: 250,
    lastPrice: 260,
    supplier: "Botones Express",
    lastEntry: "2026-04-03",
    status: "low",
  },
];

const SAMPLE_SUPPLIERS = [
  {
    id: 1,
    name: "Textiles del Sur",
    contact: "María González",
    phone: "+57 311 234 5678",
    email: "maria@textilesdelsur.com",
    address: "Calle 45 #12-34, Medellín",
    totalDebt: 2450000,
    paidAmount: 8200000,
    totalOrders: 24,
    rating: 4.5,
    lastPayment: "2026-04-05",
    materials: ["TEL-001", "TEL-003"],
  },
  {
    id: 2,
    name: "Botones Express",
    contact: "Carlos Pérez",
    phone: "+57 300 876 5432",
    email: "ventas@botonesexpress.com",
    address: "Av. Industrial 789, Bogotá",
    totalDebt: 380000,
    paidAmount: 1560000,
    totalOrders: 12,
    rating: 4.2,
    lastPayment: "2026-04-02",
    materials: ["BOT-001", "BOT-002"],
  },
  {
    id: 3,
    name: "YKK Distribuidora",
    contact: "Ana Rodríguez",
    phone: "+57 315 111 2222",
    email: "ana@ykkdist.com",
    address: "Zona Franca, Barranquilla",
    totalDebt: 890000,
    paidAmount: 3200000,
    totalOrders: 8,
    rating: 4.8,
    lastPayment: "2026-03-28",
    materials: ["CIE-001"],
  },
  {
    id: 4,
    name: "ImportTex",
    contact: "Li Wei",
    phone: "+57 320 555 6666",
    email: "li@importtex.co",
    address: "Centro Com. San Andresito, Cali",
    totalDebt: 1200000,
    paidAmount: 4500000,
    totalOrders: 15,
    rating: 3.8,
    lastPayment: "2026-04-01",
    materials: ["TEL-002"],
  },
];

const SAMPLE_MOVEMENTS = [
  { id: 1, date: "2026-04-09", type: "entrada", materialCode: "HIL-001", materialName: "Hilo Poliéster #40", quantity: 10, unit: "cono", supplier: "HiloSur", unitPrice: 3400, total: 34000 },
  { id: 2, date: "2026-04-08", type: "entrada", materialCode: "TEL-001", materialName: "Algodón Premium", quantity: 20, unit: "m", supplier: "Textiles del Sur", unitPrice: 8200, total: 164000 },
  { id: 3, date: "2026-04-08", type: "salida", materialCode: "TEL-001", materialName: "Algodón Premium", quantity: 8.5, unit: "m", reference: "OP-2026-042", total: null },
  { id: 4, date: "2026-04-07", type: "salida", materialCode: "BOT-001", materialName: "Botón Nácar 18mm", quantity: 200, unit: "unid", reference: "OP-2026-041", total: null },
  { id: 5, date: "2026-04-05", type: "entrada", materialCode: "BOT-001", materialName: "Botón Nácar 18mm", quantity: 1000, unit: "unid", supplier: "Botones Express", unitPrice: 115, total: 115000 },
  { id: 6, date: "2026-04-03", type: "entrada", materialCode: "BOT-002", materialName: "Botón Metálico Jeans", quantity: 500, unit: "unid", supplier: "Botones Express", unitPrice: 260, total: 130000 },
  { id: 7, date: "2026-04-02", type: "salida", materialCode: "TEL-002", materialName: "Poliéster Stretch", quantity: 15, unit: "m", reference: "OP-2026-039", total: null },
];

const SAMPLE_PAYMENTS = [
  { id: 1, date: "2026-04-05", supplier: "Textiles del Sur", amount: 500000, method: "Transferencia", reference: "TRF-0412", note: "Abono parcial factura #1023" },
  { id: 2, date: "2026-04-02", supplier: "Botones Express", amount: 245000, method: "Efectivo", reference: "EFE-0089", note: "Pago total factura #456" },
  { id: 3, date: "2026-04-01", supplier: "ImportTex", amount: 300000, method: "Transferencia", reference: "TRF-0408", note: "Abono factura #789" },
  { id: 4, date: "2026-03-28", supplier: "YKK Distribuidora", amount: 450000, method: "Cheque", reference: "CHQ-0034", note: "Pago factura #321" },
];

// 금액 포맷
const formatCurrency = (amount) => {
  if (amount == null) return "-";
  return `$${amount.toLocaleString("es-CO")}`;
};

// ============================================================
// 서브 컴포넌트들
// ============================================================

// KPI 카드
const KpiCard = ({ icon: Icon, label, value, subValue, color, trend }) => (
  <div
    style={{
      background: "white",
      borderRadius: 12,
      padding: "16px 20px",
      boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
      display: "flex",
      alignItems: "center",
      gap: 14,
      flex: 1,
      minWidth: 200,
    }}
  >
    <div
      style={{
        width: 44,
        height: 44,
        borderRadius: 10,
        background: `${color}15`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
      }}
    >
      <Icon size={22} color={color} />
    </div>
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 12, color: "#94a3b8", fontWeight: 500 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 700, color: "#1e293b", lineHeight: 1.2 }}>{value}</div>
      {subValue && (
        <div style={{ fontSize: 11, color: trend === "up" ? "#ef4444" : "#10b981", display: "flex", alignItems: "center", gap: 2 }}>
          {trend === "up" ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
          {subValue}
        </div>
      )}
    </div>
  </div>
);

// 상태 배지
const StatusBadge = ({ status }) => {
  const config = {
    normal: { label: "Normal", bg: "#dcfce7", color: "#16a34a" },
    low: { label: "Bajo", bg: "#fef3c7", color: "#d97706" },
    critical: { label: "Crítico", bg: "#fee2e2", color: "#dc2626" },
    out: { label: "Agotado", bg: "#f1f5f9", color: "#64748b" },
  };
  const c = config[status] || config.normal;

  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 4,
        padding: "3px 10px",
        borderRadius: 20,
        fontSize: 11,
        fontWeight: 600,
        background: c.bg,
        color: c.color,
      }}
    >
      <span style={{ width: 6, height: 6, borderRadius: "50%", background: c.color }} />
      {c.label}
    </span>
  );
};

// 카테고리 필터 칩
const CategoryChip = ({ category, active, onClick, count }) => {
  const Icon = CATEGORY_ICONS[category];
  const color = CATEGORY_COLORS[category];
  const label = CATEGORY_LABELS[category];

  return (
    <button
      onClick={onClick}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 6,
        padding: "6px 14px",
        borderRadius: 20,
        border: active ? `2px solid ${color}` : "1px solid #e2e8f0",
        background: active ? `${color}10` : "white",
        cursor: "pointer",
        fontSize: 13,
        fontWeight: active ? 600 : 400,
        color: active ? color : "#64748b",
        transition: "all 0.15s",
      }}
    >
      <Icon size={14} />
      {label}
      <span
        style={{
          background: active ? color : "#e2e8f0",
          color: active ? "white" : "#64748b",
          borderRadius: 10,
          padding: "1px 7px",
          fontSize: 11,
          fontWeight: 600,
        }}
      >
        {count}
      </span>
    </button>
  );
};

// 원자재 카드
const MaterialCard = ({ material, onView }) => {
  const Icon = CATEGORY_ICONS[material.category];
  const color = CATEGORY_COLORS[material.category];
  const stockPercent = material.minStock > 0 ? Math.min((material.currentStock / (material.minStock * 2)) * 100, 100) : 100;
  const stockBarColor = material.status === "out" ? "#cbd5e1" : material.status === "critical" ? "#ef4444" : material.status === "low" ? "#f59e0b" : "#10b981";

  return (
    <div
      style={{
        background: "white",
        borderRadius: 12,
        padding: 0,
        boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
        overflow: "hidden",
        transition: "box-shadow 0.2s, transform 0.2s",
        cursor: "pointer",
        border: material.status === "critical" || material.status === "out" ? "1px solid #fecaca" : "1px solid transparent",
      }}
      onClick={onView}
      onMouseEnter={(e) => {
        e.currentTarget.style.boxShadow = "0 4px 12px rgba(0,0,0,0.12)";
        e.currentTarget.style.transform = "translateY(-2px)";
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.boxShadow = "0 1px 3px rgba(0,0,0,0.08)";
        e.currentTarget.style.transform = "translateY(0)";
      }}
    >
      {/* 상단 카테고리 스트라이프 */}
      <div style={{ height: 4, background: color }} />

      <div style={{ padding: "14px 16px" }}>
        {/* 헤더 */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 10 }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 4 }}>
              <Icon size={14} color={color} />
              <span style={{ fontSize: 11, color: "#94a3b8", fontWeight: 500 }}>{material.code}</span>
            </div>
            <div style={{ fontSize: 14, fontWeight: 600, color: "#1e293b" }}>{material.name}</div>
          </div>
          <StatusBadge status={material.status} />
        </div>

        {/* 속성 태그 (원단일 경우) */}
        {material.category === "tela" && (
          <div style={{ display: "flex", gap: 4, marginBottom: 10, flexWrap: "wrap" }}>
            {material.color && (
              <span style={{ fontSize: 10, padding: "2px 8px", borderRadius: 4, background: "#f1f5f9", color: "#64748b" }}>
                {material.color}
              </span>
            )}
            {material.origin && (
              <span style={{ fontSize: 10, padding: "2px 8px", borderRadius: 4, background: "#f1f5f9", color: "#64748b" }}>
                {material.origin}
              </span>
            )}
            {material.quality && (
              <span style={{ fontSize: 10, padding: "2px 8px", borderRadius: 4, background: "#ede9fe", color: "#7c3aed" }}>
                {material.quality}
              </span>
            )}
          </div>
        )}

        {/* 재고 바 */}
        <div style={{ marginBottom: 8 }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
            <span style={{ fontSize: 12, color: "#64748b" }}>Stock</span>
            <span style={{ fontSize: 13, fontWeight: 700, color: "#1e293b" }}>
              {material.currentStock} {material.unit}
            </span>
          </div>
          <div style={{ height: 6, background: "#f1f5f9", borderRadius: 3, overflow: "hidden" }}>
            <div
              style={{
                height: "100%",
                width: `${stockPercent}%`,
                background: stockBarColor,
                borderRadius: 3,
                transition: "width 0.3s",
              }}
            />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 2 }}>
            <span style={{ fontSize: 10, color: "#94a3b8" }}>Mín: {material.minStock}</span>
            <span style={{ fontSize: 10, color: "#94a3b8" }}>Último: {material.lastEntry}</span>
          </div>
        </div>

        {/* 하단: 가격 + 공급자 */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            paddingTop: 10,
            borderTop: "1px solid #f1f5f9",
          }}
        >
          <div>
            <div style={{ fontSize: 11, color: "#94a3b8" }}>Precio unit.</div>
            <div style={{ fontSize: 13, fontWeight: 600, color: "#1e293b" }}>
              {formatCurrency(material.standardPrice)}
              <span style={{ fontSize: 10, color: "#94a3b8" }}>/{material.unit}</span>
            </div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 11, color: "#94a3b8" }}>Proveedor</div>
            <div style={{ fontSize: 12, fontWeight: 500, color: "#475569" }}>{material.supplier}</div>
          </div>
        </div>
      </div>
    </div>
  );
};

// 공급자 카드
const SupplierCard = ({ supplier }) => (
  <div
    style={{
      background: "white",
      borderRadius: 12,
      padding: 20,
      boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
      transition: "box-shadow 0.2s",
      cursor: "pointer",
    }}
    onMouseEnter={(e) => (e.currentTarget.style.boxShadow = "0 4px 12px rgba(0,0,0,0.12)")}
    onMouseLeave={(e) => (e.currentTarget.style.boxShadow = "0 1px 3px rgba(0,0,0,0.08)")}
  >
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 14 }}>
      <div>
        <div style={{ fontSize: 16, fontWeight: 700, color: "#1e293b", marginBottom: 2 }}>{supplier.name}</div>
        <div style={{ fontSize: 12, color: "#64748b" }}>{supplier.contact}</div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 2 }}>
        <Star size={14} fill="#f59e0b" color="#f59e0b" />
        <span style={{ fontSize: 13, fontWeight: 600, color: "#1e293b" }}>{supplier.rating}</span>
      </div>
    </div>

    {/* 연락처 */}
    <div style={{ display: "flex", gap: 12, marginBottom: 14, flexWrap: "wrap" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 11, color: "#64748b" }}>
        <Phone size={12} /> {supplier.phone}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 11, color: "#64748b" }}>
        <Mail size={12} /> {supplier.email}
      </div>
    </div>

    {/* 대금 정보 */}
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "1fr 1fr",
        gap: 10,
        padding: 12,
        background: "#f8fafc",
        borderRadius: 8,
        marginBottom: 12,
      }}
    >
      <div>
        <div style={{ fontSize: 11, color: "#94a3b8", marginBottom: 2 }}>Deuda pendiente</div>
        <div style={{ fontSize: 16, fontWeight: 700, color: supplier.totalDebt > 0 ? "#ef4444" : "#10b981" }}>
          {formatCurrency(supplier.totalDebt)}
        </div>
      </div>
      <div>
        <div style={{ fontSize: 11, color: "#94a3b8", marginBottom: 2 }}>Total pagado</div>
        <div style={{ fontSize: 16, fontWeight: 700, color: "#1e293b" }}>{formatCurrency(supplier.paidAmount)}</div>
      </div>
    </div>

    {/* 하단 */}
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <span style={{ fontSize: 11, color: "#94a3b8" }}>
        {supplier.totalOrders} pedidos · Último pago: {supplier.lastPayment}
      </span>
      <button
        style={{
          display: "flex",
          alignItems: "center",
          gap: 4,
          padding: "6px 12px",
          borderRadius: 6,
          border: "1px solid #e2e8f0",
          background: "white",
          cursor: "pointer",
          fontSize: 12,
          color: "#6366f1",
          fontWeight: 500,
        }}
      >
        <CreditCard size={13} /> Registrar pago
      </button>
    </div>
  </div>
);

// 이동 내역 행
const MovementRow = ({ movement }) => (
  <div
    style={{
      display: "grid",
      gridTemplateColumns: "90px 32px 1fr 100px 80px 100px",
      gap: 8,
      padding: "10px 16px",
      alignItems: "center",
      borderBottom: "1px solid #f1f5f9",
      fontSize: 13,
    }}
  >
    <span style={{ color: "#64748b" }}>{movement.date}</span>
    <span>
      {movement.type === "entrada" ? (
        <ArrowDownCircle size={18} color="#10b981" />
      ) : (
        <ArrowUpCircle size={18} color="#f59e0b" />
      )}
    </span>
    <div>
      <span style={{ fontWeight: 500, color: "#1e293b" }}>{movement.materialName}</span>
      <span style={{ fontSize: 11, color: "#94a3b8", marginLeft: 6 }}>{movement.materialCode}</span>
    </div>
    <span style={{ fontWeight: 600, color: movement.type === "entrada" ? "#10b981" : "#f59e0b" }}>
      {movement.type === "entrada" ? "+" : "-"}
      {movement.quantity} {movement.unit}
    </span>
    <span style={{ fontSize: 12, color: "#64748b" }}>
      {movement.type === "entrada" ? movement.supplier : movement.reference}
    </span>
    <span style={{ fontWeight: 500, color: "#1e293b", textAlign: "right" }}>
      {movement.total ? formatCurrency(movement.total) : "-"}
    </span>
  </div>
);

// 알림 카드
const AlertCard = ({ material }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "10px 14px",
      background: material.status === "out" ? "#fef2f2" : "#fffbeb",
      borderRadius: 8,
      borderLeft: `3px solid ${material.status === "out" ? "#ef4444" : "#f59e0b"}`,
    }}
  >
    <AlertTriangle size={16} color={material.status === "out" ? "#ef4444" : "#f59e0b"} />
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#1e293b" }}>{material.name}</div>
      <div style={{ fontSize: 11, color: "#64748b" }}>
        Stock: {material.currentStock} {material.unit} / Mín: {material.minStock} {material.unit}
      </div>
    </div>
    <button
      style={{
        padding: "5px 12px",
        borderRadius: 6,
        border: "none",
        background: "#6366f1",
        color: "white",
        fontSize: 11,
        fontWeight: 600,
        cursor: "pointer",
      }}
    >
      Pedir
    </button>
  </div>
);

// ============================================================
// 메인 컴포넌트
// ============================================================
export default function MaterialPrimaPrototype() {
  const [activeTab, setActiveTab] = useState("dashboard");
  const [activeCategory, setActiveCategory] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [showEntryModal, setShowEntryModal] = useState(false);

  // 카테고리별 카운트
  const categoryCounts = useMemo(() => {
    const counts = { all: SAMPLE_MATERIALS.length };
    SAMPLE_MATERIALS.forEach((m) => {
      counts[m.category] = (counts[m.category] || 0) + 1;
    });

    return counts;
  }, []);

  // 필터링된 재료
  const filteredMaterials = useMemo(() => {
    return SAMPLE_MATERIALS.filter((m) => {
      if (activeCategory !== "all" && m.category !== activeCategory) return false;
      if (searchQuery && !m.name.toLowerCase().includes(searchQuery.toLowerCase()) && !m.code.toLowerCase().includes(searchQuery.toLowerCase())) return false;

      return true;
    });
  }, [activeCategory, searchQuery]);

  // KPI 계산
  const kpis = useMemo(() => {
    const totalItems = SAMPLE_MATERIALS.length;
    const lowStockItems = SAMPLE_MATERIALS.filter((m) => m.status === "low" || m.status === "critical" || m.status === "out").length;
    const totalValue = SAMPLE_MATERIALS.reduce((sum, m) => sum + m.currentStock * m.standardPrice, 0);
    const totalDebt = SAMPLE_SUPPLIERS.reduce((sum, s) => sum + s.totalDebt, 0);

    return { totalItems, lowStockItems, totalValue, totalDebt };
  }, []);

  // 탭 메뉴
  const tabs = [
    { id: "dashboard", label: "Dashboard", icon: BarChart3 },
    { id: "inventory", label: "Inventario", icon: Package },
    { id: "suppliers", label: "Proveedores", icon: Truck },
    { id: "movements", label: "Movimientos", icon: ArrowRight },
    { id: "payments", label: "Pagos", icon: Wallet },
  ];

  return (
    <div style={{ fontFamily: "'Inter', -apple-system, sans-serif", background: "#f8fafc", minHeight: "100vh" }}>
      {/* 헤더 */}
      <div
        style={{
          background: "white",
          borderBottom: "1px solid #e2e8f0",
          padding: "0 24px",
          position: "sticky",
          top: 0,
          zIndex: 10,
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", height: 60 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div
              style={{
                width: 36,
                height: 36,
                borderRadius: 8,
                background: "linear-gradient(135deg, #6366f1, #8b5cf6)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Scissors size={20} color="white" />
            </div>
            <div>
              <div style={{ fontSize: 16, fontWeight: 700, color: "#1e293b" }}>Materia Prima</div>
              <div style={{ fontSize: 11, color: "#94a3b8" }}>Gestión de Insumos · Confección</div>
            </div>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            {/* 알림 벨 */}
            <div style={{ position: "relative", cursor: "pointer" }}>
              <Bell size={20} color="#64748b" />
              {kpis.lowStockItems > 0 && (
                <span
                  style={{
                    position: "absolute",
                    top: -4,
                    right: -4,
                    width: 16,
                    height: 16,
                    borderRadius: "50%",
                    background: "#ef4444",
                    color: "white",
                    fontSize: 10,
                    fontWeight: 700,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  {kpis.lowStockItems}
                </span>
              )}
            </div>

            {/* 빠른 입고 버튼 */}
            <button
              onClick={() => setShowEntryModal(true)}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 6,
                padding: "8px 16px",
                borderRadius: 8,
                border: "none",
                background: "#6366f1",
                color: "white",
                fontSize: 13,
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              <Plus size={16} /> Nueva Entrada
            </button>
          </div>
        </div>

        {/* 탭 네비게이션 */}
        <div style={{ display: "flex", gap: 0 }}>
          {tabs.map((tab) => {
            const TabIcon = tab.icon;

            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "10px 18px",
                  border: "none",
                  background: "none",
                  cursor: "pointer",
                  fontSize: 13,
                  fontWeight: activeTab === tab.id ? 600 : 400,
                  color: activeTab === tab.id ? "#6366f1" : "#64748b",
                  borderBottom: activeTab === tab.id ? "2px solid #6366f1" : "2px solid transparent",
                  transition: "all 0.15s",
                }}
              >
                <TabIcon size={16} />
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* 본문 */}
      <div style={{ padding: 24, maxWidth: 1280, margin: "0 auto" }}>
        {/* ======== DASHBOARD 탭 ======== */}
        {activeTab === "dashboard" && (
          <div>
            {/* KPI 행 */}
            <div style={{ display: "flex", gap: 16, marginBottom: 24, flexWrap: "wrap" }}>
              <KpiCard icon={Package} label="Total Materiales" value={kpis.totalItems} subValue={null} color="#6366f1" />
              <KpiCard
                icon={AlertTriangle}
                label="Stock Bajo / Agotado"
                value={kpis.lowStockItems}
                subValue="3 necesitan pedido"
                color="#ef4444"
                trend="up"
              />
              <KpiCard
                icon={DollarSign}
                label="Valor Inventario"
                value={formatCurrency(kpis.totalValue)}
                subValue="+5.2% vs mes anterior"
                color="#10b981"
                trend="down"
              />
              <KpiCard
                icon={Truck}
                label="Deuda Proveedores"
                value={formatCurrency(kpis.totalDebt)}
                subValue="4 proveedores activos"
                color="#f59e0b"
              />
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 20 }}>
              {/* 좌측: 재고 알림 + 최근 이동 */}
              <div>
                {/* 알림 */}
                <div style={{ marginBottom: 20 }}>
                  <div style={{ fontSize: 15, fontWeight: 700, color: "#1e293b", marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
                    <AlertTriangle size={18} color="#ef4444" />
                    Alertas de Stock ({kpis.lowStockItems})
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                    {SAMPLE_MATERIALS.filter((m) => m.status !== "normal").map((m) => (
                      <AlertCard key={m.id} material={m} />
                    ))}
                  </div>
                </div>

                {/* 최근 이동 */}
                <div
                  style={{
                    background: "white",
                    borderRadius: 12,
                    boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
                    overflow: "hidden",
                  }}
                >
                  <div
                    style={{
                      padding: "14px 16px",
                      borderBottom: "1px solid #f1f5f9",
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                    }}
                  >
                    <span style={{ fontSize: 15, fontWeight: 700, color: "#1e293b" }}>Últimos Movimientos</span>
                    <button
                      onClick={() => setActiveTab("movements")}
                      style={{
                        fontSize: 12,
                        color: "#6366f1",
                        background: "none",
                        border: "none",
                        cursor: "pointer",
                        fontWeight: 500,
                        display: "flex",
                        alignItems: "center",
                        gap: 4,
                      }}
                    >
                      Ver todos <ChevronRight size={14} />
                    </button>
                  </div>
                  {SAMPLE_MOVEMENTS.slice(0, 5).map((m) => (
                    <MovementRow key={m.id} movement={m} />
                  ))}
                </div>
              </div>

              {/* 우측: 카테고리 분포 + 공급자 대금 */}
              <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
                {/* 카테고리 분포 */}
                <div style={{ background: "white", borderRadius: 12, padding: 20, boxShadow: "0 1px 3px rgba(0,0,0,0.08)" }}>
                  <div style={{ fontSize: 15, fontWeight: 700, color: "#1e293b", marginBottom: 16 }}>Por Categoría</div>
                  {Object.entries(CATEGORY_LABELS).map(([key, label]) => {
                    const count = categoryCounts[key] || 0;
                    const Icon = CATEGORY_ICONS[key];
                    const color = CATEGORY_COLORS[key];
                    const totalInCat = SAMPLE_MATERIALS.filter((m) => m.category === key).reduce(
                      (sum, m) => sum + m.currentStock * m.standardPrice,
                      0
                    );

                    return (
                      <div
                        key={key}
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: 10,
                          padding: "10px 0",
                          borderBottom: "1px solid #f8fafc",
                        }}
                      >
                        <div
                          style={{
                            width: 32,
                            height: 32,
                            borderRadius: 8,
                            background: `${color}15`,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                          }}
                        >
                          <Icon size={16} color={color} />
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ fontSize: 13, fontWeight: 500, color: "#1e293b" }}>{label}</div>
                          <div style={{ fontSize: 11, color: "#94a3b8" }}>{count} items</div>
                        </div>
                        <div style={{ fontSize: 13, fontWeight: 600, color: "#475569" }}>{formatCurrency(totalInCat)}</div>
                      </div>
                    );
                  })}
                </div>

                {/* 공급자 대금 요약 */}
                <div style={{ background: "white", borderRadius: 12, padding: 20, boxShadow: "0 1px 3px rgba(0,0,0,0.08)" }}>
                  <div style={{ fontSize: 15, fontWeight: 700, color: "#1e293b", marginBottom: 16, display: "flex", alignItems: "center", gap: 8 }}>
                    <Wallet size={18} color="#6366f1" />
                    Deudas por Proveedor
                  </div>
                  {SAMPLE_SUPPLIERS.filter((s) => s.totalDebt > 0)
                    .sort((a, b) => b.totalDebt - a.totalDebt)
                    .map((s) => (
                      <div
                        key={s.id}
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          alignItems: "center",
                          padding: "10px 0",
                          borderBottom: "1px solid #f8fafc",
                        }}
                      >
                        <div>
                          <div style={{ fontSize: 13, fontWeight: 500, color: "#1e293b" }}>{s.name}</div>
                          <div style={{ fontSize: 11, color: "#94a3b8" }}>Último pago: {s.lastPayment}</div>
                        </div>
                        <div style={{ fontSize: 14, fontWeight: 700, color: "#ef4444" }}>{formatCurrency(s.totalDebt)}</div>
                      </div>
                    ))}
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      paddingTop: 12,
                      marginTop: 4,
                      borderTop: "2px solid #e2e8f0",
                    }}
                  >
                    <span style={{ fontSize: 13, fontWeight: 700, color: "#1e293b" }}>Total</span>
                    <span style={{ fontSize: 16, fontWeight: 700, color: "#ef4444" }}>{formatCurrency(kpis.totalDebt)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ======== INVENTARIO 탭 ======== */}
        {activeTab === "inventory" && (
          <div>
            {/* 검색 + 필터 */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
              <div style={{ position: "relative", width: 300 }}>
                <Search size={16} color="#94a3b8" style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)" }} />
                <input
                  type="text"
                  placeholder="Buscar material..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "8px 12px 8px 36px",
                    borderRadius: 8,
                    border: "1px solid #e2e8f0",
                    fontSize: 13,
                    outline: "none",
                    background: "white",
                  }}
                />
              </div>
              <button
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "8px 16px",
                  borderRadius: 8,
                  border: "1px solid #e2e8f0",
                  background: "white",
                  cursor: "pointer",
                  fontSize: 13,
                  color: "#475569",
                }}
              >
                <Plus size={16} /> Nuevo Material
              </button>
            </div>

            {/* 카테고리 필터 */}
            <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
              <button
                onClick={() => setActiveCategory("all")}
                style={{
                  padding: "6px 14px",
                  borderRadius: 20,
                  border: activeCategory === "all" ? "2px solid #6366f1" : "1px solid #e2e8f0",
                  background: activeCategory === "all" ? "#6366f110" : "white",
                  cursor: "pointer",
                  fontSize: 13,
                  fontWeight: activeCategory === "all" ? 600 : 400,
                  color: activeCategory === "all" ? "#6366f1" : "#64748b",
                }}
              >
                Todos ({categoryCounts.all})
              </button>
              {Object.keys(CATEGORY_LABELS).map((cat) => (
                <CategoryChip
                  key={cat}
                  category={cat}
                  active={activeCategory === cat}
                  onClick={() => setActiveCategory(cat)}
                  count={categoryCounts[cat] || 0}
                />
              ))}
            </div>

            {/* 재료 카드 그리드 */}
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))",
                gap: 16,
              }}
            >
              {filteredMaterials.map((m) => (
                <MaterialCard key={m.id} material={m} onView={() => {}} />
              ))}
            </div>

            {filteredMaterials.length === 0 && (
              <div style={{ textAlign: "center", padding: "60px 20px", color: "#94a3b8" }}>
                <Package size={48} color="#cbd5e1" />
                <div style={{ fontSize: 15, fontWeight: 500, marginTop: 12 }}>No se encontraron materiales</div>
                <div style={{ fontSize: 13, marginTop: 4 }}>Ajuste los filtros o agregue un nuevo material</div>
              </div>
            )}
          </div>
        )}

        {/* ======== PROVEEDORES 탭 ======== */}
        {activeTab === "suppliers" && (
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#1e293b" }}>Proveedores de Materia Prima</div>
              <button
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "8px 16px",
                  borderRadius: 8,
                  border: "none",
                  background: "#6366f1",
                  color: "white",
                  fontSize: 13,
                  fontWeight: 600,
                  cursor: "pointer",
                }}
              >
                <Plus size={16} /> Nuevo Proveedor
              </button>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(380px, 1fr))", gap: 16 }}>
              {SAMPLE_SUPPLIERS.map((s) => (
                <SupplierCard key={s.id} supplier={s} />
              ))}
            </div>
          </div>
        )}

        {/* ======== MOVIMIENTOS 탭 ======== */}
        {activeTab === "movements" && (
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#1e293b" }}>Movimientos de Inventario</div>
              <div style={{ display: "flex", gap: 8 }}>
                <button
                  onClick={() => setShowEntryModal(true)}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    padding: "8px 16px",
                    borderRadius: 8,
                    border: "none",
                    background: "#10b981",
                    color: "white",
                    fontSize: 13,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  <ArrowDownCircle size={16} /> Entrada
                </button>
                <button
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    padding: "8px 16px",
                    borderRadius: 8,
                    border: "none",
                    background: "#f59e0b",
                    color: "white",
                    fontSize: 13,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  <ArrowUpCircle size={16} /> Salida
                </button>
              </div>
            </div>

            <div style={{ background: "white", borderRadius: 12, boxShadow: "0 1px 3px rgba(0,0,0,0.08)", overflow: "hidden" }}>
              {/* 테이블 헤더 */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "90px 32px 1fr 100px 80px 100px",
                  gap: 8,
                  padding: "10px 16px",
                  background: "#f8fafc",
                  borderBottom: "1px solid #e2e8f0",
                  fontSize: 11,
                  fontWeight: 600,
                  color: "#94a3b8",
                  textTransform: "uppercase",
                  letterSpacing: 0.5,
                }}
              >
                <span>Fecha</span>
                <span>Tipo</span>
                <span>Material</span>
                <span>Cantidad</span>
                <span>Ref.</span>
                <span style={{ textAlign: "right" }}>Monto</span>
              </div>
              {SAMPLE_MOVEMENTS.map((m) => (
                <MovementRow key={m.id} movement={m} />
              ))}
            </div>
          </div>
        )}

        {/* ======== PAGOS 탭 ======== */}
        {activeTab === "payments" && (
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#1e293b" }}>Registro de Pagos a Proveedores</div>
              <button
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "8px 16px",
                  borderRadius: 8,
                  border: "none",
                  background: "#6366f1",
                  color: "white",
                  fontSize: 13,
                  fontWeight: 600,
                  cursor: "pointer",
                }}
              >
                <CreditCard size={16} /> Registrar Pago
              </button>
            </div>

            {/* 대금 요약 카드 */}
            <div style={{ display: "flex", gap: 16, marginBottom: 20, flexWrap: "wrap" }}>
              <KpiCard icon={Wallet} label="Deuda Total" value={formatCurrency(kpis.totalDebt)} color="#ef4444" />
              <KpiCard
                icon={Check}
                label="Pagado este mes"
                value={formatCurrency(1495000)}
                subValue="4 transacciones"
                color="#10b981"
              />
              <KpiCard icon={Clock} label="Próximo Vencimiento" value="Abr 15" subValue="Textiles del Sur" color="#f59e0b" />
            </div>

            {/* 결제 내역 테이블 */}
            <div style={{ background: "white", borderRadius: 12, boxShadow: "0 1px 3px rgba(0,0,0,0.08)", overflow: "hidden" }}>
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "90px 1fr 120px 100px 100px 1fr",
                  gap: 8,
                  padding: "10px 16px",
                  background: "#f8fafc",
                  borderBottom: "1px solid #e2e8f0",
                  fontSize: 11,
                  fontWeight: 600,
                  color: "#94a3b8",
                  textTransform: "uppercase",
                  letterSpacing: 0.5,
                }}
              >
                <span>Fecha</span>
                <span>Proveedor</span>
                <span>Monto</span>
                <span>Método</span>
                <span>Ref.</span>
                <span>Nota</span>
              </div>
              {SAMPLE_PAYMENTS.map((p) => (
                <div
                  key={p.id}
                  style={{
                    display: "grid",
                    gridTemplateColumns: "90px 1fr 120px 100px 100px 1fr",
                    gap: 8,
                    padding: "10px 16px",
                    alignItems: "center",
                    borderBottom: "1px solid #f1f5f9",
                    fontSize: 13,
                  }}
                >
                  <span style={{ color: "#64748b" }}>{p.date}</span>
                  <span style={{ fontWeight: 500, color: "#1e293b" }}>{p.supplier}</span>
                  <span style={{ fontWeight: 700, color: "#10b981" }}>{formatCurrency(p.amount)}</span>
                  <span
                    style={{
                      fontSize: 11,
                      padding: "2px 8px",
                      borderRadius: 4,
                      background: "#f1f5f9",
                      color: "#475569",
                      textAlign: "center",
                    }}
                  >
                    {p.method}
                  </span>
                  <span style={{ fontSize: 12, color: "#64748b" }}>{p.reference}</span>
                  <span style={{ fontSize: 12, color: "#94a3b8" }}>{p.note}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* ======== 입고 모달 ======== */}
      {showEntryModal && (
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            background: "rgba(0,0,0,0.5)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 100,
          }}
          onClick={() => setShowEntryModal(false)}
        >
          <div
            style={{
              background: "white",
              borderRadius: 16,
              width: 480,
              maxHeight: "80vh",
              overflow: "auto",
              boxShadow: "0 20px 60px rgba(0,0,0,0.2)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "16px 20px",
                borderBottom: "1px solid #e2e8f0",
              }}
            >
              <div style={{ fontSize: 16, fontWeight: 700, color: "#1e293b" }}>Nueva Entrada de Material</div>
              <button
                onClick={() => setShowEntryModal(false)}
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 6,
                  border: "none",
                  background: "#f1f5f9",
                  cursor: "pointer",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <X size={16} color="#64748b" />
              </button>
            </div>

            <div style={{ padding: 20, display: "flex", flexDirection: "column", gap: 16 }}>
              {/* 재료 선택 */}
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                  Material *
                </label>
                <select
                  style={{
                    width: "100%",
                    padding: "8px 12px",
                    borderRadius: 8,
                    border: "1px solid #e2e8f0",
                    fontSize: 13,
                    background: "white",
                  }}
                >
                  <option>Seleccionar material...</option>
                  {SAMPLE_MATERIALS.map((m) => (
                    <option key={m.id}>
                      {m.code} - {m.name}
                    </option>
                  ))}
                </select>
              </div>

              {/* 공급자 */}
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                  Proveedor *
                </label>
                <select
                  style={{
                    width: "100%",
                    padding: "8px 12px",
                    borderRadius: 8,
                    border: "1px solid #e2e8f0",
                    fontSize: 13,
                    background: "white",
                  }}
                >
                  <option>Seleccionar proveedor...</option>
                  {SAMPLE_SUPPLIERS.map((s) => (
                    <option key={s.id}>{s.name}</option>
                  ))}
                </select>
              </div>

              {/* 수량 + 단가 */}
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                <div>
                  <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                    Cantidad *
                  </label>
                  <input
                    type="number"
                    placeholder="0"
                    style={{
                      width: "100%",
                      padding: "8px 12px",
                      borderRadius: 8,
                      border: "1px solid #e2e8f0",
                      fontSize: 13,
                    }}
                  />
                </div>
                <div>
                  <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                    Precio Unitario
                  </label>
                  <input
                    type="number"
                    placeholder="$0"
                    style={{
                      width: "100%",
                      padding: "8px 12px",
                      borderRadius: 8,
                      border: "1px solid #e2e8f0",
                      fontSize: 13,
                    }}
                  />
                </div>
              </div>

              {/* 날짜 */}
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                  Fecha de Entrada
                </label>
                <input
                  type="date"
                  defaultValue="2026-04-10"
                  style={{
                    width: "100%",
                    padding: "8px 12px",
                    borderRadius: 8,
                    border: "1px solid #e2e8f0",
                    fontSize: 13,
                  }}
                />
              </div>

              {/* 메모 */}
              <div>
                <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 6 }}>
                  Notas
                </label>
                <textarea
                  placeholder="Observaciones..."
                  rows={2}
                  style={{
                    width: "100%",
                    padding: "8px 12px",
                    borderRadius: 8,
                    border: "1px solid #e2e8f0",
                    fontSize: 13,
                    resize: "vertical",
                  }}
                />
              </div>

              {/* 대금 처리 옵션 */}
              <div
                style={{
                  padding: 12,
                  background: "#f8fafc",
                  borderRadius: 8,
                  border: "1px solid #e2e8f0",
                }}
              >
                <label style={{ fontSize: 12, fontWeight: 600, color: "#475569", display: "block", marginBottom: 8 }}>
                  Forma de Pago
                </label>
                <div style={{ display: "flex", gap: 8 }}>
                  {["A cuenta (Deuda)", "Pagado", "Parcial"].map((opt) => (
                    <button
                      key={opt}
                      style={{
                        padding: "6px 12px",
                        borderRadius: 6,
                        border: opt === "A cuenta (Deuda)" ? "2px solid #6366f1" : "1px solid #e2e8f0",
                        background: opt === "A cuenta (Deuda)" ? "#6366f110" : "white",
                        cursor: "pointer",
                        fontSize: 12,
                        fontWeight: opt === "A cuenta (Deuda)" ? 600 : 400,
                        color: opt === "A cuenta (Deuda)" ? "#6366f1" : "#64748b",
                      }}
                    >
                      {opt}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: 10,
                padding: "14px 20px",
                borderTop: "1px solid #e2e8f0",
              }}
            >
              <button
                onClick={() => setShowEntryModal(false)}
                style={{
                  padding: "8px 20px",
                  borderRadius: 8,
                  border: "1px solid #e2e8f0",
                  background: "white",
                  cursor: "pointer",
                  fontSize: 13,
                  color: "#64748b",
                }}
              >
                Cancelar
              </button>
              <button
                style={{
                  padding: "8px 20px",
                  borderRadius: 8,
                  border: "none",
                  background: "#6366f1",
                  color: "white",
                  cursor: "pointer",
                  fontSize: 13,
                  fontWeight: 600,
                }}
              >
                Registrar Entrada
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
