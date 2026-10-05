package com.coolsistema.wearadmin.surface

import android.app.KeyguardManager
import android.content.Context

/**
 * 잠금 판정 — 요청 시점(Tile/컴플리케이션 서비스가 호출되는 순간) 기준(D-14 ②).
 * 그 순간 이후 잠기면 캐시된 Tile 이 남아 있을 수 있다 — 98-12 사람 검증 항목으로 넘긴다.
 *
 * fail-closed(98-14 CODEX 검토 C 의 P1 수정): [KeyguardManager] 조회 실패(서비스 null)나
 * [KeyguardManager.isDeviceLocked] 예외처럼 판정 불가일 때 "잠금 아님"(false)으로 떨어지면
 * 잠금 상태에서도 금액이 보일 수 있다 — 판정 불가는 항상 잠금(true, 금액을 가린다)으로 취급한다.
 */
fun isLocked(context: Context): Boolean = isLockedFrom {
    context.getSystemService(KeyguardManager::class.java)?.isDeviceLocked
}

/** 순수 함수 — [query] 가 null(판정 불가) 또는 예외를 던지면 fail-closed(true=잠금)로 처리한다. */
fun isLockedFrom(query: () -> Boolean?): Boolean =
    try {
        query() ?: true
    } catch (e: Exception) {
        true
    }
