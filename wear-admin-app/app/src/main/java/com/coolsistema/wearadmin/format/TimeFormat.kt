package com.coolsistema.wearadmin.format

/**
 * 경과 시간·월 표기 순수 함수(앱·Tile·컴플리케이션 공용). Android 의존 없음(JVM 단위 시험).
 */

private val MESES = arrayOf(
    "ENE", "FEB", "MAR", "ABR", "MAY", "JUN",
    "JUL", "AGO", "SEP", "OCT", "NOV", "DIC",
)

/** "recién" · "hace 12 min" · "hace 3 h" · "hace 2 días" — Tile/컴플리케이션의 갱신 경과 표시(Pitfall 3). */
fun haceTexto(fetchedAtMillis: Long, nowMillis: Long): String {
    val deltaMs = (nowMillis - fetchedAtMillis).coerceAtLeast(0)
    val minutes = deltaMs / 60_000L
    if (minutes < 1) return "recién"

    val hours = deltaMs / 3_600_000L
    if (hours < 1) return "hace $minutes min"

    val days = deltaMs / 86_400_000L
    if (days < 1) return "hace $hours h"

    return "hace $days días"
}

/** "YYYY-MM" -> "OCT 2026"(스페인어 대문자 3자 + 연도). */
fun mesCorto(yyyyMm: String): String {
    val parts = yyyyMm.split("-")
    require(parts.size == 2) { "Formato esperado YYYY-MM: $yyyyMm" }
    val year = parts[0]
    val month = parts[1].toInt()
    require(month in 1..12) { "Mes fuera de rango: $month" }
    return "${MESES[month - 1]} $year"
}
