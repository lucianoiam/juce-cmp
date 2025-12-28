#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Build everything first
./scripts/build.sh

# Run the host app
./host/build/host.app/Contents/MacOS/host
