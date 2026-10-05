plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.coolsistema.wearadmin"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.coolsistema.tienda_admin_app"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        val ventagoApiBase = (project.findProperty("ventagoApiBase") as String?)
            ?: "https://newapi.coolsistema.com/api"
        buildConfigField("String", "API_BASE", "\"$ventagoApiBase\"")
    }

    // release 서명(업로드 키)은 98-07 범위 — 여기서는 debug 빌드만 다룬다.
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // 98-11 Task 1: debug 빌드 전용 데모 데이터 — 골든 JSON 을 build/generated/demoAssets 로
    // 복사해 debug 소스셋 assets 로 포함한다(release 에는 없음 — DemoResumen.kt 가 debug/
    // release 두 구현으로 나뉘는 것과 같은 이유, action 문구 그대로).
    sourceSets["debug"].assets.srcDir(layout.buildDirectory.dir("generated/demoAssets"))
}

val copyDemoGoldenJson = tasks.register<Copy>("copyDemoGoldenJson") {
    from(rootProject.file("../api-ventago/test/fixtures/watch-resumen-v2.golden.json"))
    into(layout.buildDirectory.dir("generated/demoAssets"))
}

tasks.matching { it.name == "generateDebugAssets" || it.name == "mergeDebugAssets" }.configureEach {
    dependsOn(copyDemoGoldenJson)
}
tasks.matching { it.name == "preDebugUnitTestBuild" || it.name == "preDebugBuild" }.configureEach {
    dependsOn(copyDemoGoldenJson)
}

// ResumenDtoTest 가 api-ventago 의 골든 JSON 을 복사 없이 직접 읽는다(단일 출처).
tasks.withType<Test> {
    systemProperty(
        "ventago.goldenJson",
        rootProject.file("../api-ventago/test/fixtures/watch-resumen-v2.golden.json").absolutePath,
    )
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.wear)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    implementation(libs.wear.compose.material3)
    implementation(libs.wear.compose.foundation)
    implementation(libs.wear.compose.navigation)
    implementation(libs.wear.tiles)
    implementation(libs.wear.tiles.material)
    implementation(libs.wear.protolayout)
    implementation(libs.wear.protolayout.material3)
    implementation(libs.wear.protolayout.expression)
    implementation(libs.wear.watchface.complications.data.source.ktx)

    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.kotlinx.serialization)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    implementation(libs.androidx.datastore.preferences)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
}
