import java.security.MessageDigest
import java.util.Properties
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.capsuleutkarsh.gleo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The store identity: fixed for good once the first build is uploaded to Google Play.
        // (namespace above is only the code package and can be renamed later.)
        applicationId = "com.capsuleutkarsh.gleo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // Android 8
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: android/key.properties (never committed) names the keystore and its passwords.
    // Without it the release APK is signed with the debug key (fine for testing, not for updates).
    val keys = rootProject.file("key.properties").takeIf { it.exists() }?.let { f -> Properties().apply { f.inputStream().use { load(it) } } }
    signingConfigs {
        if (keys != null) {
            create("release") {
                storeFile = rootProject.file(keys.getProperty("storeFile"))
                storePassword = keys.getProperty("storePassword")
                keyAlias = keys.getProperty("keyAlias")
                keyPassword = keys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keys != null) "release" else "debug")
        }
    }
}

// Gleo's own audio engine: libmpv.so (mpv + FFmpeg with the audio filters, soxr and bs2b), built in
// public at https://github.com/capsuleutkarsh-design/gleo-audio-engine. It replaces the libmpv.so of
// media_kit_libs_android_audio: the app's own jniLibs win over a dependency's.
// To update: set the new release tag and the SHA-256 of its zip (from the release's SHA256SUMS.txt).
// Downloads with curl (in Windows 10+, macOS and Linux), not Java: Java's connect timed out on the
// owner's network (it tried IPv6 first, and Gradle applies -Djava.net.preferIPv4Stack too late).
fun curl(url: String, to: File) {
    to.parentFile.mkdirs()
    check(ProcessBuilder("curl", "-fsSL", "--retry", "3", "-o", to.path, url).inheritIO().start().waitFor() == 0) {
        "Could not download $url"
    }
}
val gleoEngineTag = "v2026.10.14-android"
val gleoEngineSha256 = "a446d0ec91cbbb9d0ffbdddb39381567a592fca9e9a38121394df3dc8c00888a"
val gleoEngineLibs = layout.buildDirectory.dir("lumen-audio-engine-$gleoEngineTag/lib").get().asFile
val gleoEngineDone = File("$gleoEngineLibs.ok") // written last, so a half-done extract is redone
if (!gleoEngineDone.exists()) {
    val url = "https://github.com/capsuleutkarsh-design/gleo-audio-engine/releases/download/" +
        "$gleoEngineTag/lumen-audio-engine-$gleoEngineTag.zip"
    val file = File("$gleoEngineLibs.zip")
    curl(url, file)
    val zip = file.readBytes()
    val sha = MessageDigest.getInstance("SHA-256").digest(zip).joinToString("") { "%02x".format(it) }
    check(sha == gleoEngineSha256) { "Gleo audio engine: wrong SHA-256 $sha for $url" }
    gleoEngineLibs.deleteRecursively()
    ZipInputStream(zip.inputStream()).use { z ->
        generateSequence { z.nextEntry }.filter { !it.isDirectory && it.name.startsWith("lib/") }.forEach {
            File(gleoEngineLibs, it.name.removePrefix("lib/")).apply { parentFile.mkdirs() }.writeBytes(z.readBytes())
        }
    }
    file.delete()
    gleoEngineDone.writeText(sha)
}
android.sourceSets.getByName("main").jniLibs.srcDir(gleoEngineLibs)
// media_kit_libs_android_audio (evaluated after :app) downloads these jars with Java, unless they are already
// where it looks; it still checks their MD5. Only its libmediakitandroidhelper.so is used (libmpv.so is ours).
val mediaKitJars = rootProject.layout.buildDirectory.dir("media_kit_libs_android_audio/v1.1.8").get().asFile
for (abi in listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")) {
    val jar = File(mediaKitJars, "default-$abi.jar")
    if (!jar.exists()) curl("https://github.com/media-kit/libmpv-android-audio-build/releases/download/v1.1.8/${jar.name}", jar)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
