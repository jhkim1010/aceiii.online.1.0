package com.coolsistema.wearadmin.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.firstOrNull
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** 워치 토큰·지점 선택·마지막 응답을 담는 단일 DataStore 파일(앱 전용 저장소, D-14 ③). */
internal val Context.watchDataStore by preferencesDataStore(name = "watch_prefs")

private const val KEYSTORE_ALIAS = "ventago_watch_token"
private const val GCM_TAG_LENGTH_BITS = 128
private val KEY_TOKEN_IV = stringPreferencesKey("watch_token_iv")
private val KEY_TOKEN_CT = stringPreferencesKey("watch_token_ct")

interface TokenStore {
    suspend fun getToken(): String?
    suspend fun saveToken(token: String)
    suspend fun clearToken()
}

/**
 * Android Keystore(AES-GCM 256)로 직접 암호화한다 — 기기 보안 저장을 위한 과거의
 * 표준 래퍼 클래스는 공식 폐기되어 신규 코드에 쓰지 않는다(98-RESEARCH.md 참고).
 * 복호화 실패(키 손상·백업 복원 등)는 토큰을 삭제하고 null 을 반환한다(깨진 토큰을
 * 들고 있지 않는다).
 */
class KeystoreTokenStore(private val context: Context) : TokenStore {

    override suspend fun getToken(): String? {
        val prefs = context.watchDataStore.data.firstOrNull() ?: return null
        val ivB64 = prefs[KEY_TOKEN_IV] ?: return null
        val ctB64 = prefs[KEY_TOKEN_CT] ?: return null
        return try {
            val iv = Base64.getDecoder().decode(ivB64)
            val ct = Base64.getDecoder().decode(ctB64)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, loadKey(), GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            String(cipher.doFinal(ct), Charsets.UTF_8)
        } catch (e: Exception) {
            clearToken()
            null
        }
    }

    override suspend fun saveToken(token: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, loadOrCreateKey())
        val ct = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        context.watchDataStore.edit { prefs ->
            prefs[KEY_TOKEN_IV] = Base64.getEncoder().encodeToString(iv)
            prefs[KEY_TOKEN_CT] = Base64.getEncoder().encodeToString(ct)
        }
    }

    override suspend fun clearToken() {
        context.watchDataStore.edit { prefs ->
            prefs.remove(KEY_TOKEN_IV)
            prefs.remove(KEY_TOKEN_CT)
        }
    }

    private fun loadKey(): SecretKey = loadOrCreateKey()

    private fun loadOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)
        (keyStore.getKey(KEYSTORE_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEYSTORE_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }
}
