package com.coolsistema.wearadmin.ui.resumen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.model.GastosDescUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/** ③ Gastos · Descuentos — 2열(건수 기준 D-12 ②), (Todas) 지점별 소계. */
@Composable
fun GastosDescScreen(seccion: SeccionUi<GastosDescUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Row(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            GastoColumna(titulo = "Gastos", monto = ui.gastosMonto, detalle = ui.gastosEventos)
            GastoColumna(titulo = "Descuentos", monto = ui.descuentosMonto, detalle = ui.descuentosEventos)
        }
        if (ui.porSucursal.isNotEmpty()) {
            Column(modifier = Modifier.width(130.dp).padding(top = 10.dp)) {
                ui.porSucursal.forEach { fila ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(text = fila.nombre, color = VentagoColors.White, fontSize = 10.sp)
                        Text(text = fila.gastos, color = VentagoColors.Down, fontSize = 10.sp)
                        Text(text = fila.descuentos, color = VentagoColors.Down, fontSize = 10.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.GastoColumna(titulo: String, monto: String, detalle: String) {
    Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = titulo, color = VentagoColors.Muted, fontSize = 9.sp)
        Text(text = monto, color = VentagoColors.Down, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        Text(text = detalle, color = VentagoColors.Muted, fontSize = 9.sp)
    }
}
