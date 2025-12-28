#!/bin/sh
cd "$(dirname "$0")/../ui"

./gradlew :composeApp:hotRunJvm --auto

