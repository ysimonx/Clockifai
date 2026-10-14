import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé d'envoi Google Play, hors du dépôt (make app-android-keystore, à sauvegarder) :
// ~/.config/clockifai/android/key.properties (storeFile, storePassword, keyAlias, keyPassword).
val uploadKey = Properties().apply {
    val path = System.getenv("CLOCKIFAI_ANDROID_KEY_PROPERTIES")
        ?: "${System.getProperty("user.home")}/.config/clockifai/android/key.properties"
    val file = File(path)
    if (file.exists()) FileInputStream(file).use { load(it) }
}

android {
    namespace = "com.kysoe.clockifai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Nom de l'app par type de build (resValue app_name) : « Clockifai » ou « Clockifai Dev ».
    buildFeatures {
        resValues = true
    }

    compileOptions {
        // Requis par flutter_local_notifications (API java.time sur anciens Android)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kysoe.clockifai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "Clockifai")
    }

    signingConfigs {
        if (!uploadKey.isEmpty) {
            create("upload") {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // « Clockifai Dev » : pile locale, installable à côté de la version du Play Store.
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Clockifai Dev")
        }
        release {
            // Sans clé d'envoi (autre poste), signature de debug : `flutter run --release` fonctionne quand même ;
            // make app-dist-android exige la clé.
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
