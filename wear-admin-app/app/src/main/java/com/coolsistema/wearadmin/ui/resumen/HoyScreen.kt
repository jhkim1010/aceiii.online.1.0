package com.coolsistema.wearadmin.ui.resumen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.model.HoyUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/** ① Hoy(목업 D1/D4) — 큰 금액·증감·구분선·건수/벌수·마지막 판매·(Todas) 지점별 목록. */
@Composable
fun HoyScreen(seccion: SeccionUi<HoyUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Text(
            text = ui.monto,
            color = VentagoColors.White,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 4.dp),
        )
        if (ui.delta.isNotEmpty()) {
            val deltaColor = when {
                ui.delta.startsWith("▲") -> VentagoColors.Up
                ui.delta.startsWith("▼") -> VentagoColors.Down
                else -> VentagoColors.Muted
            }
            Text(text = ui.delta, color = deltaColor, fontSize = 11.sp, textAlign = TextAlign.Center)
        }
        Text(
            text = ui.detalle,
            color = VentagoColors.Muted,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp),
        )
        Text(
            text = ui.ultima,
            color = VentagoColors.Muted,
            fontSize = 9.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 2.dp),
        )
        if (ui.sucursales.isNotEmpty()) {
            Column(modifier = Modifier.width(130.dp).padding(top = 8.dp)) {
                ui.sucursales.forEach { fila ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(text = fila.nombre, color = VentagoColors.White, fontSize = 10.sp)
                        Text(
                            text = fila.monto,
                            color = VentagoColors.Muted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }
    }
}
