#!/bin/bash
# Run the JUCE standalone host for juce-cmp
set -e
cd "$(dirname "$0")/.."

# Build if needed
if [ ! -d "build/juce" ]; then
    echo "Building JUCE host..."
    ./scripts/build.sh
fi

# Find and run the standalone app
if [ "$(uname)" == "Darwin" ]; then
    # Try Debug build first, then Release/default
    if [ -f "build/juce/juce-cmp_artefacts/Debug/Standalone/juce-cmp.app/Contents/MacOS/juce-cmp" ]; then
        APP="build/juce/juce-cmp_artefacts/Debug/Standalone/juce-cmp.app/Contents/MacOS/juce-cmp"
    elif [ -f "build/juce/juce-cmp_artefacts/Standalone/juce-cmp.app/Contents/MacOS/juce-cmp" ]; then
        APP="build/juce/juce-cmp_artefacts/Standalone/juce-cmp.app/Contents/MacOS/juce-cmp"
    else
        echo "Error: JUCE standalone not found"
        echo "Run ./scripts/build.sh first"
        exit 1
    fi
    exec "$APP"
else
    echo "JUCE host not yet supported on this platform"
    exit 1
fi
