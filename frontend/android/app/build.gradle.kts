import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    // Giữ nguyên plugin google services
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
val releaseStorePassword = keystoreProperties.getProperty("storePassword")?.takeIf { it.isNotBlank() }
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")?.takeIf { it.isNotBlank() }
val canSignRelease = hasReleaseKeystore &&
    releaseStoreFile != null &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

android {
    namespace = "com.example.health_ai_app" // Đảm bảo namespace này khớp với cái cũ của bạn
    
    // [FIX]: Ghi cứng phiên bản SDK mới nhất (Android 14)
    compileSdk = 34
    ndkVersion = "27.0.12077973"

    // [FIX]: Ép buộc sử dụng Build Tools mới, bỏ qua bản 25.0.1 cũ
    buildToolsVersion = "34.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ID ứng dụng của bạn
        applicationId = "com.example.health_ai_app"
        
        // [W1-B PoC]: Min SDK set to 24 for MediaPipe Tasks Vision compatibility (baseline was 21)
        minSdk = 24
        targetSdk = 34
        
        versionCode = flutter.versionCode()
        versionName = flutter.versionName()

        val fbAppId = (project.findProperty("FACEBOOK_APP_ID") as String?)
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("FACEBOOK_APP_ID")?.takeIf { it.isNotBlank() }
        val fbClientToken = (project.findProperty("FACEBOOK_CLIENT_TOKEN") as String?)
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("FACEBOOK_CLIENT_TOKEN")?.takeIf { it.isNotBlank() }
        val fbLoginProtocolScheme = (project.findProperty("FB_LOGIN_PROTOCOL_SCHEME") as String?)
            ?.takeIf { it.isNotBlank() }
            ?: System.getenv("FB_LOGIN_PROTOCOL_SCHEME")?.takeIf { it.isNotBlank() }
            ?: fbAppId?.let { "fb$it" }

        manifestPlaceholders["facebookAppId"] = fbAppId ?: "@string/facebook_app_id"
        manifestPlaceholders["facebookClientToken"] =
            fbClientToken ?: "@string/facebook_client_token"
        manifestPlaceholders["fbLoginProtocolScheme"] =
            fbLoginProtocolScheme ?: "@string/fb_login_protocol_scheme"
    }

    aaptOptions {
        noCompress("task")
    }

    signingConfigs {
        if (canSignRelease) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (canSignRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
