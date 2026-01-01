cmake_minimum_required(VERSION 3.15)
project(standalone)

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")

# Standalone application - will become JUCE project later
add_executable(standalone MACOSX_BUNDLE
    main.m
    iosurface_provider.m
    input_cocoa.m
)
target_include_directories(standalone PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../common
)
target_link_libraries(standalone "-framework Cocoa" "-framework IOSurface" "-framework CoreVideo" "-framework QuartzCore")
