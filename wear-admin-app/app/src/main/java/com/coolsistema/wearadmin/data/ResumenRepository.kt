package com.coolsistema.wearadmin.data

import kotlinx.coroutines.flow.firstOrNull
import java.io.IOException

sealed class ResumenState {
    data object Unpaired : ResumenState()
    data class Fresh(val resumen: Resumen, val fetchedAt: Long) : ResumenState()
    data class Stale(val resumen: Resumen, val fetchedAt: Long) : ResumenState()
    data class Error(val message: String) : ResumenState()
}

sealed class PollResult {
    data object Pending : PollResult()
    data object Paired : PollResult()
    data object Expired : PollResult()
}

/**
 * [ResumenRepository] 의 계약 — 뷰모델(98-04)이 이 인터페이스에만 의존해 페이크로
 * 시험할 수 있게 뽑았다(가상 시간 폴링 시험은 실제 네트워크 I/O 와 섞이면 결정적이지 않다).
 */
interface ResumenSource {
    suspend fun fetch(notify: Boolean = true): ResumenState
    suspend fun setSucursal(id: Int?)
    suspend fun requestCode(model: String?): PairingCodeDto
    suspend fun poll(deviceCode: String): PollResult
}

/** requestCode 가 2xx 가 아닌 응답을 받았을 때(429 포함) — PairingViewModel 이 코드별로 다르게 처리한다. */
class PairingHttpException(val code: Int) : Exception("Pairing request failed with HTTP $code")

/**
 * 워치 데이터 계층의 단일 진입점. 지점 선택·400 복구(Todas 로 1회 재시도)·401 정리
 * (토큰+캐시 삭제)·오프라인 1값(다른 지점이면 Stale 아님, T-98-25)을 전부 여기서 결정한다.
 */
class ResumenRepository(
    private val api: WatchApi,
    private val tokenStore: TokenStore,
    private val prefs: WatchPrefs,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val onChanged: (() -> Unit)? = null,
) : ResumenSource {

    override suspend fun fetch(notify: Boolean): ResumenState {
        val token = tokenStore.getToken() ?: return ResumenState.Unpaired
        val sucursalId = prefs.sucursalId.firstOrNull()
        val state = doFetch(token, sucursalId, allowRetryOn400 = true)
        if (notify && (state is ResumenState.Fresh || state is ResumenState.Unpaired)) {
            onChanged?.invoke()
        }
        return state
    }

    private suspend fun doFetch(token: String, sucursalId: Int?, allowRetryOn400: Boolean): ResumenState {
        val response = try {
            api.resumen(token, sucursalId)
        } catch (e: IOException) {
            return offlineFallback(sucursalId)
        }

        return when (val code = response.code()) {
            200 -> {
                val body = response.body()?.string()
                    ?: return ResumenState.Error("Respuesta vacía")
                val resumen = WatchJson.decodeFromString<Resumen>(body)
                val now = clock()
                prefs.saveLast(body, now, sucursalId)
                ResumenState.Fresh(resumen, now)
            }
            400 -> {
                if (allowRetryOn400) {
                    prefs.setSucursal(null)
                    doFetch(token, null, allowRetryOn400 = false)
                } else {
                    ResumenState.Error("Sucursal inválida")
                }
            }
            401 -> {
                tokenStore.clearToken()
                prefs.clearLast()
                ResumenState.Unpaired
            }
            in 500..599 -> offlineFallback(sucursalId)
            else -> ResumenState.Error("Error $code")
        }
    }

    /** IOException/5xx 공통 경로 — 저장된 마지막 값이 지금 선택과 같은 지점일 때만 Stale. */
    private suspend fun offlineFallback(currentSucursalId: Int?): ResumenState {
        val last = prefs.getLast() ?: return ResumenState.Error("Sin conexión")
        if (last.sucursalId != currentSucursalId) return ResumenState.Error("Sin conexión")
        val resumen = WatchJson.decodeFromString<Resumen>(last.json)
        return ResumenState.Stale(resumen, last.fetchedAt)
    }

    /**
     * 지점 변경 — 다른 지점의 옛 값이 지금 지점 값처럼 보이지 않게 마지막 값도 지운다(T-98-25).
     * Tile·컴플리케이션도 선택 지점을 따르게(D-09) 항상 [onChanged] 를 호출한다.
     */
    override suspend fun setSucursal(id: Int?) {
        prefs.setSucursal(id)
        prefs.clearLast()
        onChanged?.invoke()
    }

    override suspend fun requestCode(model: String?): PairingCodeDto {
        val response = api.requestCode(PairingCodeRequest(model))
        val body = response.body()
        if (!response.isSuccessful || body == null) throw PairingHttpException(response.code())
        return body
    }

    override suspend fun poll(deviceCode: String): PollResult {
        val response = api.poll(PollRequest(deviceCode))
        return when (response.code()) {
            202 -> PollResult.Pending
            200 -> {
                val body = response.body()?.string() ?: return PollResult.Pending
                val poll = WatchJson.decodeFromString<PollDto>(body)
                val token = poll.watchToken ?: return PollResult.Pending
                tokenStore.saveToken(token)
                PollResult.Paired
            }
            410 -> PollResult.Expired
            else -> PollResult.Expired
        }
    }
}
