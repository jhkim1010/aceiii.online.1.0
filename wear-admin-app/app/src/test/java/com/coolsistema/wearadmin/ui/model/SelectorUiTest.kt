package com.coolsistema.wearadmin.ui.model

import com.coolsistema.wearadmin.data.Resumen
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

class SelectorUiTest {

    private val golden = readGolden()

    @Test
    fun `sin seleccion Todas aparece elegida con el total de la tienda`() {
        val opciones = selectorUi(golden, seleccion = null)

        assertEquals(
            listOf(
                OpcionSucursal(null, "Todas", "$13,75 M", elegida = true),
                OpcionSucursal(11, "Centro", "$9,84 M", elegida = false),
                OpcionSucursal(12, "Once", "$3,91 M", elegida = false),
            ),
            opciones,
        )
    }

    @Test
    fun `con sucursal seleccionada esa opcion queda elegida y Todas no`() {
        val opciones = selectorUi(golden, seleccion = 12)

        val todas = opciones.first { it.id == null }
        val once = opciones.first { it.id == 12 }
        val centro = opciones.first { it.id == 11 }
        assertTrue(!todas.elegida)
        assertTrue(once.elegida)
        assertTrue(!centro.elegida)
    }

    @Test
    fun `tienda con una sola sucursal no ofrece selector (D-15 6)`() {
        val unaSucursal = golden.copy(sucursales = listOf(golden.sucursales.first()))

        val opciones = selectorUi(unaSucursal, seleccion = 11)

        assertTrue(opciones.isEmpty())
    }
}
