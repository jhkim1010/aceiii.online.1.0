package com.coolsistema.wearadmin.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// =============================================================================
// GET /watch/resumen 응답 v2 — 단일 출처는 api-ventago 의 골든 JSON
// (test/fixtures/watch-resumen-v2.golden.json). 이 파일은 그 모양을 Kotlin
// 타입으로 반영할 뿐이다. 담당자 "이름" 류 필드는 어느 타입에도 없다(D-14 ①).
// =============================================================================

/** 응답 v2 전용 Json — 서버가 필드를 늘려도(모르는 키) 워치가 죽지 않게. */
val WatchJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

@Serializable
data class SucursalRef(
    val id: Int? = null,
    val nombre: String,
)

@Serializable
data class SucursalResumenRow(
    val id: Int? = null,
    val nombre: String,
    val ventasHoy: Double,
)

@Serializable
data class Seccion<T>(
    val status: String,
    val asOf: String? = null,
    val periodStart: String,
    val periodEnd: String,
    val data: T? = null,
)

@Serializable
data class HoySucursalRow(
    val id: Int? = null,
    val nombre: String,
    val total: Double,
    val ventas: Int,
    val prendas: Int,
    val ultimaVenta: String? = null,
)

@Serializable
data class HoyData(
    val total: Double,
    val ventas: Int,
    val prendas: Int,
    val ultimaVenta: String? = null,
    val ayerMismaHora: Double,
    val porSucursal: List<HoySucursalRow> = emptyList(),
)

@Serializable
data class MediosPagoSucursalRow(
    val id: Int? = null,
    val nombre: String,
    val efectivo: Double,
    val bancarias: Double,
    val credito: Double,
    val favor: Double,
    val otros: Double,
)

@Serializable
data class MediosPagoData(
    val efectivo: Double,
    val bancarias: Double,
    val credito: Double,
    val favor: Double,
    val otros: Double,
    val porSucursal: List<MediosPagoSucursalRow> = emptyList(),
)

@Serializable
data class MontoEventos(val monto: Double, val eventos: Int)

@Serializable
data class MontoVentas(val monto: Double, val ventas: Int)

@Serializable
data class GastosDescuentosSucursalRow(
    val id: Int? = null,
    val nombre: String,
    val gastos: MontoEventos,
    val descuentos: MontoVentas,
)

@Serializable
data class GastosDescuentosData(
    val gastos: MontoEventos,
    val descuentos: MontoVentas,
    val porSucursal: List<GastosDescuentosSucursalRow> = emptyList(),
)

@Serializable
data class PrendasEventos(val prendas: Int, val eventos: Int)

@Serializable
data class IngresosSucursalRow(
    val id: Int? = null,
    val nombre: String,
    val prendas: Int,
    val eventos: Int,
)

@Serializable
data class IngresosData(
    val prendas: Int,
    val eventos: Int,
    val compras: PrendasEventos,
    val talleres: PrendasEventos,
    val porSucursal: List<IngresosSucursalRow> = emptyList(),
)

@Serializable
data class FacturacionPorTipoRow(
    val tipo: String,
    val total: Double,
    val iva: Double,
    val comprobantes: Int,
)

@Serializable
data class FacturacionSucursalRow(
    val id: Int? = null,
    val nombre: String,
    val total: Double,
    val iva: Double,
)

@Serializable
data class FacturacionMesData(
    val mes: String,
    val total: Double,
    val iva: Double,
    val comprobantes: Int,
    val comprobantesSinIva: Int,
    val porTipo: List<FacturacionPorTipoRow> = emptyList(),
    val porSucursal: List<FacturacionSucursalRow> = emptyList(),
)

@Serializable
data class CajaRow(
    val boxId: Int,
    val nombre: String,
    val abierta: Boolean,
    val desde: String? = null,
    val saldo: Double? = null,
    val abiertaDesdeDiaAnterior: Boolean,
    val pendientesAnteriores: Int,
)

@Serializable
data class CajasSucursalRow(
    val id: Int? = null,
    val nombre: String,
    val subtotal: Double,
    val cajas: List<CajaRow> = emptyList(),
)

@Serializable
data class CajasData(
    val abiertas: Int,
    val total: Int,
    val efectivoEnCajas: Double,
    val omitidas: Int,
    val porSucursal: List<CajasSucursalRow> = emptyList(),
)

@Serializable
data class Secciones(
    val hoy: Seccion<HoyData>,
    val mediosPago: Seccion<MediosPagoData>,
    val gastosDescuentos: Seccion<GastosDescuentosData>,
    val ingresos: Seccion<IngresosData>,
    val facturacionMes: Seccion<FacturacionMesData>,
    val cajas: Seccion<CajasData>,
)

@Serializable
data class Resumen(
    val schemaVersion: Int,
    val tienda: String,
    val zona: String,
    val hoy: String,
    val generadoEn: String,
    val sucursal: SucursalRef? = null,
    val sucursales: List<SucursalResumenRow> = emptyList(),
    val secciones: Secciones,
)

// --- 페어링 ---

@Serializable
data class PairingCodeDto(
    val userCode: String,
    val deviceCode: String,
    val expiresIn: Int,
    val interval: Int,
)

@Serializable
data class PollDto(
    val watchToken: String? = null,
    val expiresAt: String? = null,
    val status: String? = null,
)
