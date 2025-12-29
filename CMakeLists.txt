cmake_minimum_required(VERSION 3.15)
project(cmp-embed)

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

add_custom_target(ui
    COMMAND ${GRADLE_CMD} :composeApp:createDistributable --quiet
    WORKING_DIRECTORY "${UI_DIR}"
    COMMENT "Building Compose UI"
)
add_dependencies(ui native_renderer)

#
# 3. Standalone Application (subdirectory - will become JUCE project)
#
add_subdirectory(standalone)
add_dependencies(standalone ui)
