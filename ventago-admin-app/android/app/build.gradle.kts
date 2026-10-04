import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play 업로드 키 — 저장소 밖(~/android-keys/key.properties). 없으면 release 는 debug 키로 서명되지만
// AAB(bundle*) 는 Play 가 거부하므로 조용히 만들지 않고 실패시킨다.
val uploadKeyProps = Properties().apply {
    val f = file(System.getenv("ANDROID_KEY_PROPERTIES") ?: "${System.getProperty("user.home")}/android-keys/key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hasUploadKey = uploadKeyProps.getProperty("storeFile") != null
if (!hasUploadKey && gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }) {
    throw GradleException("AAB 빌드에는 업로드 키가 필요합니다: ~/android-keys/key.properties 가 없습니다.")
}

android {
    namespace = "com.coolsistema.ventago_admin_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.coolsistema.ventago_admin_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadKeyProps.getProperty("storeFile"))
                storePassword = uploadKeyProps.getProperty("storePassword")
                keyAlias = uploadKeyProps.getProperty("keyAlias")
                keyPassword = uploadKeyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
