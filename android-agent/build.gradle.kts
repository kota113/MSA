import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application") version "9.1.1"
}

val systemApiJar = layout.projectDirectory.file("system-stubs/android.jar")

android {
    namespace = "dev.macwsa.agent"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.macwsa.agent"
        minSdk = 36
        targetSdk = 36
        versionCode = 2
        versionName = "0.2.0"
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile("AndroidManifest.xml")
            java.setSrcDirs(listOf("src"))
            res.setSrcDirs(listOf("res"))
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.withType<JavaCompile>().configureEach {
    require(systemApiJar.asFile.exists()) {
        "Missing system-stubs/android.jar; run ../scripts/fetch-android-prebuilts.sh"
    }
    options.bootstrapClasspath = files(systemApiJar)
    doFirst {
        classpath = files(systemApiJar) + classpath
    }
}
