plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    // Giữ nguyên plugin google services
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.health_ai_app" // Đảm bảo namespace này khớp với cái cũ của bạn
    
    // [FIX]: Ghi cứng phiên bản SDK mới nhất (Android 14)
    compileSdk = 34
    ndkVersion = "25.0.3"

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
    }

    aaptOptions {
        noCompress("task")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
