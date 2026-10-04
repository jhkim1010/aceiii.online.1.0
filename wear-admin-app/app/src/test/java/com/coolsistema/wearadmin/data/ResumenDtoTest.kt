package com.coolsistema.wearadmin.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 응답 v2 의 단일 출처는 api-ventago 의 골든 JSON 이다(복사본 없이 직접 읽는다).
 * 파일이 없으면 이 시험은 실패해야 한다(건너뛰지 않는다) — 그래서 System.getProperty
 * 가 비어 있을 때 바로 require() 로 죽인다.
 */
private fun readGoldenText(): String {
    val path = System.getProperty("ventago.goldenJson")
    requireNotNull(path) { "ventago.goldenJson 시스템 프로퍼티가 설정되지 않았다" }
    val file = File(path)
    require(file.exists()) { "골든 JSON 파일이 없다: $path" }
    return file.readText()
}

class ResumenDtoTest {

    @Test
    fun `골든 JSON 을 그대로 파싱한다`() {
        val resumen = WatchJson.decodeFromString<Resumen>(readGoldenText())

        assertEquals(2, resumen.schemaVersion)
        assertEquals("ok", resumen.secciones.hoy.status)
        assertEquals("ok", resumen.secciones.mediosPago.status)
        assertEquals("ok", resumen.secciones.gastosDescuentos.status)
        assertEquals("ok", resumen.secciones.ingresos.status)
        assertEquals("ok", resumen.secciones.facturacionMes.status)
        assertEquals("ok", resumen.secciones.cajas.status)

        // 닫힌 서랍(box 4) 은 saldo·desde 가 null
        val once = resumen.secciones.cajas.data!!.porSucursal.first { it.id == 12 }
        val cerrada = once.cajas.first { !it.abierta }
        assertNull(cerrada.saldo)
        assertNull(cerrada.desde)

        // porSucursal 의 id 는 Int? (여기선 실제 지점이라 non-null 이지만 타입이 nullable)
        val idCentro: Int? = resumen.secciones.hoy.data!!.porSucursal.first().id
        assertEquals(11, idCentro)
    }

    @Test
    fun `한 섹션이 error 면 그 섹션만 data null, 나머지는 유지`() {
        val root = Json.parseToJsonElement(readGoldenText()).jsonObject
        val secciones = root["secciones"]!!.jsonObject

        val mutatedFacturacion = buildJsonObject {
            put("status", "error")
            put("asOf", JsonNull)
            put("periodStart", "2026-10-01")
            put("periodEnd", "2026-10-04")
            put("data", JsonNull)
        }
        val mutatedSecciones = buildJsonObject {
            secciones.forEach { (k, v) -> put(k, if (k == "facturacionMes") mutatedFacturacion else v) }
        }
        val mutatedRoot = buildJsonObject {
            root.forEach { (k, v) -> put(k, if (k == "secciones") mutatedSecciones else v) }
        }

        val resumen = WatchJson.decodeFromString<Resumen>(mutatedRoot.toString())

        assertEquals("error", resumen.secciones.facturacionMes.status)
        assertNull(resumen.secciones.facturacionMes.data)
        assertNotNull(resumen.secciones.hoy.data)
        assertNotNull(resumen.secciones.mediosPago.data)
        assertNotNull(resumen.secciones.gastosDescuentos.data)
        assertNotNull(resumen.secciones.ingresos.data)
        assertNotNull(resumen.secciones.cajas.data)
    }

    @Test
    fun `모르는 키는 무시된다`() {
        val root = Json.parseToJsonElement(readGoldenText()).jsonObject
        val mutatedRoot = buildJsonObject {
            root.forEach { (k, v) -> put(k, v) }
            put("campoDesconocidoFuturo", "lo que sea")
        }

        val resumen = WatchJson.decodeFromString<Resumen>(mutatedRoot.toString())

        assertEquals(2, resumen.schemaVersion)
    }

    @Test
    fun `sucursal con id y nombre se parsea`() {
        val root = Json.parseToJsonElement(readGoldenText()).jsonObject
        val mutatedSucursal = buildJsonObject {
            put("id", 12)
            put("nombre", "Once")
        }
        val mutatedRoot = buildJsonObject {
            root.forEach { (k, v) -> put(k, if (k == "sucursal") mutatedSucursal else v) }
        }

        val resumen = WatchJson.decodeFromString<Resumen>(mutatedRoot.toString())

        assertEquals("Once", resumen.sucursal?.nombre)
        assertEquals(12, resumen.sucursal?.id)
    }

    @Test
    fun `sucursal null se parsea como null (Todas)`() {
        val resumen = WatchJson.decodeFromString<Resumen>(readGoldenText())
        assertTrue(resumen.sucursal == null)
    }
}
