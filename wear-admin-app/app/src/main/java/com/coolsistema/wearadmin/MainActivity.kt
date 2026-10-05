package com.coolsistema.wearadmin

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.lifecycleScope
import com.coolsistema.wearadmin.ui.WearApp
import com.coolsistema.wearadmin.ui.pairing.PairingViewModel
import com.coolsistema.wearadmin.ui.resumen.ResumenViewModel
import com.coolsistema.wearadmin.ui.theme.VentagoWearTheme
import kotlinx.coroutines.runBlocking

/**
 * 진입 화면(98-11 Task 1) — 페어링 여부로 시작 라우트를 정하고(토큰 유무, debug 데모는
 * 항상 "secciones"), onResume 마다 즉시 갱신한다(D-10).
 */
class MainActivity : ComponentActivity() {
    private lateinit var resumenViewModel: ResumenViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val appGraph = AppGraph.from(application)
        val demoSource = DemoResumen.aplicar(intent, applicationContext)
        val resumenSource = demoSource ?: appGraph.resumenRepository

        val pairingViewModel = PairingViewModel(resumenSource, lifecycleScope)
        resumenViewModel = ResumenViewModel(resumenSource, lifecycleScope)

        val startDestination = if (demoSource != null) {
            "secciones"
        } else {
            val tienePareo = runBlocking { appGraph.tokenStore.getToken() != null }
            if (tienePareo) "secciones" else "pairing"
        }

        setContent {
            VentagoWearTheme {
                WearApp(
                    pairingViewModel = pairingViewModel,
                    resumenViewModel = resumenViewModel,
                    startDestination = startDestination,
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        resumenViewModel.onResume()
    }
}
