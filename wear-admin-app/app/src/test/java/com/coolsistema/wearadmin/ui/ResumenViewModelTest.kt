package com.coolsistema.wearadmin.ui

import com.coolsistema.wearadmin.data.PairingCodeDto
import com.coolsistema.wearadmin.data.PollResult
import com.coolsistema.wearadmin.data.ResumenSource
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.data.WatchJson
import com.coolsistema.wearadmin.ui.resumen.ResumenViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

private fun readGoldenText(): String {
    val path = System.getProperty("ventago.goldenJson")
    requireNotNull(path) { "ventago.goldenJson 시스템 프로퍼티가 설정되지 않았다" }
    return File(path).readText()
}

/** 저장 지점 선택 + fetch 결과를 전부 수동으로 제어하는 가짜 — 실제 네트워크 없이 결정적. */
private class FakeResumenSource(private val golden: String) : ResumenSource {
    var sucursalId: Int? = null
    val setSucursalCalls = mutableListOf<Int?>()
    val fetchSucursalIds = mutableListOf<Int?>()
    val fetchResponses = ArrayDeque<ResumenState>()
    private var defaultResponse: ResumenState = ResumenState.Fresh(WatchJson.decodeFromString(golden), 1_000L)

    fun enqueue(state: ResumenState) {
        fetchResponses.addLast(state)
    }

    fun setDefault(state: ResumenState) {
        defaultResponse = state
    }

    override suspend fun fetch(): ResumenState {
        delay(1) // 진짜 중단점 하나 — refreshing 플래그가 중간 상태로 관찰 가능해야 한다.
        fetchSucursalIds.add(sucursalId)
        return fetchResponses.removeFirstOrNull() ?: defaultResponse
    }

    override suspend fun setSucursal(id: Int?) {
        setSucursalCalls.add(id)
        sucursalId = id
    }

    override suspend fun requestCode(model: String?): PairingCodeDto =
        throw NotImplementedError("ResumenViewModel 은 requestCode 를 쓰지 않는다")

    override suspend fun poll(deviceCode: String): PollResult =
        throw NotImplementedError("ResumenViewModel 은 poll 을 쓰지 않는다")
}

class ResumenViewModelTest {

    private val golden by lazy { readGoldenText() }

    @Test
    fun `refresh con Unpaired actualiza el estado y emite onUnpaired`() = runTest {
        val source = FakeResumenSource(golden)
        source.setDefault(ResumenState.Unpaired)
        val vm = ResumenViewModel(source, backgroundScope)
        val events = mutableListOf<Unit>()
        backgroundScope.launch { vm.onUnpaired.collect { events.add(it) } }
        runCurrent()

        vm.refresh()
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertTrue(vm.state.value is ResumenState.Unpaired)
        assertEquals(1, events.size)
    }

    @Test
    fun `refresh con Fresh actualiza el estado y refreshing vuelve a false`() = runTest {
        val source = FakeResumenSource(golden)
        val vm = ResumenViewModel(source, backgroundScope)

        assertFalse(vm.refreshing.value)
        vm.refresh()
        runCurrent()
        assertTrue(vm.refreshing.value) // fetch 가 delay(1) 중단점에 머물러 있다.

        advanceTimeBy(1)
        runCurrent()
        assertFalse(vm.refreshing.value)
        assertTrue(vm.state.value is ResumenState.Fresh)
        assertEquals(1, source.fetchSucursalIds.size)
    }

    @Test
    fun `llamadas concurrentes a refresh se fusionan en un solo fetch`() = runTest {
        val source = FakeResumenSource(golden)
        val vm = ResumenViewModel(source, backgroundScope)

        vm.refresh()
        vm.refresh()
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertEquals(1, source.fetchSucursalIds.size)
    }

    @Test
    fun `onResume dispara un refresh`() = runTest {
        val source = FakeResumenSource(golden)
        val vm = ResumenViewModel(source, backgroundScope)

        vm.onResume()
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertEquals(1, source.fetchSucursalIds.size)
        assertTrue(vm.state.value is ResumenState.Fresh)
    }

    @Test
    fun `selectSucursal(12) guarda la seleccion y vuelve a pedir con esa sucursal`() = runTest {
        val source = FakeResumenSource(golden)
        val vm = ResumenViewModel(source, backgroundScope)

        vm.selectSucursal(12)
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertEquals(listOf(12), source.setSucursalCalls)
        assertEquals(12, source.sucursalId)
        assertEquals(listOf(12), source.fetchSucursalIds)
    }

    @Test
    fun `selectSucursal(null) vuelve a Todas`() = runTest {
        val source = FakeResumenSource(golden)
        source.sucursalId = 12
        val vm = ResumenViewModel(source, backgroundScope)

        vm.selectSucursal(null)
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertEquals(listOf(null), source.setSucursalCalls)
        assertNull(source.sucursalId)
        assertEquals(listOf<Int?>(null), source.fetchSucursalIds)
    }

    @Test
    fun `respuesta de sucursal unica borra la seleccion guardada y vuelve a pedir sin sucursal`() = runTest {
        val source = FakeResumenSource(golden)
        source.sucursalId = 11
        val estrechado = WatchJson.decodeFromString<com.coolsistema.wearadmin.data.Resumen>(golden).copy(
            sucursal = com.coolsistema.wearadmin.data.SucursalRef(11, "Centro"),
            sucursales = listOf(com.coolsistema.wearadmin.data.SucursalResumenRow(11, "Centro", 100.0)),
        )
        val sinSeleccion = estrechado.copy(sucursal = null)
        source.enqueue(ResumenState.Fresh(estrechado, 1_000L))
        source.enqueue(ResumenState.Fresh(sinSeleccion, 2_000L))
        val vm = ResumenViewModel(source, backgroundScope)

        vm.refresh()
        runCurrent()
        advanceTimeBy(1)
        runCurrent()
        advanceTimeBy(1)
        runCurrent()

        assertEquals(listOf(11, null), source.fetchSucursalIds)
        assertEquals(listOf(null), source.setSucursalCalls)
        assertNull(source.sucursalId)
        val finalState = vm.state.value
        assertTrue(finalState is ResumenState.Fresh)
        assertNull((finalState as ResumenState.Fresh).resumen.sucursal)

        // 이후 refresh 도 ?sucursal 없이(저장된 선택이 이미 null) — setSucursal 을 또 부르지 않는다.
        source.enqueue(ResumenState.Fresh(sinSeleccion, 3_000L))
        vm.refresh()
        runCurrent()
        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf(11, null, null), source.fetchSucursalIds)
        assertEquals(listOf(null), source.setSucursalCalls)
    }
}
