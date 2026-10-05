package com.coolsistema.wearadmin.ui.pairing

import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/**
 * 페어링 화면(D-06, 목업 ⑨) — 코드 표시 → 연결되면 [onPaired]. 비밀번호 없음.
 * `PairingViewModel.start()` 는 이 화면이 처음 그려질 때 한 번만 호출한다.
 */
@Composable
fun PairingScreen(viewModel: PairingViewModel, onPaired: () -> Unit) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(viewModel) { viewModel.start(Build.MODEL) }
    LaunchedEffect(uiState) {
        if (uiState is PairingUi.Paired) onPaired()
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "VENTAGO",
            color = VentagoColors.Gold,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
        )
        when (val s = uiState) {
            is PairingUi.Loading -> {
                Text(
                    text = "Generando código…",
                    color = VentagoColors.Muted,
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            is PairingUi.ShowCode -> {
                Text(
                    text = "Código para vincular",
                    color = VentagoColors.Muted,
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Text(
                    text = s.userCode,
                    color = VentagoColors.Gold,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 4.dp),
                )
                Text(
                    text = "Abrí Ventago Admin en el celular › Relojes e ingresalo",
                    color = VentagoColors.Muted,
                    fontSize = 10.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Text(
                    text = "vence en ${formatMmSs(s.secondsLeft)}",
                    color = VentagoColors.Muted,
                    fontSize = 9.sp,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            is PairingUi.Error -> {
                Text(
                    text = s.message,
                    color = VentagoColors.Gold,
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Text(
                    text = "Reintentando…",
                    color = VentagoColors.Muted,
                    fontSize = 10.sp,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            is PairingUi.Paired -> {
                Text(
                    text = "Vinculado",
                    color = VentagoColors.Up,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
        }
    }
}

private fun formatMmSs(totalSeconds: Int): String {
    val clamped = totalSeconds.coerceAtLeast(0)
    val m = clamped / 60
    val s = clamped % 60
    return "$m:${s.toString().padStart(2, '0')}"
}
