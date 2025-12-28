#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "=== Building KMP UI ==="
cd ui
./gradlew :composeApp:createDistributable --quiet
cd ..

echo "=== Building Host App ==="
cd host
rm -rf build
cmake -B build
cmake --build build
cd ..

echo "=== Build Complete ==="
