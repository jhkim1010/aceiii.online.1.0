package com.coolsistema.wearadmin.surface

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [isLockedFrom] 만 순수 JVM 시험 — [isLocked](Context 버전)는 KeyguardManager 를 요구해
 * Robolectric/Mockito 없이 단위 시험 불가(새 테스트 의존성 추가는 98-14 plan 범위 밖).
 *
 * 98-14 CODEX 검토 C 의 P1 지적(DeviceLock.kt:11/:12) — 판정 불가(서비스 null·예외)를
 * "잠금 아님"(fail-open)으로 처리하면 잠금 상태에서도 금액이 보일 수 있다(D-14 ②).
 * fail-closed(판정 불가 → 잠금으로 취급)가 맞다.
 */
class DeviceLockTest {

    @Test
    fun `잠김 true 그대로 전달`() {
        assertTrue(isLockedFrom { true })
    }

    @Test
    fun `잠김 false 그대로 전달`() {
        assertFalse(isLockedFrom { false })
    }

    @Test
    fun `판정 불가(null)면 fail-closed로 잠금 취급`() {
        assertTrue(isLockedFrom { null })
    }

    @Test
    fun `예외 발생 시 fail-closed로 잠금 취급`() {
        assertTrue(isLockedFrom { throw IllegalStateException("boom") })
    }
}
