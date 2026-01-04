cmake_minimum_required(VERSION 3.15)
project(juce-cmp VERSION 0.0.1)

# Default to Debug build for development
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

#
# 1. Fetch JUCE
#
include(FetchContent)
FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        8.0.4
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(JUCE)

#
# 2. Add juce_cmp module
#
juce_add_module(juce_cmp)

#
# 3. Build Compose UI runtime
#
set(UI_DIR "${CMAKE_SOURCE_DIR}/juce_cmp_ui")
set(NATIVE_RENDERER_SRC "${UI_DIR}/lib/src/jvmMain/cpp/iosurface_renderer.m")
set(NATIVE_RENDERER_OUT "${UI_DIR}/lib/src/jvmMain/resources/libiosurface_renderer.dylib")

# Native Metal Renderer Library
if(APPLE)
    add_custom_command(
        OUTPUT "${NATIVE_RENDERER_OUT}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${UI_DIR}/lib/src/jvmMain/resources"
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
endif()

# Compose UI Application
set(DEMO_UI_DIR "${CMAKE_SOURCE_DIR}/demo/ui")

if(WIN32)
    set(GRADLE_CMD cmd /c gradlew.bat)
else()
    set(GRADLE_CMD ./gradlew)
endif()

file(GLOB_RECURSE KOTLIN_SOURCES "${DEMO_UI_DIR}/composeApp/src/*.kt")
list(APPEND KOTLIN_SOURCES "${DEMO_UI_DIR}/composeApp/build.gradle.kts")

set(UI_STAMP_FILE "${CMAKE_CURRENT_BINARY_DIR}/ui.stamp")

add_custom_command(
    OUTPUT "${UI_STAMP_FILE}"
    COMMAND ${GRADLE_CMD} :composeApp:createDistributable --quiet
    COMMAND ${CMAKE_COMMAND} -E touch "${UI_STAMP_FILE}"
    WORKING_DIRECTORY "${DEMO_UI_DIR}"
    DEPENDS ${KOTLIN_SOURCES} "${NATIVE_RENDERER_OUT}"
    COMMENT "Building Compose UI"
)

add_custom_target(ui DEPENDS "${UI_STAMP_FILE}")

#
# 4. Build demo plugin
#
add_subdirectory(demo)
add_dependencies(juce-cmp-demo ui)
