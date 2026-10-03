// Stripped from `flutter create --template=plugin --platforms=android`: the
// unit-test block, the mockito and kotlin-test dependencies, and the example
// app are gone. What is left is what makes an Android library module that
// packages android/src/main/jniLibs/<abi>/libc++_shared.so into the consumer's
// APK — which is the whole point of the fixture (PRD §12.2 step 9).

group = "dev.wcf.eval.libcxx_plugin"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.wcf.eval.libcxx_plugin"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            // The default already, and stated so the one thing this module
            // exists for is visible in the file.
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
