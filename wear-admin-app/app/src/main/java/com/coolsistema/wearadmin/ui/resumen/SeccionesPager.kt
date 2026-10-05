package com.coolsistema.wearadmin.ui.resumen

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.background
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.pager.VerticalPager
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.wear.compose.material3.Text
import com.coolsistema.wearadmin.BuildConfig
import com.coolsistema.wearadmin.data.ResumenState
import com.coolsistema.wearadmin.ui.model.seccionesUi
import com.coolsistema.wearadmin.ui.theme.VentagoColors
import kotlinx.coroutines.launch

private const val PAGE_COUNT = 6
private const val REFRESH_PULL_THRESHOLD_DP = 48
private const val REFRESH_LOG_TAG = "VentagoRefresh"

/**
 * 여섯 섹션 세로 페이저(D-08·D-10) — VerticalPager 가 베젤/세로 스와이프로 페이지를
 * 넘긴다(회전 입력은 `androidx.wear.compose.foundation.pager` 의 기본 rotary 동작을
 * 그대로 쓴다 — 섹션 안 목록이 더 길 때 "목록을 먼저 내리고 끝이면 페이지 전환"하는
 * 세부 우선순위 튜닝은 실기기 베젤 확인(98-12)으로 미룬다, action 문구의 폴백 그대로).
 * Back: 섹션에서는 Hoy 로, Hoy 에서는 시스템 기본(종료). Hoy 맨 위에서 아래로 당기면
 * nestedScroll 의 onPostScroll 로 과스크롤을 감지해 새로고침 1회.
 */
@Composable
fun SeccionesPager(viewModel: ResumenViewModel, onAbrirSelector: () -> Unit) {
    val state by viewModel.state.collectAsState()
    val pagerState = rememberPagerState { PAGE_COUNT }
    val scope = rememberCoroutineScope()

    BackHandler(enabled = pagerState.currentPage > 0) {
        scope.launch { pagerState.animateScrollToPage(0) }
    }

    val thresholdPx = with(LocalDensity.current) { REFRESH_PULL_THRESHOLD_DP.dp.toPx() }
    var pullAccum by remember { mutableStateOf(0f) }
    var refreshTriggered by remember { mutableStateOf(false) }

    val pullToRefreshConnection = remember {
        object : NestedScrollConnection {
            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                if (pagerState.currentPage == 0 && available.y > 0f) {
                    pullAccum += available.y
                    if (pullAccum > thresholdPx && !refreshTriggered) {
                        refreshTriggered = true
                        if (BuildConfig.DEBUG) Log.d(REFRESH_LOG_TAG, "refresh")
                        viewModel.refresh()
                    }
                } else {
                    pullAccum = 0f
                    refreshTriggered = false
                }
                return Offset.Zero
            }
        }
    }

    when (val current = state) {
        null -> LoadingSeccion()
        is ResumenState.Unpaired -> LoadingSeccion()
        is ResumenState.Error -> LoadingSeccion()
        is ResumenState.Fresh, is ResumenState.Stale -> {
            val secciones = seccionesUi(current, System.currentTimeMillis())
            Box(modifier = Modifier.fillMaxSize().nestedScroll(pullToRefreshConnection)) {
                VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                    when (page) {
                        0 -> HoyScreen(secciones.hoy, onAbrirSelector)
                        1 -> MediosScreen(secciones.mediosPago, onAbrirSelector)
                        2 -> GastosDescScreen(secciones.gastosDescuentos, onAbrirSelector)
                        3 -> IngresosScreen(secciones.ingresos, onAbrirSelector)
                        4 -> FacturacionScreen(secciones.facturacionMes, onAbrirSelector)
                        5 -> CajasScreen(secciones.cajas, onAbrirSelector)
                    }
                }
                PageDots(
                    pageCount = PAGE_COUNT,
                    currentPage = pagerState.currentPage,
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(end = 4.dp)
                        .fillMaxHeight(0.5f),
                )
            }
        }
    }
}

@Composable
private fun LoadingSeccion() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text = "Cargando…", color = VentagoColors.Muted)
    }
}

/** 목업 v2 의 `.dots` — 활성 페이지만 골드 세로 막대, 나머지는 작은 회색 점. */
@Composable
private fun PageDots(pageCount: Int, currentPage: Int, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        repeat(pageCount) { index ->
            val activo = index == currentPage
            val dotSize = if (activo) Modifier.size(width = 2.dp, height = 9.dp) else Modifier.size(4.dp)
            Box(
                modifier = dotSize.background(
                    color = if (activo) VentagoColors.Gold else VentagoColors.MedioGray,
                    shape = RoundedCornerShape(50),
                ),
            )
        }
    }
}
