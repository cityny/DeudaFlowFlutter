import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties (release signing)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.deudaflow.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.13846066"

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.deudaflow.app"
        
        // --- (INICIO DE LA CORRECCIÓN #2: MIN SDK) ---
        // Forzamos el SDK mínimo a 21 con la sintaxis de función.
        // Si el archivo se sigue reescribiendo a 'flutter.minSdkVersion', este valor
        // será sobrescrito por el bloque 'afterEvaluate' al final.
        minSdkVersion(21)
        // --- (FIN DE LA CORRECCIÓN #2) ---

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // --- (INICIO DE LA CORRECCIÓN #1: ARQUITECTURAS) ---
        // Forzamos las 4 arquitecturas para recuperar la compatibilidad x86
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86"))
        }
        // --- (FIN DE LA CORRECCIÓN #1) ---
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Bloque afterEvaluate para asegurar que minSdk se establece después
// de que todos los otros plugins (incluido Flutter) hayan configurado sus valores.
// Esto es para *forzar* minSdk a 21 y evitar que sea sobrescrito,
// incluso si la línea de defaultConfig es revertida por algún proceso automático.
// --- (INICIO DE LA CORRECCIÓN #2: MIN SDK - Sobrescritura final) ---
project.afterEvaluate {
    android {
        defaultConfig {
            minSdkVersion(21) // Aseguramos el SDK mínimo a 21 aquí, como último recurso.
        }
    }
}
// --- (FIN DE LA CORRECCIÓN #2) ---

flutter {
    source = "../.."
}