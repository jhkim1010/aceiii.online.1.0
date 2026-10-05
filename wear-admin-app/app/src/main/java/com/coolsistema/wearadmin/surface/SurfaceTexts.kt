package com.coolsistema.wearadmin.surface

import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.format.abreviarCorto
import com.coolsistema.wearadmin.format.abreviarMonto
import com.coolsistema.wearadmin.format.formatCantidad
import com.coolsistema.wearadmin.format.haceTexto

/**
 * 표면(Tile·컴플리케이션) 문구 순수 함수 — 앱이 아니라 여기 한 곳에서
 * "잠금 시 금액은 가리고 건수만 보인다"(D-14 ②)를 결정한다.
 *
 * D-15 ⑦ — ambient/잠금에서 금액을 가릴 플랫폼 수단이 없으므로(watchface-complications-data
 * 1.3.0 조사 결과는 98-06-SUMMARY.md 참조) 원형 컴플리케이션(SHORT_TEXT) 기본값은
 * **건수**. 금액 노출은 사용자가 나중에 명시적으로 허용할 때만 — 이 상수를 true 로 바꾸지
 * 않는다(바꾸려면 새 사용자 결정이 필요하다).
 */
const val MONTO_EN_CIRCULO = false

private const val OCULTO = "•••"

/** Tile 표시 문구 — 제목·큰 금액·2×2 칸(라벨+값)·하단 경과시간. */
data class TileTexts(
    val titulo: String,
    val monto: String,
    val celdas: List<Pair<String, String>>,
    val pie: String,
)

/** 원형(SHORT_TEXT) 컴플리케이션 표시 문구. */
data class ShortTexts(val text: String, val title: String)

fun tileTexts(state: ResumenState?, nowMillis: Long, bloqueado: Boolean): TileTexts =
    when (state) {
        null, is ResumenState.Unpaired -> sinValor()
        is ResumenState.Error -> sinDisponible()
        is ResumenState.Fresh -> tileTextsDeResumen(state.resumen, state.fetchedAt, nowMillis, bloqueado, stale = false)
        is ResumenState.Stale -> tileTextsDeResumen(state.resumen, state.fetchedAt, nowMillis, bloqueado, stale = true)
    }

private fun sinValor() = TileTexts(
    titulo = "HOY",
    monto = "—",
    celdas = emptyList(),
    pie = "Abrí la app para vincular",
)

private fun sinDisponible(titulo: String = "HOY") = TileTexts(
    titulo = titulo,
    monto = "—",
    celdas = emptyList(),
    pie = "No disponible",
)

private fun tileTextsDeResumen(
    resumen: Resumen,
    fetchedAt: Long,
    nowMillis: Long,
    bloqueado: Boolean,
    stale: Boolean,
): TileTexts {
    val titulo = tituloPara(resumen)
    val hoy = resumen.secciones.hoy.data ?: return sinDisponible(titulo)

    val pieBase = haceTexto(fetchedAt, nowMillis)
    val pie = if (stale) "Sin conexión · $pieBase" else pieBase

    val monto = if (bloqueado) OCULTO else abreviarMonto(hoy.total)
    val medios = resumen.secciones.mediosPago.data
    val gastos = resumen.secciones.gastosDescuentos.data
    val celdas = buildList {
        if (medios != null) {
            add("Efectivo" to if (bloqueado) OCULTO else abreviarMonto(medios.efectivo))
            add("Bancarias" to if (bloqueado) OCULTO else abreviarMonto(medios.bancarias))
        }
        if (gastos != null) {
            add("Gastos" to if (bloqueado) OCULTO else abreviarMonto(gastos.gastos.monto))
        }
        add("Ventas" to formatCantidad(hoy.ventas))
    }

    return TileTexts(titulo, monto, celdas, pie)
}

/** D-15 ⑦ — montoEnCirculo 는 기본값 [MONTO_EN_CIRCULO](false)로만 호출된다(서비스가 true 를 넘기지 않는다). */
fun complicationShort(
    state: ResumenState?,
    nowMillis: Long,
    bloqueado: Boolean,
    montoEnCirculo: Boolean = MONTO_EN_CIRCULO,
): ShortTexts {
    val resumen = resumenDe(state) ?: return ShortTexts("—", "")
    val hoy = resumen.secciones.hoy.data ?: return ShortTexts("—", "")

    val title = resumen.sucursal?.nombre ?: "ventas"
    val text = if (montoEnCirculo) {
        if (bloqueado) OCULTO else abreviarCorto(hoy.total)
    } else {
        formatCantidad(hoy.ventas)
    }
    return ShortTexts(text, title)
}

/** 막대(LONG_TEXT) — 건수만이라 잠금과 무관하게 같은 문자열(D-14 ② 가릴 금액이 없다). */
fun complicationLong(state: ResumenState?, nowMillis: Long, bloqueado: Boolean): String {
    val resumen = resumenDe(state) ?: return "—"
    val hoy = resumen.secciones.hoy.data ?: return "—"

    val sucursal = resumen.sucursal
    return if (sucursal != null) {
        "${sucursal.nombre} · ${hoy.ventas} ventas"
    } else {
        val abiertas = resumen.secciones.cajas.data?.abiertas ?: 0
        "${hoy.ventas} ventas · $abiertas cajas"
    }
}

private fun tituloPara(resumen: Resumen): String {
    val nombre = resumen.sucursal?.nombre ?: resumen.tienda
    return "HOY · ${nombre.uppercase()}"
}

private fun resumenDe(state: ResumenState?): Resumen? = when (state) {
    is ResumenState.Fresh -> state.resumen
    is ResumenState.Stale -> state.resumen
    else -> null
}
