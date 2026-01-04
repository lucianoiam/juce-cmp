#!/bin/bash
# Generate LoadingPreview.h from loading_preview.png

PNG_FILE="demo/resources/loading_preview.png"
HEADER_FILE="juce_cmp/juce_cmp/LoadingPreview.h"

# Get file size
FILE_SIZE=$(wc -c < "$PNG_FILE" | tr -d ' ')

cat > "$HEADER_FILE" << HEADER_START
// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

// Auto-generated from loading_preview.png
// This image is displayed while the Compose UI child process loads.

namespace juce_cmp
{

HEADER_START

# Generate the array (excluding the length line from xxd)
xxd -i "$PNG_FILE" | grep -v "unsigned int" | sed 's/unsigned char .*\[\]/static const unsigned char loading_preview_png[]/' >> "$HEADER_FILE"

# Add the correct length
echo "static const unsigned int loading_preview_png_len = $FILE_SIZE;" >> "$HEADER_FILE"

cat >> "$HEADER_FILE" << 'HEADER_END'

}  // namespace juce_cmp
HEADER_END

echo "Generated $HEADER_FILE from $PNG_FILE ($FILE_SIZE bytes)"
