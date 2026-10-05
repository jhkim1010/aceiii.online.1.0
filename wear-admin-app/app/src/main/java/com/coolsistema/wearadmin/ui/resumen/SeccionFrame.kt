package com.coolsistema.wearadmin.ui.resumen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.ui.model.Cabecera
import com.coolsistema.wearadmin.ui.model.SeccionUi
import com.coolsistema.wearadmin.ui.model.Tono
import com.coolsistema.wearadmin.ui.theme.VentagoColors

/**
 * 공통 섹션 틀(98-11 Task 1) — 머리(라벨·범위 칩 — [Cabecera.alcanceTocable] 일 때만
 * 탭 가능, D-15 ⑥ 지점 1개 매장은 탭해도 선택기가 안 열린다) · 상태(No disponible ·
 * Sin conexión) · 하단 경과 시간을 전부 여기서 그린다. 개별 섹션 화면(Task 2)은
 * [content] 슬롯에 본문만 채운다 — 상태 문구를 직접 만들지 않는다.
 */
@Composable
fun <T> SeccionFrame(
    seccion: SeccionUi<T>,
    onAlcance: () -> Unit,
    content: @Composable (T) -> Unit,
) {
    val cabecera: Cabecera = when (seccion) {
        is SeccionUi.Lista -> seccion.cabecera
        is SeccionUi.NoDisponible -> seccion.cabecera
    }
    val colorLabel = if (cabecera.tono == Tono.Gris) VentagoColors.Muted else VentagoColors.Gold

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 22.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Top,
    ) {
        Text(
            text = cabecera.label,
            color = colorLabel,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = cabecera.alcance,
            color = VentagoColors.Muted,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
            modifier = (
                if (cabecera.alcanceTocable) Modifier.clickable(onClick = onAlcance) else Modifier
                ).fillMaxWidth(),
        )
        cabecera.aviso?.let { aviso ->
            Text(
                text = aviso,
                color = VentagoColors.Gold,
                fontSize = 9.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when (seccion) {
                is SeccionUi.Lista -> content(seccion.data)
                is SeccionUi.NoDisponible -> {
                    Text(
                        text = seccion.mensaje,
                        color = VentagoColors.Muted,
                        fontSize = 11.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                    )
                }
            }
        }

        cabecera.pie?.let { pie ->
            Text(
                text = pie,
                color = VentagoColors.Muted,
                fontSize = 9.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
