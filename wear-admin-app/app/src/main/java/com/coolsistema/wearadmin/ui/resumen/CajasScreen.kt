package com.coolsistema.wearadmin.ui.resumen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.model.CajaFila
import com.coolsistema.wearadmin.ui.model.CajasGrupo
import com.coolsistema.wearadmin.ui.model.CajasUi
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors

private const val PUNTO_ABIERTA = "●"

/** ⑥ Cajas(목업 D5, v1 유지) — 서랍 단위, ⚠ 전날부터 열려있거나 미마감 펜딩이 있을 때. */
@Composable
fun CajasScreen(seccion: SeccionUi<CajasUi>, onAlcance: () -> Unit) {
    SeccionFrame(seccion = seccion, onAlcance = onAlcance) { ui ->
        Text(
            text = ui.efectivoEnCajas,
            color = VentagoColors.Muted,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp),
        )
        Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            if (ui.grupos.isNotEmpty()) {
                ui.grupos.forEach { grupo -> CajasGrupoBloque(grupo) }
            } else {
                ui.filas.forEach { fila -> CajaRowView(fila) }
            }
        }
        ui.masOmitidas?.let { texto ->
            Text(
                text = texto,
                color = VentagoColors.Muted,
                fontSize = 9.sp,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}

@Composable
private fun CajasGrupoBloque(grupo: CajasGrupo) {
    Text(
        text = grupo.titulo,
        color = VentagoColors.Gold,
        fontSize = 9.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
    )
    grupo.filas.forEach { fila -> CajaRowView(fila) }
}

@Composable
private fun CajaRowView(fila: CajaFila) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        val abierta = fila.punto == PUNTO_ABIERTA
        Text(text = fila.punto, color = if (abierta) VentagoColors.Up else VentagoColors.ClosedOutline, fontSize = 9.sp)
        Text(
            text = fila.nombre,
            color = VentagoColors.White,
            fontSize = 10.sp,
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
        )
        if (fila.aviso) {
            Text(text = "⚠", color = VentagoColors.Gold, fontSize = 10.sp, modifier = Modifier.padding(end = 2.dp))
        }
        Text(
            text = fila.montoOCerrada,
            color = if (abierta) VentagoColors.White else VentagoColors.Muted,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}
