#!/bin/bash
# Build the GPU renderer native library
set -e

cd "$(dirname "$0")"

echo "Building libiosurface_renderer.dylib..."

clang -dynamiclib -o ../resources/libiosurface_renderer.dylib \
    iosurface_renderer.m \
    -framework IOSurface \
    -framework Metal \
    -framework Foundation \
    -fobjc-arc \
    -O2

echo "Built: $(pwd)/../resources/libiosurface_renderer.dylib"
