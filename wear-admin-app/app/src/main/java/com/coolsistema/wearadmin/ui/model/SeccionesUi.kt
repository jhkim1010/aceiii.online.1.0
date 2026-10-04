package com.coolsistema.wearadmin.ui.model

import com.coolsistema.wearadmin.data.CajaRow
import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.format.abreviarMonto
import com.coolsistema.wearadmin.format.deltaPct
import com.coolsistema.wearadmin.format.formatCantidad
import com.coolsistema.wearadmin.format.formatDelta
import com.coolsistema.wearadmin.format.haceTexto
import com.coolsistema.wearadmin.format.mesCorto
import kotlin.math.roundToInt

// =============================================================================
// 목업 v2 의 여섯 섹션을 화면 문구로 바꾸는 순수 함수(D-08·D-09·D-12·D-14·D-15 ⑥).
// 숫자·문구·정렬·상태 규칙은 전부 여기서 고정된다 — Compose 화면(98-11)은 이 모델을
// 그리기만 한다. 금액은 abreviarMonto, 수량은 formatCantidad, 월은 mesCorto 로만 포맷한다
// (다른 로케일 표준 포맷 클래스는 이 패키지에서 쓰지 않는다).
// =============================================================================

enum class Tono { Normal, Gris }

/** 모든 섹션 머리에 공통으로 붙는 범위 칩(D-09) + 연결 상태(D-10 Stale/Fresh). */
data class Cabecera(
    val label: String,
    val alcance: String,
    val alcanceTocable: Boolean,
    val aviso: String?,
    val pie: String?,
    val tono: Tono,
)

/** 섹션 한 칸의 상태 — error 면 본문 대신 "No disponible ahora"(그 섹션만). */
sealed class SeccionUi<out T> {
    data class Lista<T>(val data: T, val cabecera: Cabecera) : SeccionUi<T>()
    data class NoDisponible(val cabecera: Cabecera, val mensaje: String = "No disponible ahora") : SeccionUi<Nothing>()
}

data class HoySucursalResumen(val nombre: String, val monto: String)

data class HoyUi(
    val monto: String,
    val delta: String,
    val detalle: String,
    val ultima: String,
    val sucursales: List<HoySucursalResumen>,
)

data class MedioFila(val nombre: String, val monto: String, val proporcion: Double)
data class MedioSucursalResumen(val nombre: String, val efectivo: String)

data class MediosUi(
    val filas: List<MedioFila>,
    val porSucursal: List<MedioSucursalResumen>,
    val pieSucursal: String?,
)

data class GastosDescSucursalResumen(val nombre: String, val gastos: String, val descuentos: String)

data class GastosDescUi(
    val gastosMonto: String,
    val gastosEventos: String,
    val descuentosMonto: String,
    val descuentosEventos: String,
    val porSucursal: List<GastosDescSucursalResumen>,
)

data class IngresosSucursalResumen(val nombre: String, val prendas: String)

data class IngresosUi(
    val cantidad: String,
    val detalle: String,
    val subDetalle: String,
    val porSucursal: List<IngresosSucursalResumen>,
)

data class FacturacionTipoFila(val etiqueta: String, val monto: String)
data class FacturacionSucursalResumen(val nombre: String, val monto: String)

data class FacturacionUi(
    val grande: String,
    val iva: String,
    val tipos: List<FacturacionTipoFila>,
    val aviso: String?,
    val porSucursal: List<FacturacionSucursalResumen>,
)

data class CajaFila(val punto: String, val nombre: String, val montoOCerrada: String, val aviso: Boolean)
data class CajasGrupo(val titulo: String, val filas: List<CajaFila>)

data class CajasUi(
    val efectivoEnCajas: String,
    val grupos: List<CajasGrupo>,
    val filas: List<CajaFila>,
    val masOmitidas: String?,
)

data class SeccionesUi(
    val hoy: SeccionUi<HoyUi>,
    val mediosPago: SeccionUi<MediosUi>,
    val gastosDescuentos: SeccionUi<GastosDescUi>,
    val ingresos: SeccionUi<IngresosUi>,
    val facturacionMes: SeccionUi<FacturacionUi>,
    val cajas: SeccionUi<CajasUi>,
)

/** Fresh/Stale 응답 → 섹션 6종 표시 모델. */
fun seccionesUi(state: ResumenState, nowMillis: Long): SeccionesUi {
    val resumen: Resumen
    val fetchedAt: Long
    val isStale: Boolean
    when (state) {
        is ResumenState.Fresh -> {
            resumen = state.resumen
            fetchedAt = state.fetchedAt
            isStale = false
        }
        is ResumenState.Stale -> {
            resumen = state.resumen
            fetchedAt = state.fetchedAt
            isStale = true
        }
        else -> throw IllegalArgumentException("seccionesUi espera Fresh/Stale, no $state")
    }

    return SeccionesUi(
        hoy = hoySeccion(resumen, isStale, nowMillis, fetchedAt),
        mediosPago = mediosSeccion(resumen, isStale, nowMillis, fetchedAt),
        gastosDescuentos = gastosDescSeccion(resumen, isStale, nowMillis, fetchedAt),
        ingresos = ingresosSeccion(resumen, isStale, nowMillis, fetchedAt),
        facturacionMes = facturacionSeccion(resumen, isStale, nowMillis, fetchedAt),
        cajas = cajasSeccion(resumen, isStale, nowMillis, fetchedAt),
    )
}

// --- 범위 칩(D-09 · D-15 ⑥) — 이 두 함수가 판정의 단일 지점이다 -------------------

private fun muestraTodas(resumen: Resumen): Boolean = resumen.sucursal == null && resumen.sucursales.size > 1

private fun alcanceDe(resumen: Resumen): String {
    if (resumen.sucursales.size <= 1) return resumen.tienda.uppercase()
    val sel = resumen.sucursal
    return if (sel == null) "TODAS ▾" else "${sel.nombre.uppercase()} ▾"
}

private fun cabecera(resumen: Resumen, label: String, nowMillis: Long, fetchedAt: Long, isStale: Boolean): Cabecera {
    val hace = haceTexto(fetchedAt, nowMillis)
    return Cabecera(
        label = label,
        alcance = alcanceDe(resumen),
        alcanceTocable = resumen.sucursales.size > 1,
        aviso = if (isStale) "Sin conexión · $hace" else null,
        pie = if (isStale) null else hace,
        tono = if (isStale) Tono.Gris else Tono.Normal,
    )
}

private fun pctEntero(value: Double, total: Double): Int {
    if (total == 0.0) return 0
    return (value / total * 100).roundToInt()
}

// --- ① Hoy ------------------------------------------------------------------

private fun hoySeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<HoyUi> {
    val cab = cabecera(resumen, "VENTAS HOY", now, fetchedAt, isStale)
    val seccion = resumen.secciones.hoy
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val ui = HoyUi(
        monto = abreviarMonto(data.total),
        delta = formatDelta(deltaPct(data.total, data.ayerMismaHora)),
        detalle = "${formatCantidad(data.ventas)} ventas · ${formatCantidad(data.prendas)} prendas",
        ultima = data.ultimaVenta?.let { "Última venta $it" } ?: "Sin ventas hoy",
        sucursales = if (muestraTodas(resumen)) {
            resumen.sucursales
                .sortedByDescending { it.ventasHoy }
                .map { HoySucursalResumen(it.nombre, abreviarMonto(it.ventasHoy)) }
        } else {
            emptyList()
        },
    )
    return SeccionUi.Lista(ui, cab)
}

// --- ② Medios de pago ---------------------------------------------------------

private fun mediosSeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<MediosUi> {
    val cab = cabecera(resumen, "MEDIOS DE PAGO", now, fetchedAt, isStale)
    val seccion = resumen.secciones.mediosPago
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val total = data.efectivo + data.bancarias + data.credito + data.favor
    fun proporcion(v: Double) = if (total == 0.0) 0.0 else v / total

    val filas = listOf(
        MedioFila("Efectivo", abreviarMonto(data.efectivo), proporcion(data.efectivo)),
        MedioFila("Bancarias", abreviarMonto(data.bancarias), proporcion(data.bancarias)),
        MedioFila("Crédito", abreviarMonto(data.credito), proporcion(data.credito)),
        MedioFila("Favor", abreviarMonto(data.favor), proporcion(data.favor)),
    )

    val mostrar = muestraTodas(resumen)
    val porSucursal = if (mostrar) {
        data.porSucursal.map { MedioSucursalResumen(it.nombre, abreviarMonto(it.efectivo)) }
    } else {
        emptyList()
    }
    val pie = if (mostrar) "Total ${abreviarMonto(data.efectivo)} · ${pctEntero(data.efectivo, total)}%" else null

    return SeccionUi.Lista(MediosUi(filas, porSucursal, pie), cab)
}

// --- ③ Gastos y descuentos ----------------------------------------------------

private fun gastosDescSeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<GastosDescUi> {
    val cab = cabecera(resumen, "GASTOS Y DESCUENTOS", now, fetchedAt, isStale)
    val seccion = resumen.secciones.gastosDescuentos
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val porSucursal = if (muestraTodas(resumen)) {
        data.porSucursal.map {
            GastosDescSucursalResumen(it.nombre, abreviarMonto(it.gastos.monto), abreviarMonto(-it.descuentos.monto))
        }
    } else {
        emptyList()
    }

    val ui = GastosDescUi(
        gastosMonto = abreviarMonto(data.gastos.monto),
        gastosEventos = "${data.gastos.eventos} eventos",
        descuentosMonto = abreviarMonto(-data.descuentos.monto),
        descuentosEventos = "${data.descuentos.ventas} eventos",
        porSucursal = porSucursal,
    )
    return SeccionUi.Lista(ui, cab)
}

// --- ④ Ingresos de mercadería --------------------------------------------------

private fun ingresosSeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<IngresosUi> {
    val cab = cabecera(resumen, "INGRESOS DE MERCADERÍA", now, fetchedAt, isStale)
    val seccion = resumen.secciones.ingresos
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val porSucursal = if (muestraTodas(resumen)) {
        data.porSucursal.map { IngresosSucursalResumen(it.nombre, formatCantidad(it.prendas)) }
    } else {
        emptyList()
    }

    val ui = IngresosUi(
        cantidad = formatCantidad(data.prendas),
        detalle = "en ${data.eventos} ingresos",
        subDetalle = "Compras ${formatCantidad(data.compras.prendas)} · Talleres ${formatCantidad(data.talleres.prendas)}",
        porSucursal = porSucursal,
    )
    return SeccionUi.Lista(ui, cab)
}

// --- ⑤ Facturación del mes ------------------------------------------------------

private val TIPOS_OBLIGATORIOS = listOf("A", "B")

private fun facturacionTipos(porTipo: List<com.coolsistema.wearadmin.data.FacturacionPorTipoRow>): List<FacturacionTipoFila> {
    val porNombre = porTipo.associateBy { it.tipo }
    val filas = mutableListOf<FacturacionTipoFila>()
    for (tipo in TIPOS_OBLIGATORIOS) {
        filas.add(FacturacionTipoFila("Tipo $tipo", abreviarMonto(porNombre[tipo]?.total ?: 0.0)))
    }
    for (row in porTipo) {
        if (row.tipo in TIPOS_OBLIGATORIOS) continue
        filas.add(FacturacionTipoFila("Tipo ${row.tipo}", abreviarMonto(row.total)))
    }
    return filas
}

private fun facturacionSeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<FacturacionUi> {
    val seccion = resumen.secciones.facturacionMes
    val label = seccion.data?.let { "FACTURADO · ${mesCorto(it.mes)}" } ?: "FACTURADO"
    val cab = cabecera(resumen, label, now, fetchedAt, isStale)
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val porSucursal = if (muestraTodas(resumen)) {
        data.porSucursal.map { FacturacionSucursalResumen(it.nombre, abreviarMonto(it.total)) }
    } else {
        emptyList()
    }

    val ui = FacturacionUi(
        grande = abreviarMonto(data.total),
        iva = "IVA ${abreviarMonto(data.iva)}",
        tipos = facturacionTipos(data.porTipo),
        aviso = if (data.comprobantesSinIva > 0) "IVA incompleto (${data.comprobantesSinIva})" else null,
        porSucursal = porSucursal,
    )
    return SeccionUi.Lista(ui, cab)
}

// --- ⑥ Cajas ------------------------------------------------------------------

private fun cajaFila(c: CajaRow): CajaFila {
    val punto = if (c.abierta) "●" else "○"
    val montoOCerrada = if (c.abierta) abreviarMonto(c.saldo ?: 0.0) else "cerrada"
    val aviso = c.abiertaDesdeDiaAnterior || c.pendientesAnteriores > 0
    return CajaFila(punto, c.nombre, montoOCerrada, aviso)
}

private fun cajasSeccion(resumen: Resumen, isStale: Boolean, now: Long, fetchedAt: Long): SeccionUi<CajasUi> {
    val seccion = resumen.secciones.cajas
    val label = seccion.data?.let { "CAJAS · ${it.abiertas}/${it.total} ABIERTAS" } ?: "CAJAS"
    val cab = cabecera(resumen, label, now, fetchedAt, isStale)
    if (seccion.status == "error") return SeccionUi.NoDisponible(cab)
    val data = seccion.data ?: return SeccionUi.NoDisponible(cab)

    val mostrarGrupos = muestraTodas(resumen)
    val grupos = if (mostrarGrupos) {
        data.porSucursal.map { row ->
            CajasGrupo(
                titulo = "${row.nombre.uppercase()} · ${abreviarMonto(row.subtotal)}",
                filas = row.cajas.map { cajaFila(it) },
            )
        }
    } else {
        emptyList()
    }
    val filas = if (!mostrarGrupos) data.porSucursal.flatMap { it.cajas }.map { cajaFila(it) } else emptyList()

    val ui = CajasUi(
        efectivoEnCajas = "Efectivo en cajas ${abreviarMonto(data.efectivoEnCajas)}",
        grupos = grupos,
        filas = filas,
        masOmitidas = if (data.omitidas > 0) "+${data.omitidas} más" else null,
    )
    return SeccionUi.Lista(ui, cab)
}
