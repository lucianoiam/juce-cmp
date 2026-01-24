#!/bin/bash
# Build script for juce-cmp
set -e
cd "$(dirname "$0")/../.."

# Configure only on first build
if [ ! -f build/CMakeCache.txt ]; then
    cmake -B build
fi

# Build (cmake handles incremental builds)
cmake --build build
