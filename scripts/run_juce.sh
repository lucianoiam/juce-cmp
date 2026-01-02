#!/bin/bash
# Run the JUCE standalone host for CMP Embed
set -e
cd "$(dirname "$0")/.."

# Build if needed
if [ ! -d "build/juce" ]; then
    echo "Building JUCE host..."
    ./scripts/build.sh
fi

# Find and run the standalone app
if [ "$(uname)" == "Darwin" ]; then
    APP="build/juce/CMPEmbedHost_artefacts/Standalone/CMP Embed.app/Contents/MacOS/CMP Embed"
    if [ -f "$APP" ]; then
        exec "$APP"
    else
        echo "Error: JUCE standalone not found at: $APP"
        echo "Run ./scripts/build.sh first"
        exit 1
    fi
else
    echo "JUCE host not yet supported on this platform"
    exit 1
fi
