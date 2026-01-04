cmake_minimum_required(VERSION 3.22)
project(juce-cmp-demo VERSION 0.0.1)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add juce_cmp module to path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")

# Define plugin/standalone target
juce_add_plugin(juce-cmp-demo
    COMPANY_NAME "juce-cmp"
    BUNDLE_ID "com.juce-cmp.demo"
    PLUGIN_MANUFACTURER_CODE JCMm
    PLUGIN_CODE JCMs
    FORMATS Standalone AU
    PRODUCT_NAME "juce-cmp-demo"
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_SYNTH TRUE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
)

target_sources(juce-cmp-demo
    PRIVATE
        PluginProcessor.cpp
        PluginProcessor.h
        PluginEditor.cpp
        PluginEditor.h
)

target_compile_definitions(juce-cmp-demo
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
)

target_link_libraries(juce-cmp-demo
    PRIVATE
        juce_cmp
        juce::juce_audio_utils
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags
)

# Platform-specific bundle merging
if(APPLE)
    # Paths to Compose Desktop build outputs
    set(CMP_UI_APP "${CMAKE_SOURCE_DIR}/demo/ui/composeApp/build/compose/binaries/main/app/juce-cmp-demo.app")
    set(CMP_UI_CONTENTS "${CMP_UI_APP}/Contents")

    # Standalone - merge Compose runtime into bundle
    add_custom_command(TARGET juce-cmp-demo_Standalone POST_BUILD
        # Copy Compose launcher to MacOS/
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMP_UI_CONTENTS}/MacOS/juce-cmp-demo"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/MacOS/ui"
        # Copy JARs + Skiko dylib to app/
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMP_UI_CONTENTS}/app"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/app"
        # Rename config file to match binary name
        COMMAND ${CMAKE_COMMAND} -E rename
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/app/juce-cmp-demo.cfg"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/app/ui.cfg"
        # Copy jlink'd JVM to runtime/
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMP_UI_CONTENTS}/runtime"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/runtime"
        # Copy native renderer to app/
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_SOURCE_DIR}/juce_cmp_ui/lib/src/jvmMain/resources/libiosurface_renderer.dylib"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_Standalone>/Contents/app/libiosurface_renderer.dylib"
        COMMENT "Merging Compose runtime into Standalone bundle"
    )

    # AU plugin - merge Compose runtime
    add_custom_command(TARGET juce-cmp-demo_AU POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMP_UI_CONTENTS}/MacOS/juce-cmp-demo"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/MacOS/ui"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMP_UI_CONTENTS}/app"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/app"
        COMMAND ${CMAKE_COMMAND} -E rename
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/app/juce-cmp-demo.cfg"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/app/ui.cfg"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMP_UI_CONTENTS}/runtime"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/runtime"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_SOURCE_DIR}/juce_cmp_ui/lib/src/jvmMain/resources/libiosurface_renderer.dylib"
            "$<TARGET_BUNDLE_DIR:juce-cmp-demo_AU>/Contents/app/libiosurface_renderer.dylib"
        COMMENT "Merging Compose runtime into AU bundle"
    )
endif()
