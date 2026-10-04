package com.coolsistema.wearadmin.format

import org.junit.Assert.assertEquals
import org.junit.Test

class TimeFormatTest {

    @Test
    fun `haceTexto menos de 1 minuto es recien`() {
        val t = 1_700_000_000_000L
        assertEquals("recién", haceTexto(t, t + 30_000L))
    }

    @Test
    fun `haceTexto minutos`() {
        val t = 1_700_000_000_000L
        assertEquals("hace 12 min", haceTexto(t, t + 12 * 60_000L))
    }

    @Test
    fun `haceTexto horas`() {
        val t = 1_700_000_000_000L
        val delta = (3 * 60 + 5) * 60_000L
        assertEquals("hace 3 h", haceTexto(t, t + delta))
    }

    @Test
    fun `haceTexto dias`() {
        val t = 1_700_000_000_000L
        val delta = 2 * 24 * 60 * 60_000L
        assertEquals("hace 2 días", haceTexto(t, t + delta))
    }

    @Test
    fun `mesCorto octubre`() {
        assertEquals("OCT 2026", mesCorto("2026-10"))
    }

    @Test
    fun `mesCorto enero`() {
        assertEquals("ENE 2026", mesCorto("2026-01"))
    }

    @Test
    fun `mesCorto agosto`() {
        assertEquals("AGO 2026", mesCorto("2026-08"))
    }
}
