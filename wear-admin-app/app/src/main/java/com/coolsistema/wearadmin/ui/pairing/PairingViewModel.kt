package com.coolsistema.wearadmin.ui.pairing

import com.coolsistema.wearadmin.data.PairingCodeDto
import com.coolsistema.wearadmin.data.PairingHttpException
import com.coolsistema.wearadmin.data.PollResult
import com.coolsistema.wearadmin.data.ResumenSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.IOException

/** 페어링 화면 상태(D-06) — 코드 표시 → interval 초마다 poll → 연결됨/만료 시 새 코드. */
sealed class PairingUi {
    data object Loading : PairingUi()
    data class ShowCode(val userCode: String, val secondsLeft: Int) : PairingUi()
    data object Paired : PairingUi()
    data class Error(val message: String) : PairingUi()
}

private const val ERROR_RETRY_MS = 10_000L
private const val RATE_LIMIT_RETRY_MS = 60_000L

/**
 * `requestCode` → `ShowCode` → `interval` 초마다 `poll`(RFC 8628 §3.5 — interval 보다 빨리
 * 묻지 않는다). `Paired` 가 되면 폴링을 멈춘다. 코드가 만료되거나(`Expired`) 남은 시간이
 * 0 이 되면 새 코드를 자동으로 다시 요청한다. 네트워크 오류는 10초, 429(rate limit)는
 * 60초 뒤 재시도한다.
 *
 * `scope` 는 호출부가 소유한다(화면의 `viewModelScope`/`rememberCoroutineScope()`, 시험은
 * `backgroundScope`) — 뷰모델이 자기 자신의 루트 스코프를 만들면 그 생애주기가 호출부와
 * 분리돼 시험 종료 후에도 폴링 루프가 계속 돌며 가상 시간을 끝까지 소진한다.
 */
class PairingViewModel(
    private val repository: ResumenSource,
    private val scope: CoroutineScope,
) {
    private val _uiState = MutableStateFlow<PairingUi>(PairingUi.Loading)
    val uiState: StateFlow<PairingUi> = _uiState

    private var job: Job? = null

    fun start(model: String?) {
        job?.cancel()
        job = scope.launch { runLoop(model) }
    }

    private suspend fun runLoop(model: String?) {
        while (true) {
            val code = requestCodeWithRetry(model) ?: continue
            _uiState.value = PairingUi.ShowCode(code.userCode, code.expiresIn)
            if (pollUntilPairedOrExpired(code)) {
                _uiState.value = PairingUi.Paired
                return
            }
            // Expired 또는 secondsLeft 0 — while 이 새 코드를 다시 요청한다.
        }
    }

    /** null = 백오프를 기다렸다(바깥 루프가 requestCode 를 다시 시도한다). */
    private suspend fun requestCodeWithRetry(model: String?): PairingCodeDto? {
        return try {
            repository.requestCode(model)
        } catch (e: IOException) {
            _uiState.value = PairingUi.Error("Sin conexión")
            delay(ERROR_RETRY_MS)
            null
        } catch (e: PairingHttpException) {
            if (e.code == 429) {
                _uiState.value = PairingUi.Error("Demasiados intentos")
                delay(RATE_LIMIT_RETRY_MS)
            } else {
                _uiState.value = PairingUi.Error("Sin conexión")
                delay(ERROR_RETRY_MS)
            }
            null
        }
    }

    /** true = Paired. false = Expired 또는 secondsLeft 가 0 에 도달(새 코드 필요). */
    private suspend fun pollUntilPairedOrExpired(code: PairingCodeDto): Boolean {
        var remainingSeconds = code.expiresIn
        val intervalMs = code.interval * 1_000L
        while (remainingSeconds > 0) {
            delay(intervalMs)
            remainingSeconds -= code.interval
            when (repository.poll(code.deviceCode)) {
                PollResult.Pending -> Unit
                PollResult.Paired -> return true
                PollResult.Expired -> return false
            }
        }
        return false
    }
}
