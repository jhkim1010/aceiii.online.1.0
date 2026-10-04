package com.coolsistema.wearadmin.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map

/** 마지막으로 받은 응답 1개(오프라인 표시용) — 키 하나에 덮어쓰므로 구조적으로 1개뿐. */
data class LastResumen(val json: String, val fetchedAt: Long, val sucursalId: Int?)

interface WatchPrefs {
    val sucursalId: Flow<Int?>
    suspend fun setSucursal(id: Int?)
    suspend fun saveLast(json: String, fetchedAt: Long, sucursalId: Int?)
    suspend fun getLast(): LastResumen?
    suspend fun clearLast()
}

private val KEY_SUCURSAL_ID = intPreferencesKey("sucursal_id")
private val KEY_LAST_JSON = stringPreferencesKey("last_json")
private val KEY_LAST_FETCHED_AT = longPreferencesKey("last_fetched_at")
private val KEY_LAST_SUCURSAL_ID = intPreferencesKey("last_sucursal_id")

/**
 * 선택 지점 + 마지막 응답(평문, 집계값 — 앱 전용 저장소). 토큰은 여기 없다([KeystoreTokenStore]).
 * 지점 변경 시 마지막 값을 지우는 정책은 [ResumenRepository.setSucursal] 이 가진다(여기는
 * 저장소일 뿐, T-98-25 는 리포지토리 레이어의 책임).
 */
class DataStoreWatchPrefs(private val context: Context) : WatchPrefs {

    override val sucursalId: Flow<Int?>
        get() = context.watchDataStore.data.map { it[KEY_SUCURSAL_ID] }

    override suspend fun setSucursal(id: Int?) {
        context.watchDataStore.edit { prefs ->
            if (id == null) prefs.remove(KEY_SUCURSAL_ID) else prefs[KEY_SUCURSAL_ID] = id
        }
    }

    override suspend fun saveLast(json: String, fetchedAt: Long, sucursalId: Int?) {
        context.watchDataStore.edit { prefs ->
            prefs[KEY_LAST_JSON] = json
            prefs[KEY_LAST_FETCHED_AT] = fetchedAt
            if (sucursalId == null) prefs.remove(KEY_LAST_SUCURSAL_ID) else prefs[KEY_LAST_SUCURSAL_ID] = sucursalId
        }
    }

    override suspend fun getLast(): LastResumen? {
        val prefs = context.watchDataStore.data.firstOrNull() ?: return null
        val json = prefs[KEY_LAST_JSON] ?: return null
        val fetchedAt = prefs[KEY_LAST_FETCHED_AT] ?: return null
        val sucursalId = prefs[KEY_LAST_SUCURSAL_ID]
        return LastResumen(json, fetchedAt, sucursalId)
    }

    override suspend fun clearLast() {
        context.watchDataStore.edit { prefs ->
            prefs.remove(KEY_LAST_JSON)
            prefs.remove(KEY_LAST_FETCHED_AT)
            prefs.remove(KEY_LAST_SUCURSAL_ID)
        }
    }
}
