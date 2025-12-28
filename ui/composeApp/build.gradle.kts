import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    alias(libs.plugins.composeHotReload)
}

kotlin {
    jvmToolchain(21)
    jvm()
    
    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation(compose.components.resources)
            implementation(compose.components.uiToolingPreview)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
        jvmMain.dependencies {
            implementation(compose.desktop.currentOs)
            implementation(compose.ui)
            implementation(libs.kotlinx.coroutinesSwing)
            implementation("net.java.dev.jna:jna:5.14.0")
        }
    }
}


compose.desktop {
    application {
        mainClass = "com.lucianoiam.kmpui.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb)
            packageName = "com.lucianoiam.kmpui"
            packageVersion = "1.0.0"
        }
        
        // Set JNA library path to find libiosurface_ipc.dylib
        jvmArgs("-Djna.library.path=${project.rootDir.parentFile}/lib")
    }
}
