package com.coolsistema.wearadmin.surface

import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.data.SucursalRef
import com.coolsistema.wearadmin.data.WatchJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

private fun readGolden(): Resumen {
    val path = System.getProperty("ventago.goldenJson")
    requireNotNull(path) { "ventago.goldenJson 시스템 프로퍼티가 설정되지 않았다" }
    return WatchJson.decodeFromString(File(path).readText())
}

/**
 * 표면(Tile·컴플리케이션) 문구 순수 함수 시험 — 지점·잠금 가림·오프라인·미연결 규칙(D-07·D-09·D-14·D-15 ⑦)을 고정.
 */
class SurfaceTextsTest {

    private val golden = readGolden()
    private val t0 = 1_000_000_000L

    private fun conSucursalOnce(resumen: Resumen): Resumen =
        resumen.copy(sucursal = SucursalRef(12, "Once"))

    private fun conSucursalOnceVentas16(resumen: Resumen): Resumen {
        val hoySeccion = resumen.secciones.hoy
        val hoyData = requireNotNull(hoySeccion.data)
        val onceRow = hoyData.porSucursal.first { it.id == 12 }
        return resumen.copy(
            sucursal = SucursalRef(12, "Once"),
            secciones = resumen.secciones.copy(
                hoy = hoySeccion.copy(data = hoyData.copy(total = onceRow.total, ventas = onceRow.ventas)),
            ),
        )
    }

    private fun conHoyEnError(resumen: Resumen): Resumen =
        resumen.copy(secciones = resumen.secciones.copy(hoy = resumen.secciones.hoy.copy(status = "error", data = null)))

    // --- tileTexts ---

    @Test
    fun `tileTexts Fresh golden sin bloquear`() {
        val texts = tileTexts(ResumenState.Fresh(golden, t0), t0 + 12 * 60_000, bloqueado = false)

        assertEquals("HOY · NOIX", texts.titulo)
        assertEquals("$13,75 M", texts.monto)
        assertEquals(
            listOf("Efectivo" to "$9,63 M", "Bancarias" to "$4,12 M", "Gastos" to "$51 K", "Ventas" to "46"),
            texts.celdas,
        )
        assertEquals("hace 12 min", texts.pie)
    }

    @Test
    fun `tileTexts titulo usa sucursal seleccionada`() {
        val texts = tileTexts(ResumenState.Fresh(conSucursalOnce(golden), t0), t0 + 12 * 60_000, bloqueado = false)

        assertEquals("HOY · ONCE", texts.titulo)
    }

    @Test
    fun `tileTexts bloqueado oculta montos pero no el conteo de ventas`() {
        val texts = tileTexts(ResumenState.Fresh(golden, t0), t0 + 12 * 60_000, bloqueado = true)

        assertEquals("•••", texts.monto)
        assertEquals(
            listOf("Efectivo" to "•••", "Bancarias" to "•••", "Gastos" to "•••", "Ventas" to "46"),
            texts.celdas,
        )
        assertEquals("hace 12 min", texts.pie)
    }

    @Test
    fun `tileTexts Stale muestra Sin conexion`() {
        val texts = tileTexts(ResumenState.Stale(golden, t0), t0 + 12 * 60_000, bloqueado = false)

        assertEquals("Sin conexión · hace 12 min", texts.pie)
    }

    @Test
    fun `tileTexts Unpaired no tiene valor`() {
        val texts = tileTexts(ResumenState.Unpaired, t0, bloqueado = false)

        assertEquals("—", texts.monto)
        assertTrue(texts.celdas.isEmpty())
        assertEquals("Abrí la app para vincular", texts.pie)
    }

    @Test
    fun `tileTexts hoy en error no tiene valor`() {
        val texts = tileTexts(ResumenState.Fresh(conHoyEnError(golden), t0), t0, bloqueado = false)

        assertEquals("—", texts.monto)
        assertEquals("No disponible", texts.pie)
    }

    // --- complicationShort (D-15 ⑦) ---

    @Test
    fun `complicationShort default es conteo no monto`() {
        val short = complicationShort(ResumenState.Fresh(golden, t0), t0, bloqueado = false)

        assertEquals("46", short.text)
        assertEquals("ventas", short.title)
    }

    @Test
    fun `complicationShort con sucursal seleccionada muestra su conteo y nombre`() {
        val resumen = conSucursalOnceVentas16(golden)
        val short = complicationShort(ResumenState.Fresh(resumen, t0), t0, bloqueado = false)

        assertEquals("16", short.text)
        assertEquals("Once", short.title)
    }

    @Test
    fun `complicationShort bloqueado no cambia el conteo (D-15 no hay monto que ocultar)`() {
        val short = complicationShort(ResumenState.Fresh(golden, t0), t0, bloqueado = true)

        assertEquals("46", short.text)
    }

    @Test
    fun `complicationShort Unpaired es guion`() {
        val short = complicationShort(ResumenState.Unpaired, t0, bloqueado = false)

        assertEquals("—", short.text)
    }

    @Test
    fun `complicationShort hoy en error es guion`() {
        val short = complicationShort(ResumenState.Fresh(conHoyEnError(golden), t0), t0, bloqueado = false)

        assertEquals("—", short.text)
    }

    @Test
    fun `MONTO_EN_CIRCULO es false por defecto (D-15 decision del usuario requerida para cambiarlo)`() {
        assertEquals(false, MONTO_EN_CIRCULO)
    }

    @Test
    fun `complicationShort con montoEnCirculo explicito true sin bloquear muestra monto abreviado`() {
        val short = complicationShort(ResumenState.Fresh(golden, t0), t0, bloqueado = false, montoEnCirculo = true)

        assertEquals("13,8M", short.text)
    }

    @Test
    fun `complicationShort con montoEnCirculo explicito true bloqueado oculta el monto`() {
        val short = complicationShort(ResumenState.Fresh(golden, t0), t0, bloqueado = true, montoEnCirculo = true)

        assertEquals("•••", short.text)
    }

    // --- complicationLong ---

    @Test
    fun `complicationLong Todas combina ventas y cajas abiertas`() {
        val long = complicationLong(ResumenState.Fresh(golden, t0), t0, bloqueado = false)

        assertEquals("46 ventas · 3 cajas", long)
    }

    @Test
    fun `complicationLong con sucursal seleccionada combina nombre y su conteo`() {
        val resumen = conSucursalOnceVentas16(golden)
        val long = complicationLong(ResumenState.Fresh(resumen, t0), t0, bloqueado = false)

        assertEquals("Once · 16 ventas", long)
    }

    @Test
    fun `complicationLong es igual bloqueado (solo conteo, nada que ocultar)`() {
        val desbloqueado = complicationLong(ResumenState.Fresh(golden, t0), t0, bloqueado = false)
        val bloqueado = complicationLong(ResumenState.Fresh(golden, t0), t0, bloqueado = true)

        assertEquals(desbloqueado, bloqueado)
    }
}
