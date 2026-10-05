package com.coolsistema.wearadmin.surface

import android.app.KeyguardManager
import android.content.Context

/**
 * 잠금 판정 — 요청 시점(Tile/컴플리케이션 서비스가 호출되는 순간) 기준(D-14 ②).
 * 그 순간 이후 잠기면 캐시된 Tile 이 남아 있을 수 있다 — 98-12 사람 검증 항목으로 넘긴다.
 */
fun isLocked(context: Context): Boolean {
    val keyguardManager = context.getSystemService(KeyguardManager::class.java) ?: return false
    return keyguardManager.isDeviceLocked
}
