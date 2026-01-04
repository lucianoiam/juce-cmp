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
            implementation("com.github.juce-cmp:lib")
        }
    }
}


compose.desktop {
    application {
        mainClass = "juce_cmp.demo.MainKt"

        jvmArgs += listOf(
            "--enable-native-access=ALL-UNNAMED"
        )

        nativeDistributions {
            packageName = "juce-cmp-demo"
            packageVersion = "1.0.0"
            
            jvmArgs += listOf(
                "--enable-native-access=ALL-UNNAMED"
            )
        }
    }
}

compose.resources {
    packageOfResClass = "juce_cmp.demo.resources"
}
