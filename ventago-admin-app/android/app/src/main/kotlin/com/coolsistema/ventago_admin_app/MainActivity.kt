package com.coolsistema.ventago_admin_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// local_auth(지문) 는 FragmentActivity 를 요구한다.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // [2026-10-06] actualización dentro de la app
        Actualizacion.registrar(flutterEngine, applicationContext)
    }
}
