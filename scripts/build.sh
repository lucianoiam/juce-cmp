#!/bin/bash
# Build script for CMP Embed
# CMake orchestrates: Native renderer → UI (Compose) → Standalone (macOS app)
set -e
cd "$(dirname "$0")/.."

cmake -B build
cmake --build build
