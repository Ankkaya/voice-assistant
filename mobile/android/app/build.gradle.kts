import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
}

val localSigningProperties = Properties()
val localSigningPropertiesFile = rootProject.file("key.properties")
if (localSigningPropertiesFile.exists()) {
    localSigningPropertiesFile.inputStream().use(localSigningProperties::load)
}

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf(String::isNotBlank)
        ?: localSigningProperties.getProperty(propertyName)?.takeIf(String::isNotBlank)

val releaseStoreFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseSigningValues = mapOf(
    "storeFile" to releaseStoreFile,
    "storePassword" to releaseStorePassword,
    "keyAlias" to releaseKeyAlias,
    "keyPassword" to releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.values.all { !it.isNullOrBlank() }
val hasPartialReleaseSigning = releaseSigningValues.values.any { !it.isNullOrBlank() } && !hasReleaseSigning
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (hasPartialReleaseSigning || (releaseBuildRequested && !hasReleaseSigning)) {
    val missing = releaseSigningValues.filterValues { it.isNullOrBlank() }.keys.joinToString()
    throw GradleException(
        "Release signing is incomplete. Missing: $missing. " +
            "Set Android signing environment variables or android/key.properties.",
    )
}

android {
    namespace = "com.example.childvoice"
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
        applicationId = "com.example.childvoice"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (providers.gradleProperty("arm64Only").orNull == "true") {
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(requireNotNull(releaseStoreFile))
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

val buildsSingleArm64Apk =
    providers.gradleProperty("split-per-abi").orNull == "true" &&
        providers.gradleProperty("target-platform").orNull == "android-arm64"
if (buildsSingleArm64Apk) {
    android.applicationVariants.configureEach {
        val configuredVersionCode = versionCode
        outputs.configureEach {
            (this as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride =
                configuredVersionCode
        }
    }
}

flutter {
    source = "../.."
}
