package com.coolsistema.wearadmin.data

import com.coolsistema.wearadmin.BuildConfig
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Query
import java.util.concurrent.TimeUnit

@Serializable
data class PairingCodeRequest(val model: String? = null)

@Serializable
data class PollRequest(val deviceCode: String)

/**
 * `/watch/` 하위 호출 — 로깅 인터셉터 없음(D-14 ③, T-98-21). resumen 호출은
 * x-watch-token 헤더만 쓰고 Authorization 은 전혀 보내지 않는다(전역 인터셉터도 추가하지 않는다).
 */
interface WatchApi {

    @POST("watch/pairing-codes")
    suspend fun requestCode(@Body body: PairingCodeRequest): Response<PairingCodeDto>

    @POST("watch/pairing-codes/poll")
    suspend fun poll(@Body body: PollRequest): Response<ResponseBody>

    /**
     * 본문을 원문 그대로 받는다 — 리포지토리가 [WatchJson] 으로 파싱하고, 오프라인
     * 캐시에도 같은 문자열을 저장한다(파싱과 저장이 다른 표현이면 캐시가 계약과 갈라진다).
     */
    @GET("watch/resumen")
    suspend fun resumen(
        @Header("x-watch-token") token: String,
        @Query("sucursal") sucursal: Int?,
    ): Response<ResponseBody>

    companion object {
        fun create(baseUrl: String = BuildConfig.API_BASE + "/"): WatchApi {
            val client = OkHttpClient.Builder()
                .connectTimeout(8, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .build()
            val contentType = "application/json".toMediaType()
            return Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(client)
                .addConverterFactory(WatchJson.asConverterFactory(contentType))
                .build()
                .create(WatchApi::class.java)
        }
    }
}
