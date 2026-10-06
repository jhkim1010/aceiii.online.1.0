package com.coolsistema.ventago_admin_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// [2026-10-06] Actualización dentro de la app (lib/core/update/actualizacion.dart).
// Canal «ventago/actualizacion»:
//   versionCode → versión instalada
//   dirDescarga → carpeta en caché para el APK (expuesta por FileProvider: res/xml/actualizacion_paths.xml)
//   instalar    → abre el instalador de Android ('ok'), o los ajustes de «instalar apps
//                 desconocidas» si falta el permiso ('permiso'). Android pide confirmar siempre.
object Actualizacion {
    fun registrar(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ventago/actualizacion").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "versionCode" -> {
                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
                        result.success(code)
                    }
                    "dirDescarga" -> {
                        val dir = File(context.cacheDir, "actualizacion")
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "instalar" -> {
                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                            val ajustes = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.packageName))
                            ajustes.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(ajustes)
                            result.success("permiso")
                        } else {
                            val archivo = File(call.argument<String>("ruta")!!)
                            val uri = FileProvider.getUriForFile(context, context.packageName + ".actualizacion", archivo)
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.setDataAndType(uri, "application/vnd.android.package-archive")
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success("ok")
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("actualizacion", e.message, null)
            }
        }
    }
}
