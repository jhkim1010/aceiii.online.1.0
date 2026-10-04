package com.coolsistema.wearadmin.format

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * D-07 축약 금액 표기 — 앱·Tile·컴플리케이션 공용 순수 함수.
 *
 * 기기 로케일에 좌우되는 표준 포맷 클래스는 쓰지 않는다(기기 로케일마다 소수점·구분자가
 * 달라지지 않게, 메모리: 이 저장소는 이미 로케일 의존 포맷 버그를 여러 번 겪었다). 문자열은
 * 콤마(,) 소수점·점(.) 천 단위 구분자를 직접 조립한다(es-AR 규약).
 */

private val MILLON = BigDecimal(1_000_000)
private val MIL = BigDecimal(1_000)

/** 긴 형: "$1,28 M" · "$842 K" · "$999" · "-$15 K" (D-07). */
fun abreviarMonto(value: Double): String {
    val bd = BigDecimal(value)
    val negative = bd.signum() < 0
    val abs = bd.abs()
    val sign = if (negative) "-" else ""

    // 정수로 반올림한 값이 1000 미만이면 그대로 표시(999.6 처럼 반올림으로 1000 을
    // 넘는 값은 여기서 걸러져 아래 K 분기로 간다 — "$1000" 이 절대 나오지 않는다).
    val roundedInt = abs.setScale(0, RoundingMode.HALF_UP)
    if (roundedInt < MIL) {
        return sign + "$" + formatInteger(roundedInt)
    }

    // 백만 단위로 반올림한 값이 1.00 이상이면 M(천 단위 반올림이 1000 이 되는
    // 999_600 같은 경우도 자연히 여기로 올라온다).
    val millones = abs.divide(MILLON, 2, RoundingMode.HALF_UP)
    if (millones >= BigDecimal.ONE) {
        return sign + "$" + formatDecimal2(millones) + " M"
    }

    val miles = abs.divide(MIL, 0, RoundingMode.HALF_UP)
    return sign + "$" + formatInteger(miles) + " K"
}

/** 짧은 형(컴플리케이션 SHORT_TEXT 용): "15,2M" · "842K" · "999" · 100M 이상은 소수 없음, 7자 이내. */
fun abreviarCorto(value: Double): String {
    val bd = BigDecimal(value).abs()
    return when {
        bd >= BigDecimal(100_000_000) -> {
            val millones = bd.divide(MILLON).setScale(0, RoundingMode.HALF_UP)
            "${formatInteger(millones)}M"
        }
        bd >= MILLON -> {
            val millones = bd.divide(MILLON).setScale(1, RoundingMode.HALF_UP)
            "${formatDecimal1(millones)}M"
        }
        bd >= MIL -> {
            val miles = bd.divide(MIL).setScale(0, RoundingMode.HALF_UP)
            "${formatInteger(miles)}K"
        }
        else -> formatInteger(bd.setScale(0, RoundingMode.HALF_UP))
    }
}

/** 오늘/어제 같은 시각 대비 증감률(%), base==0 이면 비교 불가(null). */
fun deltaPct(today: Double, base: Double): Int? {
    if (base == 0.0) return null
    val pct = BigDecimal((today - base) / base * 100.0).setScale(0, RoundingMode.HALF_UP)
    return pct.toInt()
}

/** "▲ 12% vs ayer a esta hora" · "▼ 4% ..." · "= vs ..." · null -> "". */
fun formatDelta(pct: Int?): String {
    if (pct == null) return ""
    val arrow = when {
        pct > 0 -> "▲"
        pct < 0 -> "▼"
        else -> "="
    }
    val suffix = "vs ayer a esta hora"
    return if (pct == 0) "$arrow $suffix" else "$arrow ${kotlin.math.abs(pct)}% $suffix"
}

/** 천 단위 점 구분자: 1398 -> "1.398". */
fun formatCantidad(value: Int): String = formatInteger(BigDecimal(value))

// --- ensamblado manual de texto (sin clases de formato estándar del sistema) ---

private fun formatInteger(value: BigDecimal): String {
    val negative = value.signum() < 0
    val digits = value.abs().toBigInteger().toString()
    val grouped = groupThousands(digits)
    return if (negative) "-$grouped" else grouped
}

private fun formatDecimal2(value: BigDecimal): String {
    val scaled = value.setScale(2, RoundingMode.HALF_UP)
    val unscaledStr = scaled.unscaledValue().abs().toString().padStart(3, '0')
    val intPart = unscaledStr.dropLast(2).ifEmpty { "0" }
    val fracPart = unscaledStr.takeLast(2)
    val sign = if (scaled.signum() < 0) "-" else ""
    return "$sign${groupThousands(intPart)},$fracPart"
}

private fun formatDecimal1(value: BigDecimal): String {
    val scaled = value.setScale(1, RoundingMode.HALF_UP)
    val unscaledStr = scaled.unscaledValue().abs().toString().padStart(2, '0')
    val intPart = unscaledStr.dropLast(1).ifEmpty { "0" }
    val fracPart = unscaledStr.takeLast(1)
    val sign = if (scaled.signum() < 0) "-" else ""
    return "$sign${groupThousands(intPart)},$fracPart"
}

private fun groupThousands(digits: String): String {
    val sb = StringBuilder()
    for ((i, c) in digits.withIndex()) {
        val posFromEnd = digits.length - i
        if (i != 0 && posFromEnd % 3 == 0) sb.append('.')
        sb.append(c)
    }
    return sb.toString()
}
