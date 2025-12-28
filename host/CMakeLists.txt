cmake_minimum_required(VERSION 3.10)
project(kmp-host)

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")

add_executable(kmp-host MACOSX_BUNDLE main.m iosurface_ipc.m)

target_include_directories(kmp-host PRIVATE ${CMAKE_SOURCE_DIR})

target_link_libraries(kmp-host "-framework Cocoa" "-framework IOSurface" "-framework CoreVideo")
