cmake_minimum_required(VERSION 3.15)
project(juce-cmp)

# Default to Debug build for development
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

# Paths
set(UI_DIR "${CMAKE_SOURCE_DIR}/ui")
set(NATIVE_RENDERER_SRC "${UI_DIR}/composeApp/src/jvmMain/cpp/iosurface_renderer.m")
set(NATIVE_RENDERER_OUT "${UI_DIR}/composeApp/src/jvmMain/resources/libiosurface_renderer.dylib")

#
# 1. Native Metal Renderer Library
#    Builds libiosurface_renderer.dylib for Compose/Skia to use
#
if(APPLE)
    add_custom_command(
        OUTPUT "${NATIVE_RENDERER_OUT}"
        COMMAND clang -dynamiclib
            -o "${NATIVE_RENDERER_OUT}"
            "${NATIVE_RENDERER_SRC}"
            -framework IOSurface
            -framework Metal
            -framework Foundation
            -fobjc-arc
            -O2
        DEPENDS "${NATIVE_RENDERER_SRC}"
        COMMENT "Building native Metal renderer library"
    )
    add_custom_target(native_renderer DEPENDS "${NATIVE_RENDERER_OUT}")
elseif(WIN32)
    # TODO: Windows DirectX/Vulkan renderer
    add_custom_target(native_renderer COMMENT "Windows renderer not yet implemented")
endif()

#
# 2. Compose UI Application
#    Builds the CMP Compose Desktop app as a native distributable
#
if(WIN32)
    set(GRADLE_CMD cmd /c gradlew.bat)
else()
    set(GRADLE_CMD ./gradlew)
endif()

# Glob all Kotlin source files to track changes
file(GLOB_RECURSE KOTLIN_SOURCES "${UI_DIR}/composeApp/src/*.kt")
list(APPEND KOTLIN_SOURCES "${UI_DIR}/composeApp/build.gradle.kts")

# Use a stamp file to track if build is needed (Gradle handles its own incrementality)
set(UI_STAMP_FILE "${CMAKE_CURRENT_BINARY_DIR}/ui.stamp")

add_custom_command(
    OUTPUT "${UI_STAMP_FILE}"
    COMMAND ${GRADLE_CMD} :composeApp:createDistributable --quiet
    COMMAND ${CMAKE_COMMAND} -E touch "${UI_STAMP_FILE}"
    WORKING_DIRECTORY "${UI_DIR}"
    DEPENDS ${KOTLIN_SOURCES} "${NATIVE_RENDERER_OUT}"
    COMMENT "Building Compose UI"
)

add_custom_target(ui DEPENDS "${UI_STAMP_FILE}")

#
# 3. Standalone Application (native Cocoa demo)
#
add_subdirectory(standalone)
add_dependencies(standalone ui)

#
# 4. JUCE Host Application (cross-platform plugin host)
#
add_subdirectory(juce)
add_dependencies(juce-cmp ui)
