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
import com.coolsistema.wearadmin.ui.model.IngresosUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/** ④ Ingresos de mercadería — cantidad de prendas + eventos + (Todas) por sucursal. */
@Composable
fun IngresosScreen(seccion: SeccionUi<IngresosUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Text(
            text = ui.cantidad,
            color = VentagoColors.White,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 4.dp),
        )
        Text(text = "prendas ingresadas", color = VentagoColors.Muted, fontSize = 11.sp, textAlign = TextAlign.Center)
        Text(
            text = ui.detalle,
            color = VentagoColors.Muted,
            fontSize = 9.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp),
        )
        Text(
            text = ui.subDetalle,
            color = VentagoColors.Muted,
            fontSize = 9.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 2.dp),
        )
        if (ui.porSucursal.isNotEmpty()) {
            Column(modifier = Modifier.width(130.dp).padding(top = 8.dp)) {
                ui.porSucursal.forEach { fila ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(text = fila.nombre, color = VentagoColors.White, fontSize = 10.sp)
                        Text(
                            text = fila.prendas,
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
