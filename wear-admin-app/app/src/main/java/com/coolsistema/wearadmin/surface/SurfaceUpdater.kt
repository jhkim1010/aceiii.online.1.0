package com.coolsistema.wearadmin.surface

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.coolsistema.wearadmin.complication.VentasComplicationService
import com.coolsistema.wearadmin.tile.ResumenTileService

/**
 * 앱·Tile·컴플리케이션 중 하나가 새 값을 받으면(또는 지점이 바뀌거나 회수되면) 나머지
 * 표면에도 갱신을 요청한다 — [com.coolsistema.wearadmin.data.ResumenRepository] 의
 * `onChanged` 콜백이 이 함수를 부른다(AppGraph 가 연결).
 */
object SurfaceUpdater {
    fun requestAll(context: Context) {
        TileService.getUpdater(context).requestUpdate(ResumenTileService::class.java)
        ComplicationDataSourceUpdateRequester
            .create(context, ComponentName(context, VentasComplicationService::class.java))
            .requestUpdateAll()
    }
}
