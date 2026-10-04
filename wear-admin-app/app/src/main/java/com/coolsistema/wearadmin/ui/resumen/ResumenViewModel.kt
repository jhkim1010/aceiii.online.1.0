package com.coolsistema.wearadmin.ui.resumen

import com.coolsistema.wearadmin.data.ResumenSource
import com.coolsistema.wearadmin.data.ResumenState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * 요약 화면 상태 — 앱을 열 때마다·「Hoy」 맨 위에서 당길 때 즉시 갱신(D-10), 진행 중인
 * 새로고침은 fetch 1회로 합친다. 지점 선택(D-09)은 저장 후 즉시 그 지점으로 다시 받는다.
 *
 * `scope` 는 호출부가 소유한다(PairingViewModel 과 같은 이유 — 자체 루트 스코프는 시험
 * 종료 후에도 살아남아 가상 시간을 끝까지 소진한다).
 */
class ResumenViewModel(
    private val repository: ResumenSource,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<ResumenState?>(null)
    val state: StateFlow<ResumenState?> = _state

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing

    private val _onUnpaired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val onUnpaired: SharedFlow<Unit> = _onUnpaired

    private var job: Job? = null

    /** 앱 열 때마다·당겨서 새로고침(D-10). 진행 중인 refresh 가 있으면 합쳐 fetch 1회만. */
    fun refresh() {
        if (job?.isActive == true) return
        job = runRefresh { doRefresh() }
    }

    fun onResume() = refresh()

    /** 선택은 즉시 적용 — 진행 중인 refresh 가 있어도 새 선택으로 다시 받는다. */
    fun selectSucursal(id: Int?) {
        job?.cancel()
        job = runRefresh {
            repository.setSucursal(id)
            doRefresh()
        }
    }

    private fun runRefresh(block: suspend () -> Unit): Job = scope.launch {
        _refreshing.value = true
        try {
            block()
        } finally {
            _refreshing.value = false
        }
    }

    private suspend fun doRefresh() {
        val result = repository.fetch()
        _state.value = result
        if (result is ResumenState.Unpaired) {
            _onUnpaired.emit(Unit)
        }
    }
}
