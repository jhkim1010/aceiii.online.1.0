package com.example.despacho_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // [2026-10-24] actualización dentro de la app (mismo canal que mobile-sales-app)
        Actualizacion.registrar(flutterEngine, applicationContext)
    }
}
