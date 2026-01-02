# CMP Embed

Embeds a Compose Multiplatform (Compose Desktop) UI inside a JUCE audio plugin using IOSurface for zero-copy GPU rendering and binary IPC for input forwarding.

## Quick Start

```bash
# Build everything
./scripts/build.sh

# Install AU plugin to ~/Library/Audio/Plug-Ins/Components/
./scripts/install.sh

# Run standalone app for testing
./scripts/run_juce.sh
```

**Prerequisites:**
- macOS 10.15+
- JDK 17+ (`brew install openjdk@17`)
- CMake 3.15+ (`brew install cmake`)
- Xcode Command Line Tools (`xcode-select --install`)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  JUCE Plugin (AU / Standalone)                          │
│  - IOSurfaceComponent creates shared GPU surface        │
│  - SurfaceView (NSView) displays via CALayer            │
│  - CVDisplayLink for vsync-synchronized refresh         │
│  - Transparent JUCE component captures input events     │
│  - Launches Compose UI as child process                 │
└─────────────────┬───────────────────────────────────────┘
                  │ IOSurface ID (arg)    Input events (stdin)
                  ▼
┌─────────────────────────────────────────────────────────┐
│  UI (Compose Desktop / Skia / Metal)                    │
│  - Renders directly to IOSurface-backed Metal texture   │
│  - Receives input events, injects into ComposeScene     │
│  - Zero CPU pixel copies, invalidation-based rendering  │
└─────────────────────────────────────────────────────────┘
```

**Rendering:** The plugin creates an IOSurface and passes its ID to the child process. The Compose UI uses Skia's Metal backend to render directly to the shared surface—no CPU copies involved. Rendering is invalidation-based: frames are only rendered when the scene changes.

**Input:** Mouse/keyboard events are captured in the plugin and sent to the child via a 16-byte binary protocol over stdin. The UI deserializes and injects them into the Compose scene.

## Build

```bash
./scripts/build.sh
```

This builds:
1. **Native Metal renderer** (`libiosurface_renderer.dylib`)
2. **Compose UI app** (`cmpui.app` with bundled JRE)
3. **AU plugin** (`CMP Embed.component` - uses JUCE 8.0.4)
4. **Standalone app** (`CMP Embed.app` for testing outside DAW)

## Install AU Plugin

```bash
./scripts/install.sh
```

This copies `CMP Embed.component` to `~/Library/Audio/Plug-Ins/Components/` and resets the audio component cache. Restart your DAW and rescan plugins.

To validate: `auval -v aumu CMPh CMPe`

## Run

```bash
# Run standalone for testing
./scripts/run_juce.sh
```

Or use the AU plugin in any DAW after running `./scripts/install.sh`.

## Project Structure

```
common/                # Cross-platform shared code
  input_protocol.h     # Binary input event protocol (16 bytes/event)

juce/                  # JUCE audio plugin
  PluginProcessor.cpp/h    # Passthrough audio processor
  PluginEditor.cpp/h       # Editor hosting IOSurfaceComponent
  IOSurfaceComponent.mm/h  # Displays IOSurface, captures input
  IOSurfaceProvider.mm/h   # Creates IOSurface, launches child
  InputSender.cpp/h        # Sends input events via stdin pipe
  CMakeLists.txt           # Fetches JUCE 8.0.4, builds plugin

ui/composeApp/         # Kotlin Multiplatform Compose application
  src/jvmMain/
    kotlin/cmpui/
      main.kt          # Entry point
      App.kt           # Compose UI (demo app)
      input/           # Input event handling
        InputReceiver.kt   # Reads binary events from stdin
        InputDispatcher.kt # Injects events into ComposeScene
      renderer/        # IOSurface rendering
        IOSurfaceRendererGPU.kt  # Zero-copy Metal path (default)
    cpp/
      iosurface_renderer.m       # Native Metal bridge for Skia

standalone/            # Native macOS app (for exploring foreign process embedding)

scripts/
  build.sh             # Build everything
  install.sh           # Install AU to ~/Library/Audio/Plug-Ins/Components/
  run_juce.sh          # Build and run standalone app
```

## Flags

The UI app supports:
- `--embed` - Run as embedded renderer (used when launched by plugin)
- `--iosurface-id=<id>` - IOSurface to render to
- `--disable-gpu` - Use CPU software rendering instead of Metal

## Input Protocol

Events are 16-byte binary structs sent over stdin (see `common/input_protocol.h`):

| Offset | Size | Field      | Description                           |
|--------|------|------------|---------------------------------------|
| 0      | 1    | type       | 1=mouse, 2=key, 3=focus, 4=resize     |
| 1      | 1    | action     | 1=press, 2=release, 3=move, 4=scroll  |
| 2      | 1    | button     | Mouse button (1=left, 2=right, 3=mid) |
| 3      | 1    | modifiers  | Bitmask: 1=shift, 2=ctrl, 4=alt, 8=meta |
| 4      | 2    | x          | Mouse X or key code                   |
| 6      | 2    | y          | Mouse Y                               |
| 8      | 2    | data1      | Scroll delta X (*100) or codepoint    |
| 10     | 2    | data2      | Scroll delta Y (*100)                 |
| 12     | 4    | timestamp  | Milliseconds since process start      |

## Future

See [TODO.txt](TODO.txt) for planned enhancements including:
- Bidirectional IPC (cursor, clipboard)
- Windows/Linux platform support
- VST3 plugin build

## License

MIT
