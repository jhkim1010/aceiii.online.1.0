package com.coolsistema.wearadmin.ui

import com.coolsistema.wearadmin.data.PairingCodeDto
import com.coolsistema.wearadmin.data.PairingHttpException
import com.coolsistema.wearadmin.data.PollResult
import com.coolsistema.wearadmin.data.ResumenSource
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.ui.pairing.PairingUi
import com.coolsistema.wearadmin.ui.pairing.PairingViewModel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** 페어링 흐름을 전부 제어하는 가짜 — 실제 네트워크가 없으므로 가상 시간이 그대로 결정적이다. */
private class FakePairingSource : ResumenSource {
    val codes = ArrayDeque<Any>() // PairingCodeDto 또는 Exception
    val pollResults = ArrayDeque<PollResult>()
    var requestCodeCallCount = 0
    var pollCallCount = 0
    val polledDeviceCodes = mutableListOf<String>()

    override suspend fun fetch(): ResumenState = throw NotImplementedError("PairingViewModel 은 fetch 를 쓰지 않는다")

    override suspend fun setSucursal(id: Int?) {
        throw NotImplementedError("PairingViewModel 은 setSucursal 을 쓰지 않는다")
    }

    override suspend fun requestCode(model: String?): PairingCodeDto {
        requestCodeCallCount++
        val next = codes.removeFirstOrNull() ?: error("no hay más códigos configurados")
        if (next is Exception) throw next
        return next as PairingCodeDto
    }

    override suspend fun poll(deviceCode: String): PollResult {
        pollCallCount++
        polledDeviceCodes.add(deviceCode)
        return pollResults.removeFirstOrNull() ?: PollResult.Pending
    }
}

class PairingViewModelTest {

    @Test
    fun `start pide un codigo y muestra ShowCode con expiresIn`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()

        val state = vm.uiState.value
        assertTrue(state is PairingUi.ShowCode)
        assertEquals("K7Q4-29XM", (state as PairingUi.ShowCode).userCode)
        assertEquals(300, state.secondsLeft)
    }

    @Test
    fun `no llama a poll antes del interval (RFC 8628 parrafo 3 punto 5)`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()
        advanceTimeBy(4_900)
        runCurrent()

        assertEquals(0, source.pollCallCount)
    }

    @Test
    fun `llama a poll exactamente una vez al llegar al interval`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(1, source.pollCallCount)
        assertEquals("dev-1", source.polledDeviceCodes.first())
    }

    @Test
    fun `poll Pending repite y sigue mostrando el mismo codigo`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        source.pollResults.add(PollResult.Pending)
        source.pollResults.add(PollResult.Pending)
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(2, source.pollCallCount)
        val state = vm.uiState.value
        assertTrue(state is PairingUi.ShowCode)
        assertEquals("K7Q4-29XM", (state as PairingUi.ShowCode).userCode)
    }

    @Test
    fun `poll Paired deja el estado en Paired y detiene el polling`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        source.pollResults.add(PollResult.Paired)
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        advanceUntilIdle()

        assertTrue(vm.uiState.value is PairingUi.Paired)
        val countAfterPaired = source.pollCallCount
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(countAfterPaired, source.pollCallCount)
    }

    @Test
    fun `poll Expired pide un nuevo codigo automaticamente`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        source.codes.add(PairingCodeDto("NEW1-CODE", "dev-2", 300, 5))
        source.pollResults.add(PollResult.Expired)
        source.pollResults.add(PollResult.Pending)
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(2, source.requestCodeCallCount)
        val state = vm.uiState.value
        assertTrue(state is PairingUi.ShowCode)
        assertEquals("NEW1-CODE", (state as PairingUi.ShowCode).userCode)
    }

    @Test
    fun `secondsLeft llegando a 0 sin respuesta pide un nuevo codigo`() = runTest {
        val source = FakePairingSource()
        // expiresIn 10, interval 5 -> dos polls agotan el tiempo sin pairing.
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 10, 5))
        source.codes.add(PairingCodeDto("NEW1-CODE", "dev-2", 300, 5))
        source.pollResults.add(PollResult.Pending)
        source.pollResults.add(PollResult.Pending)
        source.pollResults.add(PollResult.Pending)
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(2, source.requestCodeCallCount)
        val state = vm.uiState.value
        assertTrue(state is PairingUi.ShowCode)
        assertEquals("NEW1-CODE", (state as PairingUi.ShowCode).userCode)
    }

    @Test
    fun `requestCode con error de red muestra Sin conexion y reintenta a los 10 segundos`() = runTest {
        val source = FakePairingSource()
        source.codes.add(IOException("sin conexión"))
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()

        assertEquals(PairingUi.Error("Sin conexión"), vm.uiState.value)
        assertEquals(1, source.requestCodeCallCount)

        advanceTimeBy(9_900)
        runCurrent()
        assertEquals(1, source.requestCodeCallCount)

        advanceTimeBy(100)
        runCurrent()
        assertEquals(2, source.requestCodeCallCount)
        assertTrue(vm.uiState.value is PairingUi.ShowCode)
    }

    @Test
    fun `requestCode con 429 muestra Demasiados intentos y reintenta a los 60 segundos`() = runTest {
        val source = FakePairingSource()
        source.codes.add(PairingHttpException(429))
        source.codes.add(PairingCodeDto("K7Q4-29XM", "dev-1", 300, 5))
        val vm = PairingViewModel(source, StandardTestDispatcher(testScheduler))

        vm.start(null)
        runCurrent()

        assertEquals(PairingUi.Error("Demasiados intentos"), vm.uiState.value)

        advanceTimeBy(59_900)
        runCurrent()
        assertEquals(1, source.requestCodeCallCount)

        advanceTimeBy(100)
        runCurrent()
        assertEquals(2, source.requestCodeCallCount)
        assertTrue(vm.uiState.value is PairingUi.ShowCode)
    }
}
