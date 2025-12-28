#!/bin/bash
# Build script for KMP Embed
# Builds: Native renderer (Metal) → UI (Compose) → Host (macOS app)
set -e
cd "$(dirname "$0")/.."

#
# 1. Native Metal Renderer Library
#    Builds libiosurface_renderer.dylib - provides Metal device/queue/texture for Skia
#
echo "=== Building Native Renderer ==="
clang -dynamiclib \
    -o ui/composeApp/src/jvmMain/resources/libiosurface_renderer.dylib \
    ui/composeApp/src/jvmMain/cpp/iosurface_renderer.m \
    -framework IOSurface \
    -framework Metal \
    -framework Foundation \
    -fobjc-arc \
    -O2

#
# 2. Compose UI Application
#    Builds the KMP Compose Desktop app as a native distributable
#
echo "=== Building UI ==="
cd ui
./gradlew :composeApp:createDistributable --quiet
cd ..

#
# 3. Host Application
#    Builds the native macOS host that displays the IOSurface
#
echo "=== Building Host ==="
cd host
rm -rf build
cmake -B build
cmake --build build
cd ..

echo "=== Build Complete ==="
