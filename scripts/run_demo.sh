#!/bin/bash
# Run the juce-cmp demo plugin
set -e
cd "$(dirname "$0")/.."

# Build if needed
if [ ! -d "build/demo" ]; then
    echo "Building demo..."
    ./scripts/build.sh
fi

# Find and run the standalone app
if [ "$(uname)" == "Darwin" ]; then
    # Try Debug build first, then Release/default
    if [ -f "build/demo/juce-cmp-demo_artefacts/Debug/Standalone/juce-cmp-demo.app/Contents/MacOS/juce-cmp-demo" ]; then
        APP="build/demo/juce-cmp-demo_artefacts/Debug/Standalone/juce-cmp-demo.app/Contents/MacOS/juce-cmp-demo"
    elif [ -f "build/demo/juce-cmp-demo_artefacts/Standalone/juce-cmp-demo.app/Contents/MacOS/juce-cmp-demo" ]; then
        APP="build/demo/juce-cmp-demo_artefacts/Standalone/juce-cmp-demo.app/Contents/MacOS/juce-cmp-demo"
    else
        echo "Error: Demo standalone not found"
        echo "Run ./scripts/build.sh first"
        exit 1
    fi
    exec "$APP"
else
    echo "Demo not yet supported on this platform"
    exit 1
fi
