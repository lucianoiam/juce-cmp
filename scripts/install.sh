#!/bin/bash
# Install script for CMP Embed AU plugin
# Copies the AU plugin to ~/Library/Audio/Plug-Ins/Components/
set -e
cd "$(dirname "$0")/.."

AU_SRC="build/juce/CMPEmbedHost_artefacts/AU/CMP Embed.component"
AU_DEST="$HOME/Library/Audio/Plug-Ins/Components/CMP Embed.component"

if [ ! -d "$AU_SRC" ]; then
    echo "Error: AU plugin not found at $AU_SRC"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

echo "=== Installing CMP Embed AU Plugin ==="

# Remove old version if exists
if [ -d "$AU_DEST" ]; then
    echo "Removing old installation..."
    rm -rf "$AU_DEST"
fi

# Copy new version
echo "Copying to $AU_DEST..."
cp -R "$AU_SRC" "$AU_DEST"

# Reset audio component cache
echo "Resetting audio component cache..."
killall -9 AudioComponentRegistrar 2>/dev/null || true

echo "=== Installation complete ==="
echo ""
echo "Restart your DAW and rescan plugins to use CMP Embed."
echo "To validate: auval -v aumu CMPh CMPe"
