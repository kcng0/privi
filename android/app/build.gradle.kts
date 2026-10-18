import java.util.Properties
import java.io.FileInputStream
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: load android/key.properties when present (local + CI).
// Never commit key.properties or *.jks / *.keystore (see .gitignore).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// An SDK selected explicitly by CI/local build must never fall back to Maven.
// Leave both properties unset to keep the current official SDK until migration.
val customLibvlcPath = providers.gradleProperty("priviLibvlcAar").orNull
val customLibvlcSha256 = providers.gradleProperty("priviLibvlcAarSha256").orNull
require((customLibvlcPath == null) == (customLibvlcSha256 == null)) {
    "Set both priviLibvlcAar and priviLibvlcAarSha256 for a fixed-source LibVLC SDK"
}
val customLibvlcAar = customLibvlcPath?.let { path ->
    val aar = file(path)
    require(aar.isFile) { "Selected LibVLC SDK AAR is missing: $aar" }
    require(customLibvlcSha256!!.matches(Regex("[0-9a-f]{64}"))) {
        "priviLibvlcAarSha256 must be the explicit lowercase SHA-256 of the selected AAR"
    }
    val digest = MessageDigest.getInstance("SHA-256")
    aar.inputStream().use { stream ->
        val buffer = ByteArray(1024 * 1024)
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    val actual = digest.digest().joinToString("") { "%02x".format(it) }
    require(actual == customLibvlcSha256) {
        "Selected LibVLC SDK SHA-256 mismatch: expected $customLibvlcSha256, got $actual"
    }
    aar
}

android {
    namespace = "com.privi.app"
    // receive_sharing_intent requires 37+; higher compileSdk is backward compatible.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.privi.app"
        // Product baseline documented in the architecture and install guides.
        minSdk = 26
        // Keep current Play / Play Protect baseline (API 34+ required; 36 is fine).
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("profile") {
            // Performance runs must never replace the installed private vault.
            applicationIdSuffix = ".playbackprofile"
        }
        release {
            // Prefer a permanent release keystore (Play Protect reputation).
            // Falls back to debug only for local `flutter run --release` convenience
            // when key.properties is missing — CI must always provide the release key.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 + resource shrink: smaller APK and fewer generic-scanner false positives.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            // GitHub distributes one APK containing all supported ABIs. Compress
            // native libraries for download; Android extracts the device's ABI
            // during installation instead of loading directly from the APK.
            useLegacyPackaging = true
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
    if (customLibvlcAar == null) {
        implementation("org.videolan.android:libvlc-all:3.7.7")
    } else {
        implementation(files(customLibvlcAar))
        // Preserve the official 3.7.7 POM's dependencies when using a file AAR.
        implementation("androidx.annotation:annotation:1.7.1")
        implementation("androidx.legacy:legacy-support-v4:1.0.0")
        implementation("org.jetbrains.kotlin:kotlin-stdlib:2.2.10")
    }
}
