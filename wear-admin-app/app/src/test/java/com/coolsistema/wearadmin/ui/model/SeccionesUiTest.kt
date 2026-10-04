package com.coolsistema.wearadmin.ui.model

import com.coolsistema.wearadmin.data.FacturacionPorTipoRow
import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.data.WatchJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

private fun readGolden(): Resumen {
    val path = System.getProperty("ventago.goldenJson")
    requireNotNull(path) { "ventago.goldenJson 시스템 프로퍼티가 설정되지 않았다" }
    return WatchJson.decodeFromString(File(path).readText())
}

class SeccionesUiTest {

    private val golden = readGolden()
    private val now = 1_759_606_200_000L // golden.generadoEn 과 같은 순간(2026-10-04T19:30:00Z)

    // --- ① Hoy ---------------------------------------------------------

    @Test
    fun `hoy Todas muestra monto delta detalle ultima y sucursales por monto descendente`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val hoy = ui.hoy as SeccionUi.Lista
        assertEquals("VENTAS HOY", hoy.cabecera.label)
        assertEquals("TODAS ▾", hoy.cabecera.alcance)
        assertTrue(hoy.cabecera.alcanceTocable)
        assertEquals("$13,75 M", hoy.data.monto)
        assertEquals("▲ 12% vs ayer a esta hora", hoy.data.delta)
        assertEquals("46 ventas · 1.202 prendas", hoy.data.detalle)
        assertEquals("Última venta 16:28", hoy.data.ultima)
        assertEquals(
            listOf(
                HoySucursalResumen("Centro", "$9,84 M"),
                HoySucursalResumen("Once", "$3,91 M"),
            ),
            hoy.data.sucursales,
        )
    }

    @Test
    fun `hoy con sucursal seleccionada muestra alcance de esa sucursal y sin lista`() {
        val conSeleccion = golden.copy(sucursal = com.coolsistema.wearadmin.data.SucursalRef(12, "Once"))
        val ui = seccionesUi(ResumenState.Fresh(conSeleccion, now), now)
        val hoy = ui.hoy as SeccionUi.Lista
        assertEquals("ONCE ▾", hoy.cabecera.alcance)
        assertTrue(hoy.data.sucursales.isEmpty())
    }

    @Test
    fun `hoy sin ultima venta muestra Sin ventas hoy`() {
        val sinVentas = golden.copy(
            secciones = golden.secciones.copy(
                hoy = golden.secciones.hoy.copy(data = golden.secciones.hoy.data!!.copy(ultimaVenta = null)),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(sinVentas, now), now)
        val hoy = ui.hoy as SeccionUi.Lista
        assertEquals("Sin ventas hoy", hoy.data.ultima)
    }

    @Test
    fun `hoy sin base de ayer no muestra delta`() {
        val sinAyer = golden.copy(
            secciones = golden.secciones.copy(
                hoy = golden.secciones.hoy.copy(data = golden.secciones.hoy.data!!.copy(ayerMismaHora = 0.0)),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(sinAyer, now), now)
        val hoy = ui.hoy as SeccionUi.Lista
        assertEquals("", hoy.data.delta)
    }

    // --- ② Medios de pago -----------------------------------------------

    @Test
    fun `medios muestra 4 filas y la proporcion del anillo suma 1`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val medios = ui.mediosPago as SeccionUi.Lista
        assertEquals(
            listOf("Efectivo", "Bancarias", "Crédito", "Favor"),
            medios.data.filas.map { it.nombre },
        )
        assertEquals("$9,63 M", medios.data.filas[0].monto)
        assertEquals("$4,12 M", medios.data.filas[1].monto)
        assertEquals("$0", medios.data.filas[2].monto)
        assertEquals("$0", medios.data.filas[3].monto)
        val sumaProporciones = medios.data.filas.sumOf { it.proporcion }
        assertTrue(Math.abs(sumaProporciones - 1.0) < 0.0001)
    }

    @Test
    fun `medios Todas muestra porSucursal y pie con total y porcentaje`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val medios = ui.mediosPago as SeccionUi.Lista
        assertEquals(
            listOf(
                MedioSucursalResumen("Centro", "$7,02 M"),
                MedioSucursalResumen("Once", "$2,61 M"),
            ),
            medios.data.porSucursal,
        )
        assertEquals("Total $9,63 M · 70%", medios.data.pieSucursal)
    }

    @Test
    fun `medios con sucursal seleccionada no muestra porSucursal`() {
        val conSeleccion = golden.copy(sucursal = com.coolsistema.wearadmin.data.SucursalRef(12, "Once"))
        val ui = seccionesUi(ResumenState.Fresh(conSeleccion, now), now)
        val medios = ui.mediosPago as SeccionUi.Lista
        assertTrue(medios.data.porSucursal.isEmpty())
        assertNull(medios.data.pieSucursal)
    }

    // --- ③ Gastos y descuentos -----------------------------------------

    @Test
    fun `gastosDescuentos muestra montos y eventos`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val gd = ui.gastosDescuentos as SeccionUi.Lista
        assertEquals("GASTOS Y DESCUENTOS", gd.cabecera.label)
        assertEquals("$51 K", gd.data.gastosMonto)
        assertEquals("3 eventos", gd.data.gastosEventos)
        assertEquals("-$103 K", gd.data.descuentosMonto)
        assertEquals("5 eventos", gd.data.descuentosEventos)
    }

    // --- ④ Ingresos -------------------------------------------------------

    @Test
    fun `ingresos muestra cantidad detalle y sub-detalle`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val ing = ui.ingresos as SeccionUi.Lista
        assertEquals("INGRESOS DE MERCADERÍA", ing.cabecera.label)
        assertEquals("2.088", ing.data.cantidad)
        assertEquals("en 4 ingresos", ing.data.detalle)
        assertEquals("Compras 1.800 · Talleres 288", ing.data.subDetalle)
    }

    // --- ⑤ Facturación del mes -------------------------------------------

    @Test
    fun `facturacion muestra titulo con mes grande iva y tipos A y B siempre`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val fac = ui.facturacionMes as SeccionUi.Lista
        assertEquals("FACTURADO · OCT 2026", fac.cabecera.label)
        assertEquals("$9,17 M", fac.data.grande)
        assertEquals("IVA $1,59 M", fac.data.iva)
        assertEquals(
            listOf(
                FacturacionTipoFila("Tipo A", "$9,17 M"),
                FacturacionTipoFila("Tipo B", "$0"),
            ),
            fac.data.tipos,
        )
        assertNull(fac.data.aviso)
    }

    @Test
    fun `facturacion con tipo C solo lo muestra si esta presente`() {
        val conC = golden.copy(
            secciones = golden.secciones.copy(
                facturacionMes = golden.secciones.facturacionMes.copy(
                    data = golden.secciones.facturacionMes.data!!.copy(
                        porTipo = golden.secciones.facturacionMes.data!!.porTipo + FacturacionPorTipoRow("C", 50_000.0, 10_000.0, 1),
                    ),
                ),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(conC, now), now)
        val fac = ui.facturacionMes as SeccionUi.Lista
        assertEquals(
            listOf(
                FacturacionTipoFila("Tipo A", "$9,17 M"),
                FacturacionTipoFila("Tipo B", "$0"),
                FacturacionTipoFila("Tipo C", "$50 K"),
            ),
            fac.data.tipos,
        )
    }

    @Test
    fun `facturacion con comprobantes sin iva muestra aviso`() {
        val incompleto = golden.copy(
            secciones = golden.secciones.copy(
                facturacionMes = golden.secciones.facturacionMes.copy(
                    data = golden.secciones.facturacionMes.data!!.copy(comprobantesSinIva = 2),
                ),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(incompleto, now), now)
        val fac = ui.facturacionMes as SeccionUi.Lista
        assertEquals("IVA incompleto (2)", fac.data.aviso)
    }

    // --- ⑥ Cajas ------------------------------------------------------------

    @Test
    fun `cajas Todas agrupa por sucursal con subtotal y filas con punto y aviso`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        val cajas = ui.cajas as SeccionUi.Lista
        assertEquals("CAJAS · 3/4 ABIERTAS", cajas.cabecera.label)
        assertEquals("Efectivo en cajas $412 K", cajas.data.efectivoEnCajas)
        assertEquals(
            listOf(
                CajasGrupo(
                    "CENTRO · $303 K",
                    listOf(
                        CajaFila("●", "Caja 1", "$182 K", false),
                        CajaFila("●", "Caja 2", "$121 K", false),
                    ),
                ),
                CajasGrupo(
                    "ONCE · $109 K",
                    listOf(
                        CajaFila("●", "Once 1", "$109 K", false),
                        CajaFila("○", "Once 2", "cerrada", false),
                    ),
                ),
            ),
            cajas.data.grupos,
        )
        assertTrue(cajas.data.filas.isEmpty())
        assertNull(cajas.data.masOmitidas)
    }

    @Test
    fun `cajas marca aviso si quedo abierta de un dia anterior o tiene pendientes`() {
        val conAviso = golden.copy(
            secciones = golden.secciones.copy(
                cajas = golden.secciones.cajas.copy(
                    data = golden.secciones.cajas.data!!.copy(
                        porSucursal = golden.secciones.cajas.data!!.porSucursal.map { sucursal ->
                            sucursal.copy(
                                cajas = sucursal.cajas.map { caja ->
                                    if (caja.boxId == 1) caja.copy(abiertaDesdeDiaAnterior = true) else caja
                                },
                            )
                        },
                    ),
                ),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(conAviso, now), now)
        val cajas = ui.cajas as SeccionUi.Lista
        val caja1 = cajas.data.grupos.first().filas.first { it.nombre == "Caja 1" }
        assertTrue(caja1.aviso)
    }

    @Test
    fun `cajas omitidas mayor a 0 muestra mas omitidas`() {
        val conOmitidas = golden.copy(
            secciones = golden.secciones.copy(
                cajas = golden.secciones.cajas.copy(
                    data = golden.secciones.cajas.data!!.copy(omitidas = 2),
                ),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(conOmitidas, now), now)
        val cajas = ui.cajas as SeccionUi.Lista
        assertEquals("+2 más", cajas.data.masOmitidas)
    }

    @Test
    fun `CajasUi y CajaFila no tienen campo usuario (D-14)`() {
        val camposCajasUi = CajasUi::class.java.declaredFields.map { it.name }
        val camposCajaFila = CajaFila::class.java.declaredFields.map { it.name }
        assertFalse(camposCajasUi.any { it.contains("usuario", ignoreCase = true) })
        assertFalse(camposCajaFila.any { it.contains("usuario", ignoreCase = true) })
    }

    // --- 상태(status error / Stale / Fresh) ------------------------------

    @Test
    fun `seccion con status error es NoDisponible y las demas quedan normales`() {
        val conError = golden.copy(
            secciones = golden.secciones.copy(
                ingresos = golden.secciones.ingresos.copy(status = "error", data = null),
            ),
        )
        val ui = seccionesUi(ResumenState.Fresh(conError, now), now)
        assertTrue(ui.ingresos is SeccionUi.NoDisponible)
        assertTrue(ui.hoy is SeccionUi.Lista)
        assertTrue(ui.cajas is SeccionUi.Lista)
    }

    @Test
    fun `Stale muestra aviso Sin conexion en todas las secciones y tono gris`() {
        val fetchedAt = now - 12 * 60_000L
        val ui = seccionesUi(ResumenState.Stale(golden, fetchedAt), now)
        assertEquals("Sin conexión · hace 12 min", (ui.hoy as SeccionUi.Lista).cabecera.aviso)
        assertEquals(Tono.Gris, (ui.hoy as SeccionUi.Lista).cabecera.tono)
        assertNull((ui.hoy as SeccionUi.Lista).cabecera.pie)
        assertEquals(Tono.Gris, (ui.cajas as SeccionUi.Lista).cabecera.tono)
    }

    @Test
    fun `Fresh muestra pie con antiguedad y tono normal`() {
        val fetchedAt = now - 30_000L
        val ui = seccionesUi(ResumenState.Fresh(golden, fetchedAt), now)
        val hoy = ui.hoy as SeccionUi.Lista
        assertEquals(Tono.Normal, hoy.cabecera.tono)
        assertNull(hoy.cabecera.aviso)
        assertEquals("recién", hoy.cabecera.pie)
    }

    // --- D-15 ⑥ 지점 1개 매장 ---------------------------------------------

    @Test
    fun `tienda con una sola sucursal usa el nombre de la tienda sin flecha en todas las secciones`() {
        val unaSucursal = golden.copy(sucursales = listOf(golden.sucursales.first()))
        val ui = seccionesUi(ResumenState.Fresh(unaSucursal, now), now)

        for (seccion in listOf(ui.hoy, ui.mediosPago, ui.gastosDescuentos, ui.ingresos, ui.facturacionMes, ui.cajas)) {
            val cab = (seccion as SeccionUi.Lista<*>).cabecera
            assertEquals("NOIX", cab.alcance)
            assertFalse(cab.alcanceTocable)
        }
        assertTrue((ui.hoy as SeccionUi.Lista).data.sucursales.isEmpty())
        assertTrue((ui.mediosPago as SeccionUi.Lista).data.porSucursal.isEmpty())
        assertTrue((ui.cajas as SeccionUi.Lista).data.grupos.isEmpty())
        assertFalse((ui.cajas as SeccionUi.Lista).data.filas.isEmpty()) // 서랍 행은 그대로 남는다
    }

    @Test
    fun `tienda con dos sucursales tiene alcanceTocable true`() {
        val ui = seccionesUi(ResumenState.Fresh(golden, now), now)
        assertTrue((ui.hoy as SeccionUi.Lista).cabecera.alcanceTocable)
    }
}
