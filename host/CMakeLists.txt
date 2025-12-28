cmake_minimum_required(VERSION 3.10)
project(host)

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")

add_executable(host MACOSX_BUNDLE main.m iosurface_provider.m)

target_include_directories(host PRIVATE ${CMAKE_SOURCE_DIR})

target_link_libraries(host "-framework Cocoa" "-framework IOSurface" "-framework CoreVideo")
