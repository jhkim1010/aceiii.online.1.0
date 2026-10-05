package com.coolsistema.wearadmin.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.coolsistema.wearadmin.ui.pairing.PairingScreen
import com.coolsistema.wearadmin.ui.pairing.PairingViewModel
import com.coolsistema.wearadmin.ui.resumen.ResumenViewModel
import com.coolsistema.wearadmin.ui.resumen.SeccionesPager
import com.coolsistema.wearadmin.ui.selector.SelectorScreen
import kotlinx.coroutines.flow.collectLatest

private const val ROUTE_PAIRING = "pairing"
private const val ROUTE_SECCIONES = "secciones"
private const val ROUTE_SELECTOR = "selector"

/**
 * 내비게이션 그래프(98-11 Task 1) — "pairing"(Unpaired 시작점) · "secciones" · "selector"(D3).
 * `resumenViewModel.onUnpaired` 가 오면 백스택을 비우고 "pairing" 으로 돌아간다(401 즉시 반영,
 * D-05). 왼→오 스와이프 닫기는 SwipeDismissableNavHost 기본 동작 그대로(D-10 「→ = 시스템 뒤로」).
 */
@Composable
fun WearApp(
    pairingViewModel: PairingViewModel,
    resumenViewModel: ResumenViewModel,
    startDestination: String,
) {
    val navController = rememberSwipeDismissableNavController()

    LaunchedEffect(resumenViewModel) {
        resumenViewModel.onUnpaired.collectLatest {
            navController.navigate(ROUTE_PAIRING) {
                popUpTo(0) { inclusive = true }
            }
        }
    }

    AppScaffold {
        SwipeDismissableNavHost(navController = navController, startDestination = startDestination) {
            composable(ROUTE_PAIRING) {
                PairingScreen(
                    viewModel = pairingViewModel,
                    onPaired = {
                        resumenViewModel.refresh()
                        navController.navigate(ROUTE_SECCIONES) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
                )
            }
            composable(ROUTE_SECCIONES) {
                SeccionesPager(
                    viewModel = resumenViewModel,
                    onAbrirSelector = { navController.navigate(ROUTE_SELECTOR) },
                )
            }
            composable(ROUTE_SELECTOR) {
                SelectorScreen(
                    viewModel = resumenViewModel,
                    onElegido = { navController.popBackStack() },
                )
            }
        }
    }
}
