package com.coolsistema.wearadmin.ui.selector

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.ui.model.OpcionSucursal
import com.coolsistema.wearadmin.ui.model.selectorUi
import com.coolsistema.wearadmin.ui.resumen.ResumenViewModel
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/**
 * 지점 선택기(D3) — 「TODAS ▾」/지점명을 탭하면 열린다. 고르면 모든 섹션·Tile·컴플리케이션에
 * 적용되고 기억된다(D-09). 지점이 1개인 매장은 이 화면에 진입하지 않는다(D-15 ⑥ —
 * [SeccionFrame] 이 `alcanceTocable=false` 일 때 탭을 막아 애초에 열리지 않는다).
 */
@Composable
fun SelectorScreen(viewModel: ResumenViewModel, onElegido: () -> Unit) {
    val state by viewModel.state.collectAsState()
    val opciones: List<OpcionSucursal> = remember(state) {
        val resumen = when (val s = state) {
            is ResumenState.Fresh -> s.resumen
            is ResumenState.Stale -> s.resumen
            else -> null
        }
        resumen?.let { selectorUi(it, it.sucursal?.id) } ?: emptyList()
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "ELEGIR SUCURSAL",
            color = VentagoColors.Gold,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
        ) {
            opciones.forEach { opcion ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .clickable {
                            viewModel.selectSucursal(opcion.id)
                            onElegido()
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    val puntoColor = if (opcion.elegida) VentagoColors.Gold else VentagoColors.MedioGray
                    Text(text = if (opcion.elegida) "●" else "○", color = puntoColor, fontSize = 11.sp)
                    Text(
                        text = opcion.etiqueta,
                        color = if (opcion.elegida) VentagoColors.Gold else VentagoColors.White,
                        fontSize = 11.sp,
                        modifier = Modifier.weight(1f).padding(horizontal = 6.dp),
                    )
                    Text(
                        text = opcion.monto,
                        color = if (opcion.elegida) VentagoColors.Gold else VentagoColors.Muted,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
        Text(
            text = "girar · tocar para elegir",
            color = VentagoColors.Muted,
            fontSize = 9.sp,
            textAlign = TextAlign.Center,
        )
    }
}
