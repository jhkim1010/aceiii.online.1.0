package com.coolsistema.wearadmin.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationPersistencePolicies
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.coolsistema.wearadmin.AppGraph
import com.coolsistema.wearadmin.MainActivity
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.surface.complicationLong
import com.coolsistema.wearadmin.surface.complicationShort
import com.coolsistema.wearadmin.surface.isLocked
import kotlinx.coroutines.withTimeoutOrNull

private const val FETCH_TIMEOUT_MILLIS = 5_000L

/**
 * 원형(SHORT_TEXT)·막대(LONG_TEXT) 컴플리케이션. D-14 ② + D-15 ⑦: SHORT_TEXT 는
 * `complicationShort()` 를 montoEnCirculo 인자 없이 불러 **항상 건수**다(MONTO_EN_CIRCULO=false
 * 기본값) — 이 서비스는 금액 경로(montoEnCirculo 를 true 로 넘기는 호출)를 두지 않는다.
 *
 * 조사 결과(98-06, read_first 문서·androidx.wear.watchface:watchface-complications-data 1.3.0
 * 소스 jar 로 확인) — SUMMARY 에도 기록:
 * - `ComplicationPersistencePolicies.DO_NOT_PERSIST` 존재 → 적용함(아래, D-14 ③. 재부팅 후
 *   옛 값이 디스크에 남지 않게).
 * - `ComplicationDisplayPolicies.DO_NOT_SHOW_WHEN_DEVICE_LOCKED` 존재(잠금에서 숨기는 플랫폼
 *   수단) → **적용하지 않음**. SHORT_TEXT·LONG_TEXT 둘 다 건수뿐이라 가릴 금액이 없고, 숨기면
 *   오히려 정보가 사라진다(D-15 ⑦ 확정 — 금액을 싣는 것도 숨기는 것도 사용자의 새 결정 없이는 하지 않는다).
 * - ambient 전용 동적 값 소스(`androidx.wear.protolayout.expression.PlatformEventSources`)는
 *   레이아웃 갱신 상태(`DynamicLayoutUpdateStatus`)만 제공하고 "ambient 여부"를 직접 노출하는
 *   dynamic boolean 은 이 버전(protolayout-expression 1.4.2)에 없다 — 즉 Tile/컴플리케이션
 *   레이어에서 ambient 진입 시 텍스트를 동적으로 가리는 플랫폼 수단은 **확인되지 않았다**.
 *   이번 phase 의 동작(원형=건수)은 이 조사 결과와 무관하게 D-15 ⑦ 로 이미 확정됐다.
 */
class VentasComplicationService : SuspendingComplicationDataSourceService() {

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData {
        val context = applicationContext
        val repository = AppGraph.from(context.applicationContext as android.app.Application).resumenRepository
        // notify = false — 이 요청 자신이 다시 모든 표면 갱신을 촉발하는 재귀를 막는다(T-98-42).
        val state = withTimeoutOrNull(FETCH_TIMEOUT_MILLIS) { repository.fetch(notify = false) }
            ?: ResumenState.Error("Tiempo de espera agotado")
        val bloqueado = isLocked(context)
        val now = System.currentTimeMillis()
        val tapAction = openAppPendingIntent(context)

        return when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                val short = complicationShort(state, now, bloqueado)
                ShortTextComplicationData.Builder(
                    PlainComplicationText.Builder(short.text).build(),
                    PlainComplicationText.Builder(short.title.ifEmpty { "Ventago" }).build(),
                )
                    .setTitle(PlainComplicationText.Builder(short.title).build())
                    .setTapAction(tapAction)
                    .setPersistencePolicy(ComplicationPersistencePolicies.DO_NOT_PERSIST)
                    .build()
            }
            ComplicationType.LONG_TEXT -> {
                val long = complicationLong(state, now, bloqueado)
                LongTextComplicationData.Builder(
                    PlainComplicationText.Builder(long).build(),
                    PlainComplicationText.Builder("Ventago").build(),
                )
                    .setTapAction(tapAction)
                    .setPersistencePolicy(ComplicationPersistencePolicies.DO_NOT_PERSIST)
                    .build()
            }
            else -> throw IllegalArgumentException("Tipo no soportado: ${request.complicationType}")
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData =
        when (type) {
            ComplicationType.SHORT_TEXT ->
                ShortTextComplicationData.Builder(
                    PlainComplicationText.Builder("55").build(),
                    PlainComplicationText.Builder("ventas").build(),
                )
                    .setTitle(PlainComplicationText.Builder("ventas").build())
                    .build()
            ComplicationType.LONG_TEXT ->
                LongTextComplicationData.Builder(
                    PlainComplicationText.Builder("55 ventas · 3 cajas").build(),
                    PlainComplicationText.Builder("Ventago").build(),
                ).build()
            else -> throw IllegalArgumentException("Tipo no soportado: $type")
        }

    private fun openAppPendingIntent(context: android.content.Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    }
}
