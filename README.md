# CMP Embed

Embeds a Compose Multiplatform (Compose Desktop) UI inside a JUCE application or native macOS application using IOSurface for zero-copy GPU rendering and binary IPC for input forwarding.

## Quick Start

```bash
# JUCE app
./scripts/build.sh && ./scripts/run_juce.sh

# Standalone native app
./scripts/build.sh && ./scripts/run_standalone.sh
```

**Prerequisites:**
- macOS 10.15+
- JDK 17+ (`brew install openjdk@17`)
- CMake 3.15+ (`brew install cmake`)
- Xcode Command Line Tools (`xcode-select --install`)

## Architecture

Two host applications are provided:

### JUCE Host

```
┌─────────────────────────────────────────────────────────┐
│  JUCE Standalone Application                            │
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

### Standalone Host (Native macOS)

```
┌─────────────────────────────────────────────────────────┐
│  Standalone (native macOS app)                          │
│  - Creates IOSurface (shared GPU memory)                │
│  - Displays it via CALayer                              │
│  - Captures input events → sends via stdin pipe         │
│  - Launches UI as child process                         │
│  - Handles window resize with delayed swap              │
└─────────────────┬───────────────────────────────────────┘
                  │ IOSurface ID (arg)    Input events (stdin)
                  │        ↓                     ↓
                  ▼────────────────────────────────────────
┌─────────────────────────────────────────────────────────┐
│  UI (Compose Desktop / Skia / Metal)                    │
│  - Renders directly to IOSurface-backed Metal texture   │
│  - Receives input events, injects into ComposeScene     │
│  - Handles resize: recreates resources for new surface  │
│  - Zero CPU pixel copies, invalidation-based rendering  │
└─────────────────────────────────────────────────────────┘
```

**Rendering:** The standalone app creates an IOSurface and passes its ID to the child process. The Compose UI uses Skia's Metal backend to render directly to the shared surface—no CPU copies involved. Rendering is invalidation-based: frames are only rendered when the scene changes.

**Input:** Mouse/keyboard events are captured in the standalone app and sent to the child via a 16-byte binary protocol over stdin. The UI deserializes and injects them into the Compose scene.

**Resize:** Window resizing uses delayed swap to avoid flicker. The standalone creates a new IOSurface at the target size, tells the child to render to it, waits one frame (~17ms) for the child to complete rendering, then swaps the displayed surface.

## Build

```bash
./scripts/build.sh
```

This builds:
1. **Native Metal renderer** (`libiosurface_renderer.dylib`)
2. **Compose UI app** (`cmpui.app` with bundled JRE)
3. **JUCE audio plugin host** (`CMP Embed Host.app` - fetches JUCE 8.0.4 via CMake)
4. **Standalone app** (`standalone.app`)

## Run

```bash
# JUCE host (recommended for plugin development)
./scripts/run_juce.sh

# Standalone host
./scripts/run_standalone.sh
```

Or after building:
```bash
# JUCE
./build/juce/CMPEmbedHost_artefacts/Standalone/"CMP Embed Host.app"/Contents/MacOS/"CMP Embed Host"

# Standalone
./build/standalone/standalone.app/Contents/MacOS/standalone
```

## Project Structure

```
common/                # Cross-platform shared code
  input_protocol.h     # Binary input event protocol (16 bytes/event)

juce/                  # JUCE audio plugin host
  PluginProcessor.cpp/h    # Passthrough audio processor
  PluginEditor.cpp/h       # Editor hosting IOSurfaceComponent
  IOSurfaceComponent.mm/h  # Displays IOSurface, captures input
  IOSurfaceProvider.mm/h   # Creates IOSurface, launches child
  InputSender.cpp/h        # Sends input events via stdin pipe
  CMakeLists.txt           # Fetches JUCE 8.0.4, builds plugin

standalone/            # Native macOS standalone application
  main.m               # Window, IOSurface display, input capture
  iosurface_provider.m # IOSurface creation and child process launch
  input_cocoa.h/.m     # Input event sender (macOS implementation)

ui/composeApp/         # Kotlin Multiplatform Compose application
  src/jvmMain/
    kotlin/cmpui/
      main.kt          # Entry point (standalone or embedded mode)
      App.kt           # Compose UI (vanilla demo app)
      input/           # Input event handling
        InputEvent.kt      # Event data classes
        InputReceiver.kt   # Reads binary events from stdin
        InputDispatcher.kt # Injects events into ComposeScene
      renderer/        # IOSurface rendering
        IOSurfaceRendererGPU.kt  # Zero-copy Metal path (default)
        IOSurfaceRendererCPU.kt  # CPU fallback (--disable-gpu)
    cpp/
      iosurface_renderer.m       # Native Metal bridge for Skia

scripts/
  build.sh             # Build everything (CMake orchestrated)
  run_juce.sh          # Build and run JUCE host
  run_standalone.sh    # Build and run standalone app
```

## Flags

The UI app supports:
- `--embed` - Run as embedded renderer (required when launched by standalone)
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
- HiDPI/Retina support
- Bidirectional IPC (cursor, clipboard)
- Windows/Linux platform support
- AU/VST3 plugin builds (currently Standalone only)

## License

MIT
