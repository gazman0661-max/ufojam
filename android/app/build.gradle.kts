plugins {
    id("com.android.application")
    // Flutter Gradle Plugin, Android ve Kotlin eklentilerinden sonra uygulanmalı.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ufobus.jam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
