rootProject.name = "github-mobile-maxxing"
enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

pluginManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
    }
}

include(":core:model")
include(":core:auth")
include(":core:network")
include(":core:ui")
include(":composeApp")
include(":androidApp")

// Kotlin bridge framework for the native SwiftUI app; lives next to it under iosNativeApp/.
include(":iosNativeShared")
project(":iosNativeShared").projectDir = file("iosNativeApp/shared")
