package com.coolsistema.wearadmin.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.ConnectException

private fun readGoldenText(): String {
    val path = System.getProperty("ventago.goldenJson")
    requireNotNull(path) { "ventago.goldenJson 시스템 프로퍼티가 설정되지 않았다" }
    return File(path).readText()
}

private class FakeTokenStore(initial: String? = null) : TokenStore {
    var token: String? = initial
    var cleared = false

    override suspend fun getToken(): String? = token

    override suspend fun saveToken(token: String) {
        this.token = token
    }

    override suspend fun clearToken() {
        token = null
        cleared = true
    }
}

private class FakeWatchPrefs : WatchPrefs {
    private val sucursalFlow = MutableStateFlow<Int?>(null)
    private var last: LastResumen? = null
    var lastCleared = false

    override val sucursalId: Flow<Int?> = sucursalFlow

    override suspend fun setSucursal(id: Int?) {
        sucursalFlow.value = id
    }

    override suspend fun saveLast(json: String, fetchedAt: Long, sucursalId: Int?) {
        last = LastResumen(json, fetchedAt, sucursalId)
    }

    override suspend fun getLast(): LastResumen? = last

    override suspend fun clearLast() {
        last = null
        lastCleared = true
    }

    fun seedLast(json: String, fetchedAt: Long, sucursalId: Int?) {
        last = LastResumen(json, fetchedAt, sucursalId)
    }

    fun setSucursalDirect(id: Int?) {
        sucursalFlow.value = id
    }
}

class ResumenRepositoryTest {

    private lateinit var server: MockWebServer
    private lateinit var tokenStore: FakeTokenStore
    private lateinit var prefs: FakeWatchPrefs
    private lateinit var repository: ResumenRepository
    private val golden by lazy { readGoldenText() }

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        tokenStore = FakeTokenStore()
        prefs = FakeWatchPrefs()
        val api = WatchApi.create(server.url("/").toString())
        repository = ResumenRepository(api, tokenStore, prefs)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `fetch sin token es Unpaired y no hace requests`() = runTest {
        val state = repository.fetch()

        assertTrue(state is ResumenState.Unpaired)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `fetch 200 es Fresh y guarda el ultimo valor`() = runTest {
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Fresh)
        val fresh = state as ResumenState.Fresh
        assertEquals(2, fresh.resumen.schemaVersion)
        val last = prefs.getLast()
        assertEquals(golden, last?.json)
    }

    @Test
    fun `fetch con sucursal seleccionada manda query sucursal`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(12)
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        repository.fetch()

        val recorded = server.takeRequest()
        assertTrue(recorded.path!!.contains("sucursal=12"))
    }

    @Test
    fun `fetch sin sucursal no manda query sucursal`() = runTest {
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        repository.fetch()

        val recorded = server.takeRequest()
        assertFalse(recorded.path!!.contains("sucursal="))
    }

    @Test
    fun `fetch header x-watch-token sin Authorization y sin token en la URL`() = runTest {
        tokenStore.token = "tok-secreto"
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        repository.fetch()

        val recorded = server.takeRequest()
        assertEquals("tok-secreto", recorded.getHeader("x-watch-token"))
        assertNull(recorded.getHeader("Authorization"))
        assertFalse(recorded.path!!.contains("tok-secreto"))
    }

    @Test
    fun `fetch 400 reintenta una vez sin sucursal y resuelve Fresh`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(99)
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"message":"Sucursal inválida"}"""))
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Fresh)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `fetch 400 dos veces es Error`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(99)
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"message":"Sucursal inválida"}"""))
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"message":"Sucursal inválida"}"""))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Error)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `fetch 401 limpia token y cache y vuelve Unpaired`() = runTest {
        tokenStore.token = "tok-1"
        prefs.seedLast(golden, 1000L, null)
        server.enqueue(MockResponse().setResponseCode(401))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Unpaired)
        assertNull(tokenStore.token)
        assertTrue(tokenStore.cleared)
        assertTrue(prefs.lastCleared)
    }

    @Test
    fun `fetch con error de red y cache de la misma sucursal es Stale`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(12)
        prefs.seedLast(golden, 1000L, 12)
        server.shutdown() // fuerza ConnectException (IOException)

        val state = repository.fetch()

        assertTrue(state is ResumenState.Stale)
        val stale = state as ResumenState.Stale
        assertEquals(1000L, stale.fetchedAt)
    }

    @Test
    fun `fetch con error de red y cache de otra sucursal es Error`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(12)
        prefs.seedLast(golden, 1000L, 99)
        server.shutdown()

        val state = repository.fetch()

        assertTrue(state is ResumenState.Error)
    }

    @Test
    fun `fetch 5xx con cache de la misma sucursal es Stale`() = runTest {
        tokenStore.token = "tok-1"
        prefs.setSucursalDirect(null)
        prefs.seedLast(golden, 2000L, null)
        server.enqueue(MockResponse().setResponseCode(503))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Stale)
    }

    @Test
    fun `fetch 5xx sin cache es Error`() = runTest {
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(503))

        val state = repository.fetch()

        assertTrue(state is ResumenState.Error)
    }

    @Test
    fun `requestCode devuelve PairingCode`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(201).setBody(
                """{"userCode":"K7Q4-29XM","deviceCode":"abc123","expiresIn":300,"interval":5}""",
            ),
        )

        val code = repository.requestCode(null)

        assertEquals("K7Q4-29XM", code.userCode)
        assertEquals(5, code.interval)
    }

    @Test
    fun `poll 202 es Pending`() = runTest {
        server.enqueue(MockResponse().setResponseCode(202).setBody("""{"status":"pending"}"""))

        val result = repository.poll("device-1")

        assertTrue(result is PollResult.Pending)
    }

    @Test
    fun `poll 200 guarda token y es Paired`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"watchToken":"nuevo-token","expiresAt":"2027-01-01T00:00:00.000Z"}""",
            ),
        )

        val result = repository.poll("device-1")

        assertTrue(result is PollResult.Paired)
        assertEquals("nuevo-token", tokenStore.token)
    }

    @Test
    fun `poll 410 es Expired`() = runTest {
        server.enqueue(MockResponse().setResponseCode(410).setBody("""{"status":"expired"}"""))

        val result = repository.poll("device-1")

        assertTrue(result is PollResult.Expired)
    }

    @Test
    fun `setSucursal guarda seleccion y borra el ultimo valor`() = runTest {
        prefs.seedLast(golden, 1000L, 11)

        repository.setSucursal(12)

        assertEquals(12, prefs.sucursalId.first())
        assertTrue(prefs.lastCleared)
    }

    // --- onChanged (98-06, requestAll de SurfaceUpdater vía AppGraph) ---

    @Test
    fun `fetch 200 Fresh llama onChanged una vez`() = runTest {
        var calls = 0
        val repoConCallback = ResumenRepository(
            WatchApi.create(server.url("/").toString()),
            tokenStore,
            prefs,
            onChanged = { calls++ },
        )
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        repoConCallback.fetch()

        assertEquals(1, calls)
    }

    @Test
    fun `fetch 401 Unpaired llama onChanged una vez`() = runTest {
        var calls = 0
        val repoConCallback = ResumenRepository(
            WatchApi.create(server.url("/").toString()),
            tokenStore,
            prefs,
            onChanged = { calls++ },
        )
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(401))

        repoConCallback.fetch()

        assertEquals(1, calls)
    }

    @Test
    fun `fetch con notify=false no llama onChanged`() = runTest {
        var calls = 0
        val repoConCallback = ResumenRepository(
            WatchApi.create(server.url("/").toString()),
            tokenStore,
            prefs,
            onChanged = { calls++ },
        )
        tokenStore.token = "tok-1"
        server.enqueue(MockResponse().setResponseCode(200).setBody(golden))

        repoConCallback.fetch(notify = false)

        assertEquals(0, calls)
    }
}
