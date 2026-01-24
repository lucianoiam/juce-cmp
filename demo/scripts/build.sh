#!/bin/bash
# Build script for juce-cmp
# CMake orchestrates: Native renderer → UI (Compose) → Demo plugin
set -e
cd "$(dirname "$0")/../.."

echo "=== Building juce-cmp ==="

# Configure only if needed (build dir doesn't exist or CMakeLists.txt changed)
if [ ! -f build/CMakeCache.txt ] || [ CMakeLists.txt -nt build/CMakeCache.txt ]; then
    echo "=== Configuring CMake ==="
    cmake -B build
fi

# Build all targets
echo "=== Building native renderer ==="
cmake --build build --target native_renderer

echo "=== Building Compose UI ==="
cmake --build build --target ui

echo "=== Building demo standalone ==="
cmake --build build --target juce-cmp-demo_Standalone

echo "=== Building demo AU plugin ==="
cmake --build build --target juce-cmp-demo_AU

echo "=== Build complete ==="
