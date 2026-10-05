package com.coolsistema.wearadmin

import android.app.Application
import com.coolsistema.wearadmin.data.DataStoreWatchPrefs
import com.coolsistema.wearadmin.data.KeystoreTokenStore
import com.coolsistema.wearadmin.data.ResumenRepository
import com.coolsistema.wearadmin.data.WatchApi
import com.coolsistema.wearadmin.surface.SurfaceUpdater

/**
 * 수동 DI 싱글턴 — 이 규모에 새 DI 프레임워크는 과하다(action 문구 그대로). 앱 화면·
 * Tile·컴플리케이션(98-06)이 전부 이 객체를 통해 같은 토큰 저장소·같은 지점 선택·
 * 같은 오프라인 캐시(ResumenRepository 1개)를 공유한다.
 */
class AppGraph private constructor(application: Application) {
    val tokenStore by lazy { KeystoreTokenStore(application) }
    val watchPrefs by lazy { DataStoreWatchPrefs(application) }
    val watchApi by lazy { WatchApi.create() }

    // 앱·Tile·컴플리케이션 중 하나가 새 값/지점/회수를 받으면 나머지 표면도 갱신 요청(D-09).
    val resumenRepository by lazy {
        ResumenRepository(
            watchApi,
            tokenStore,
            watchPrefs,
            onChanged = { SurfaceUpdater.requestAll(application) },
        )
    }

    companion object {
        @Volatile
        private var instance: AppGraph? = null

        fun from(application: Application): AppGraph =
            instance ?: synchronized(this) {
                instance ?: AppGraph(application).also { instance = it }
            }
    }
}
