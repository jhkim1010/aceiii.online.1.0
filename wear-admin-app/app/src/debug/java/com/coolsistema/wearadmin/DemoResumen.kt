package com.coolsistema.wearadmin

import android.content.Context
import android.content.Intent
import com.coolsistema.wearadmin.data.PairingCodeDto
import com.coolsistema.wearadmin.data.PollResult
import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.data.ResumenSource
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.data.SucursalRef
import com.coolsistema.wearadmin.data.WatchJson
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private const val DEMO_EXTRA = "demo"
private const val DEMO_ASSET = "watch-resumen-v2.golden.json"

/**
 * debug 빌드 전용(98-11 Task 1) — `MainActivity` 가 인텐트 extra `demo=true` 로 열리면
 * 네트워크 호출 없이 골든 JSON(`watch-resumen-v2.golden.json`, build.gradle.kts 의
 * `copyDemoGoldenJson` 이 debug assets 로 복사)을 Fresh 상태로 돌려주는 [ResumenSource] 를
 * 만들어 돌려준다. 페어링을 거치지 않고 화면을 스모크하기 위한 훅이다.
 *
 * release 구현(src/release 의 같은 파일)은 항상 `null` 을 돌려줘 release APK 에는 이
 * 경로 자체가 없다(T-98-30b — `unzip -l ...apk | grep golden` 0건으로 검증).
 */
object DemoResumen {
    fun aplicar(intent: Intent?, context: Context): ResumenSource? {
        if (intent?.getBooleanExtra(DEMO_EXTRA, false) != true) return null
        val json = context.assets.open(DEMO_ASSET).bufferedReader().use { it.readText() }
        val resumen = WatchJson.decodeFromString<Resumen>(json)
        return DemoResumenSource(resumen)
    }
}

/** 지점 선택(D3 스모크)만 메모리에 반영한다 — 금액은 항상 골든 값 그대로(action 문구 그대로). */
private class DemoResumenSource(private val base: Resumen) : ResumenSource {
    private val mutex = Mutex()
    private var sucursalId: Int? = null

    override suspend fun fetch(notify: Boolean): ResumenState = mutex.withLock {
        ResumenState.Fresh(conSeleccion(base, sucursalId), System.currentTimeMillis())
    }

    override suspend fun setSucursal(id: Int?) {
        mutex.withLock { sucursalId = id }
    }

    override suspend fun requestCode(model: String?): PairingCodeDto {
        throw UnsupportedOperationException("DemoResumenSource no pairea — demo abre directo en secciones")
    }

    override suspend fun poll(deviceCode: String): PollResult = PollResult.Expired
}

private fun conSeleccion(base: Resumen, sucursalId: Int?): Resumen {
    if (sucursalId == null) return base.copy(sucursal = null)
    val match = base.sucursales.firstOrNull { it.id == sucursalId } ?: return base.copy(sucursal = null)
    return base.copy(sucursal = SucursalRef(match.id, match.nombre))
}
