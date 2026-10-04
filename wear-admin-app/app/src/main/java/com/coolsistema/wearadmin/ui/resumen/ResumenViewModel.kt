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

    /**
     * [allowNarrowFix] 는 재귀 1단계만 허용하는 가드다 — setSucursal(null) 뒤 다시 받은
     * 응답은 당연히 sucursal == null 이라 조건이 꺼지지만, 가드가 없으면 이론상으로도
     * "낡은 선택 지우기"가 반복될 여지를 코드에 남기지 않는다.
     */
    private suspend fun doRefresh(allowNarrowFix: Boolean = true) {
        val result = repository.fetch()
        _state.value = result

        if (result is ResumenState.Unpaired) {
            _onUnpaired.emit(Unit)
            return
        }
        if (!allowNarrowFix) return

        val resumen = when (result) {
            is ResumenState.Fresh -> result.resumen
            is ResumenState.Stale -> result.resumen
            else -> null
        } ?: return

        // D-15 ⑥: 응답이 특정 지점을 가리키는데(sucursal != null) 그 지점이 매장의 유일한
        // 지점이면(sucursales.size <= 1) 저장된 선택은 낡은 좁히기다 — 지우고 한 번 더 받는다
        // (narrowing-filter-must-never-widen: 폭을 넓히는 게 아니라 애초에 좁힐 이유가
        // 없는 선택을 지우는 것뿐이다).
        if (resumen.sucursal != null && resumen.sucursales.size <= 1) {
            repository.setSucursal(null)
            doRefresh(allowNarrowFix = false)
        }
    }
}
