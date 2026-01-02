#!/bin/bash
# Build script for CMP Embed
# CMake orchestrates: Native renderer → UI (Compose) → Standalone → JUCE Host
set -e
cd "$(dirname "$0")/.."

echo "=== Building CMP Embed ==="

# Configure
cmake -B build

# Build all targets
echo "=== Building native renderer ==="
cmake --build build --target native_renderer

echo "=== Building Compose UI ==="
cmake --build build --target ui

echo "=== Building Standalone app ==="
cmake --build build --target standalone

echo "=== Building JUCE host ==="
cmake --build build --target CMPEmbedHost_Standalone

echo "=== Building AU plugin ==="
cmake --build build --target CMPEmbedHost_AU

echo "=== Build complete ==="
