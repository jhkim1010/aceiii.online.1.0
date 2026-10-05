package com.coolsistema.wearadmin.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material3.MaterialTheme

/**
 * 목업 v2 의 색(sketch-findings 스킬) — Compose [Color]. Tile·컴플리케이션(98-06) 의
 * ARGB `Int` 상수(GOLD/WHITE/MUTED)와 같은 값을 공유한다 — 표면 3개(앱·Tile·컴플리케이션)가
 * 각자 자기 레이어의 색 상수를 갖고 값만 맞춘다(한곳에서 ColorScheme 전체를 새로 정의하지
 * 않는다 — Material3 기본 타이포/셰이프는 그대로 쓴다).
 */
object VentagoColors {
    val Background = Color(0xFF000000)
    val Gold = Color(0xFFF5A623)
    val White = Color(0xFFFFFFFF)
    val Muted = Color(0xFFC9C7D4)
    val Up = Color(0xFF4CD78A)
    val Down = Color(0xFFFF7A6B)
    val ClosedOutline = Color(0xFF777777)
    val BancariasBlue = Color(0xFF5AA9FF)
    val MedioGray = Color(0xFF555555)
}

/** 테마 래퍼 — 화면 파일은 전부 이 아래에서 그려진다(MainActivity 가 한 번만 호출). */
@Composable
fun VentagoWearTheme(content: @Composable () -> Unit) {
    MaterialTheme(content = content)
}
