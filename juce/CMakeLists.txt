cmake_minimum_required(VERSION 3.22)
project(cmp-embed-juce VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Fetch JUCE from GitHub
include(FetchContent)
FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        8.0.4
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(JUCE)

# Define plugin/standalone target
juce_add_plugin(CMPEmbedHost
    COMPANY_NAME "CMPEmbed"
    BUNDLE_ID "com.cmpembed.host"
    PLUGIN_MANUFACTURER_CODE CMPe
    PLUGIN_CODE CMPh
    FORMATS Standalone  # Start with Standalone, add AU VST3 later
    PRODUCT_NAME "CMP Embed Host"
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_SYNTH FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
)

target_sources(CMPEmbedHost
    PRIVATE
        PluginProcessor.cpp
        PluginProcessor.h
        PluginEditor.cpp
        PluginEditor.h
        bridge/IOSurfaceComponent.mm
        bridge/IOSurfaceComponent.h
        bridge/IOSurfaceProvider.mm
        bridge/IOSurfaceProvider.h
        bridge/InputSender.cpp
        bridge/InputSender.h
        bridge/UIReceiver.h
)

target_include_directories(CMPEmbedHost
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/../common
)

target_compile_definitions(CMPEmbedHost
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0
)

target_link_libraries(CMPEmbedHost
    PRIVATE
        juce::juce_audio_utils
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags
)

# Platform-specific frameworks
if(APPLE)
    target_link_libraries(CMPEmbedHost PRIVATE 
        "-framework IOSurface"
        "-framework CoreVideo"
    )
endif()
