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
import com.coolsistema.wearadmin.ui.model.FacturacionUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/** ⑤ Facturación del mes(D-15 ③·④ — mes, no día) — total, IVA, por tipo, aviso IVA incompleto. */
@Composable
fun FacturacionScreen(seccion: SeccionUi<FacturacionUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Text(
            text = ui.grande,
            color = VentagoColors.White,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 4.dp),
        )
        Text(text = ui.iva, color = VentagoColors.Muted, fontSize = 11.sp)
        Column(modifier = Modifier.width(130.dp).padding(top = 8.dp)) {
            ui.tipos.forEach { fila ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(text = fila.etiqueta, color = VentagoColors.Muted, fontSize = 10.sp)
                    Text(text = fila.monto, color = VentagoColors.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        ui.aviso?.let { aviso ->
            Text(
                text = aviso,
                color = VentagoColors.Gold,
                fontSize = 9.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
        if (ui.porSucursal.isNotEmpty()) {
            Column(modifier = Modifier.width(130.dp).padding(top = 8.dp)) {
                ui.porSucursal.forEach { fila ->
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
