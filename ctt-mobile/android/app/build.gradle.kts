plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cl.ctt.ctt_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cl.ctt.ctt_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Minificación R8 explícita (antes venía inyectada por el plugin de
            // Flutter, sin que este bloque la declarara). El proguard-rules.pro
            // del app NO se lee si no se referencia con proguardFiles: el build
            // previo no lo consumió por eso (ver configuration.txt).
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// Crashlytics 2.8.1 usa XmlSlurper de Groovy, incompatible con Gradle 9.x.
// Desactiva uploadCrashlyticsMappingFile* para release hasta migrar al plugin 3.x.
// Impacto: stack traces en Crashlytics no se desofuscan — aceptable en UAT con
// debug signing, donde ProGuard no está activo de todas formas.
afterEvaluate {
    tasks.matching { it.name.startsWith("uploadCrashlyticsMappingFile") }
        .forEach { it.enabled = false }
}
