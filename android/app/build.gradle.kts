plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin, Android ve Kotlin eklentilerinden sonra uygulanmalı.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ufobus.jam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.ufobus.jam"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Bilerek imza yok: release çıktısı (AAB) imzasız üretilir.
            // İmzalama bilgisayarda jarsigner ile elle yapılır (anahtar projede/CI'da tutulmaz).
        }
    }
}

flutter {
    source = "../.."
}
