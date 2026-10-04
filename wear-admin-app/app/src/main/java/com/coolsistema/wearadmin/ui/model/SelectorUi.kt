package com.coolsistema.wearadmin.ui.model

import com.coolsistema.wearadmin.data.Resumen
import com.coolsistema.wearadmin.format.abreviarMonto

/** D3 선택기 한 줄 — id=null 은 "Todas". */
data class OpcionSucursal(val id: Int?, val etiqueta: String, val monto: String, val elegida: Boolean)

/**
 * Todas + 지점별(응답 순서 그대로, 서버가 이미 적절히 준다) 선택기 목록.
 * 지점이 1개인 매장(D-15 ⑥)은 선택기 자체가 없다 — 빈 목록을 반환해 화면이 진입하지 않게 한다.
 */
fun selectorUi(resumen: Resumen, seleccion: Int?): List<OpcionSucursal> {
    if (resumen.sucursales.size <= 1) return emptyList()

    val totalMonto = resumen.sucursales.sumOf { it.ventasHoy }
    val opciones = mutableListOf(
        OpcionSucursal(null, "Todas", abreviarMonto(totalMonto), elegida = seleccion == null),
    )
    resumen.sucursales.forEach { s ->
        opciones.add(OpcionSucursal(s.id, s.nombre, abreviarMonto(s.ventasHoy), elegida = seleccion == s.id))
    }
    return opciones
}
