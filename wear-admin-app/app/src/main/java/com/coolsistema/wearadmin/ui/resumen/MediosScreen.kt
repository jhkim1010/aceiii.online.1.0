package com.coolsistema.wearadmin.ui.resumen

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.model.MedioFila
import com.coolsistema.wearadmin.ui.model.MediosUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/** ② Medios de pago(목업 D2) — 비율 링 + 4줄 범례 + (Todas) 지점별 efectivo + pie. */
@Composable
fun MediosScreen(seccion: SeccionUi<MediosUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Box(
            modifier = Modifier.padding(top = 4.dp).size(64.dp),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                var startAngle = -90f
                ui.filas.forEach { fila ->
                    val sweep = (fila.proporcion * 360.0).toFloat()
                    if (sweep > 0f) {
                        drawArc(
                            color = colorDeMedio(fila.nombre),
                            startAngle = startAngle,
                            sweepAngle = sweep,
                            useCenter = false,
                            style = Stroke(width = 9.dp.toPx()),
                        )
                        startAngle += sweep
                    }
                }
            }
        }
        Column(modifier = Modifier.padding(top = 6.dp)) {
            ui.filas.forEach { fila -> MedioRow(fila) }
        }
        if (ui.porSucursal.isNotEmpty()) {
            Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                ui.porSucursal.forEach { fila ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(text = fila.nombre, color = VentagoColors.White, fontSize = 10.sp)
                        Text(
                            text = fila.efectivo,
                            color = VentagoColors.Muted,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }
        ui.pieSucursal?.let { pie ->
            Text(
                text = pie,
                color = VentagoColors.Muted,
                fontSize = 9.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun MedioRow(fila: MedioFila) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(text = fila.nombre, color = VentagoColors.Muted, fontSize = 10.sp)
        Text(text = fila.monto, color = VentagoColors.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
    }
}

private fun colorDeMedio(nombre: String) = when (nombre) {
    "Efectivo" -> VentagoColors.Up
    "Bancarias" -> VentagoColors.BancariasBlue
    else -> VentagoColors.MedioGray
}
