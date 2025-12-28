#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Build everything first
./scripts/build.sh

# Run the host app
./host/build/kmp-host.app/Contents/MacOS/kmp-host
