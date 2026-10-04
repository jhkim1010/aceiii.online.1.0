package com.coolsistema.wearadmin.format

import org.junit.Assert.assertEquals
import org.junit.Test

class AmountFormatTest {

    // --- abreviarMonto: millones ---

    @Test
    fun `abreviarMonto 1284500 redondea a 1,28 M`() {
        assertEquals("$1,28 M", abreviarMonto(1_284_500.0))
    }

    @Test
    fun `abreviarMonto 1285000 redondea HALF_UP a 1,29 M`() {
        assertEquals("$1,29 M", abreviarMonto(1_285_000.0))
    }

    @Test
    fun `abreviarMonto 12000000 muestra dos decimales exactos`() {
        assertEquals("$12,00 M", abreviarMonto(12_000_000.0))
    }

    @Test
    fun `abreviarMonto 15170000`() {
        assertEquals("$15,17 M", abreviarMonto(15_170_000.0))
    }

    // --- abreviarMonto: miles ---

    @Test
    fun `abreviarMonto 842000 en miles`() {
        assertEquals("$842 K", abreviarMonto(842_000.0))
    }

    @Test
    fun `abreviarMonto 842600 redondea a 843 K`() {
        assertEquals("$843 K", abreviarMonto(842_600.0))
    }

    @Test
    fun `abreviarMonto 999600 redondeo de K sube a millones`() {
        assertEquals("$1,00 M", abreviarMonto(999_600.0))
    }

    // --- abreviarMonto: debajo de mil ---

    @Test
    fun `abreviarMonto 999 se muestra entero`() {
        assertEquals("$999", abreviarMonto(999.0))
    }

    @Test
    fun `abreviarMonto 0`() {
        assertEquals("$0", abreviarMonto(0.0))
    }

    @Test
    fun `abreviarMonto 999,6 redondea a 1 K no a 1000`() {
        assertEquals("$1 K", abreviarMonto(999.6))
    }

    // --- abreviarMonto: negativos ---

    @Test
    fun `abreviarMonto negativo 15000`() {
        assertEquals("-$15 K", abreviarMonto(-15_000.0))
    }

    @Test
    fun `abreviarMonto negativo 103000`() {
        assertEquals("-$103 K", abreviarMonto(-103_000.0))
    }

    // --- abreviarCorto (SHORT_TEXT, sin $, 7 caracteres) ---

    @Test
    fun `abreviarCorto 15170000`() {
        assertEquals("15,2M", abreviarCorto(15_170_000.0))
    }

    @Test
    fun `abreviarCorto 3910000`() {
        assertEquals("3,9M", abreviarCorto(3_910_000.0))
    }

    @Test
    fun `abreviarCorto 842000`() {
        assertEquals("842K", abreviarCorto(842_000.0))
    }

    @Test
    fun `abreviarCorto 999`() {
        assertEquals("999", abreviarCorto(999.0))
    }

    @Test
    fun `abreviarCorto 125400000 sin decimales sobre 100M`() {
        assertEquals("125M", abreviarCorto(125_400_000.0))
    }

    // --- deltaPct ---

    @Test
    fun `deltaPct calcula aumento`() {
        assertEquals(17, deltaPct(1_284_500.0, 1_102_300.0))
    }

    @Test
    fun `deltaPct con base 0 es null`() {
        assertEquals(null, deltaPct(100.0, 0.0))
    }

    @Test
    fun `deltaPct calcula baja`() {
        assertEquals(-50, deltaPct(50.0, 100.0))
    }

    // --- formatDelta ---

    @Test
    fun `formatDelta positivo`() {
        assertEquals("▲ 12% vs ayer a esta hora", formatDelta(12))
    }

    @Test
    fun `formatDelta negativo`() {
        assertEquals("▼ 4% vs ayer a esta hora", formatDelta(-4))
    }

    @Test
    fun `formatDelta cero`() {
        assertEquals("= vs ayer a esta hora", formatDelta(0))
    }

    @Test
    fun `formatDelta null es vacio`() {
        assertEquals("", formatDelta(null))
    }

    // --- formatCantidad ---

    @Test
    fun `formatCantidad miles con punto`() {
        assertEquals("1.398", formatCantidad(1398))
    }

    @Test
    fun `formatCantidad sin separador`() {
        assertEquals("55", formatCantidad(55))
    }

    @Test
    fun `formatCantidad millones con puntos`() {
        assertEquals("1.234.567", formatCantidad(1_234_567))
    }

    @Test
    fun `formatCantidad negativo`() {
        assertEquals("-3", formatCantidad(-3))
    }
}
