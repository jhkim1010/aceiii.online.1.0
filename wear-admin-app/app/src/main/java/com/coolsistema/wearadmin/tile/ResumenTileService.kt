package com.coolsistema.wearadmin.tile

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.Box
import androidx.wear.protolayout.LayoutElementBuilders.Column
import androidx.wear.protolayout.LayoutElementBuilders.FontStyle
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.LayoutElementBuilders.Row
import androidx.wear.protolayout.LayoutElementBuilders.Text
import androidx.wear.protolayout.ModifiersBuilders.Clickable
import androidx.wear.protolayout.ModifiersBuilders.Modifiers
import androidx.wear.protolayout.ModifiersBuilders.Padding
import androidx.wear.protolayout.TimelineBuilders.Timeline
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.tiles.Material3TileService
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import com.coolsistema.wearadmin.AppGraph
import com.coolsistema.wearadmin.MainActivity
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.surface.TileTexts
import com.coolsistema.wearadmin.surface.isLocked
import com.coolsistema.wearadmin.surface.tileTexts
import kotlinx.coroutines.withTimeoutOrNull

private const val GOLD = 0xFFF5A623.toInt()
private const val WHITE = 0xFFFFFFFF.toInt()
private const val MUTED = 0xFFB0B0B0.toInt()

private const val FETCH_TIMEOUT_MILLIS = 8_000L

/** 시스템 스로틀(research Pitfall 3) 근처 — 실제 경과는 pie 문구가 보여준다(Claude's discretion, plan 명시). */
private const val FRESHNESS_INTERVAL_MILLIS = 15 * 60 * 1000L

/**
 * 「HOY · {지점}」 Tile — ProtoLayout Material3 1.4. 요청 시점에 [AppGraph.resumenRepository]
 * 를 공유해 앱·컴플리케이션과 같은 토큰·같은 지점 선택·같은 오프라인 캐시를 본다.
 * 잠금 판정은 요청 시점([isLocked]) — D-14 ②.
 */
class ResumenTileService : Material3TileService() {

    override suspend fun MaterialScope.tileResponse(
        requestParams: RequestBuilders.TileRequest,
    ): TileBuilders.Tile {
        val context = this.context
        val repository = AppGraph.from(context.applicationContext as android.app.Application).resumenRepository
        val state = withTimeoutOrNull(FETCH_TIMEOUT_MILLIS) { repository.fetch() }
            ?: ResumenState.Error("Tiempo de espera agotado")
        val bloqueado = isLocked(context)
        val texts = tileTexts(state, System.currentTimeMillis(), bloqueado)

        val layout = buildLayout(texts, context)

        return TileBuilders.Tile.Builder()
            .setResourcesVersion("1")
            .setTileTimeline(Timeline.fromLayoutElement(layout))
            .setFreshnessIntervalMillis(FRESHNESS_INTERVAL_MILLIS)
            .build()
    }

    private fun buildLayout(texts: TileTexts, context: android.content.Context): LayoutElement {
        val openAppIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE,
        )
        val clickable = Clickable.Builder().setOnClick(pendingIntent).build()

        val titulo = Text.Builder()
            .setText(texts.titulo)
            .setFontStyle(
                FontStyle.Builder()
                    .setColor(argb(GOLD))
                    .setSize(sp(14f))
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                    .build(),
            )
            .setMaxLines(1)
            .build()

        val monto = Text.Builder()
            .setText(texts.monto)
            .setFontStyle(
                FontStyle.Builder()
                    .setColor(argb(WHITE))
                    .setSize(sp(28f))
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
                    .build(),
            )
            .setMaxLines(1)
            .build()

        val grilla = buildGrilla(texts.celdas)

        val pie = Text.Builder()
            .setText(texts.pie)
            .setFontStyle(
                FontStyle.Builder()
                    .setColor(argb(MUTED))
                    .setSize(sp(11f))
                    .build(),
            )
            .setMaxLines(1)
            .build()

        val columna = Column.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(titulo)
            .addContent(monto)
            .addContent(grilla)
            .addContent(pie)
            .build()

        return Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(Modifiers.Builder().setClickable(clickable).build())
            .addContent(columna)
            .build()
    }

    /** 2×2 칸(Efectivo·Bancarias·Gastos·Ventas) — celdas 가 비어 있으면(미연결) 빈 Column. */
    private fun buildGrilla(celdas: List<Pair<String, String>>): LayoutElement {
        val builder = Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        celdas.chunked(2).forEach { fila ->
            val row = Row.Builder()
            fila.forEach { (label, valor) -> row.addContent(celda(label, valor)) }
            builder.addContent(row.build())
        }
        return builder.build()
    }

    private fun celda(label: String, valor: String): LayoutElement {
        val labelText = Text.Builder()
            .setText(label)
            .setFontStyle(FontStyle.Builder().setColor(argb(MUTED)).setSize(sp(10f)).build())
            .setMaxLines(1)
            .build()
        val valorText = Text.Builder()
            .setText(valor)
            .setFontStyle(
                FontStyle.Builder()
                    .setColor(argb(WHITE))
                    .setSize(sp(13f))
                    .setWeight(LayoutElementBuilders.FONT_WEIGHT_MEDIUM)
                    .build(),
            )
            .setMaxLines(1)
            .build()
        return Column.Builder()
            .setWidth(dp(68f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(Modifiers.Builder().setPadding(Padding.Builder().setAll(dp(4f)).build()).build())
            .addContent(labelText)
            .addContent(valorText)
            .build()
    }
}
