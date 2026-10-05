package com.coolsistema.wearadmin

import android.content.Context
import android.content.Intent
import com.coolsistema.wearadmin.data.ResumenSource

/**
 * release 전용(98-11 Task 1) — 데모 주입 경로가 release APK 에는 존재하지 않는다
 * (T-98-30b). debug 구현(src/debug 의 같은 파일)과 같은 이름·시그니처를 가져 main 코드가
 * 빌드 타입에 상관없이 `DemoResumen.aplicar(intent, context)` 를 그대로 부를 수 있다.
 */
object DemoResumen {
    fun aplicar(intent: Intent?, context: Context): ResumenSource? = null
}
