// Kotlin bridge for the native SwiftUI app (iosNativeApp). It exports core/model, core/auth and core/network as
// one static framework, so the Swift app reuses the shared networking, auth and caching logic and only the UI is
// written in Swift. Built from Xcode by the "Build Kotlin framework" phase (embedAndSignAppleFrameworkForXcode).
plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

kotlin {
    listOf(iosArm64(), iosSimulatorArm64()).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "MaxxingShared"
            isStatic = true
            export(projects.core.model)
            export(projects.core.auth)
            export(projects.core.network)
        }
    }

    sourceSets {
        iosMain.dependencies {
            api(projects.core.model)
            api(projects.core.auth)
            api(projects.core.network)
            implementation(libs.kotlinx.coroutines.core)
        }
    }
}
