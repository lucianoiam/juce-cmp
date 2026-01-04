# juce-cmp

A JUCE module for embedding Compose Multiplatform UI in audio plugins.

**Note:** this project was vibe-coded entirely by Claude Opus 4.5. Human supervision pending—coming soon in v1.0.0.

## Quick Start

```bash
# Build everything
./demo/scripts/build.sh

# Run demo standalone
./demo/scripts/run_standalone.sh

# Install demo AU plugin
./demo/scripts/install_plugin.sh
```

**Prerequisites:**
- macOS 10.15+
- JDK 21+ (`brew install openjdk@21`)
- CMake 3.15+ (`brew install cmake`)
- Xcode Command Line Tools (`xcode-select --install`)

## Architecture

The module uses IOSurface for zero-copy GPU rendering, enabling efficient integration between JUCE and Compose Multiplatform.

```
┌─────────────────────────────────────────────────────────┐
│  JUCE Plugin (uses juce_cmp module)                     │
│  - IOSurfaceComponent creates shared GPU surface        │
│  - SurfaceView (NSView) displays via CALayer            │
│  - CVDisplayLink for vsync-synchronized refresh         │
│  - Transparent JUCE component captures input events     │
│  - Launches Compose UI as child process                 │
└─────────────────┬───────────────────────────────────────┘
                  │ IOSurface ID (arg)    Input events (stdin)
                  │ UI messages (FIFO) ◄──┘
                  ▼
┌─────────────────────────────────────────────────────────┐
│  UI (Compose Desktop / Skia / Metal)                    │
│  - Uses juce_cmp_ui library for bridge/renderer code   │
│  - Renders directly to IOSurface-backed Metal texture   │
│  - Receives input events, injects into ComposeScene     │
│  - Sends parameter changes back to host via IPC         │
│  - Zero CPU pixel copies, invalidation-based rendering  │
└─────────────────────────────────────────────────────────┘
```

**Rendering:** The plugin creates an IOSurface and passes its ID to the child process. The Compose UI uses Skia's Metal backend to render directly to the shared surface—no CPU copies involved. Rendering is invalidation-based: frames are only rendered when the scene changes.

**Input:** Mouse/keyboard events are captured by the JUCE component and sent to the child via a 16-byte binary protocol over stdin. The UI deserializes and injects them into the Compose scene.

**Bidirectional IPC:** The UI can send messages back to the host (e.g., parameter changes) via a named pipe (FIFO).

## Project Structure

### JUCE Module

```
juce_cmp/                     # JUCE module (include in your plugin)
  juce_cmp.h                  # Module header with metadata
  juce_cmp.cpp                # Unity build (C++ implementations)
  juce_cmp.mm                 # Unity build (Objective-C++ implementations)
  juce_cmp/                   # Implementation files
    IOSurfaceComponent.h/mm   # JUCE Component displaying IOSurface
    IOSurfaceProvider.h/mm    # Creates IOSurface, manages child process
    InputSender.h/cpp          # Sends input events to child via stdin
    UIReceiver.h               # Receives messages from UI via FIFO
    input_protocol.h           # Binary input event protocol (16 bytes)
    ui_protocol.h              # UI→Host message protocol
    LoadingPreview.h           # Loading placeholder image
```

**Usage in your plugin:**

```cpp
#include <juce_cmp/juce_cmp.h>

class MyEditor : public juce::AudioProcessorEditor {
    juce_cmp::IOSurfaceComponent surfaceComponent;

    MyEditor(AudioProcessor& p) : AudioProcessorEditor(p) {
        addAndMakeVisible(surfaceComponent);

        // Handle parameter changes from UI
        surfaceComponent.onSetParameter([&](uint32_t paramId, float value) {
            // Update your processor parameters
        });
    }
};
```

Add to your CMakeLists.txt:
```cmake
juce_add_module(path/to/juce_cmp)

target_link_libraries(YourPlugin PRIVATE juce_cmp ...)
```

### Compose Multiplatform Library

```
juce_cmp_ui/                  # Kotlin Multiplatform library
  lib/
    build.gradle.kts          # Library build config
    src/jvmMain/
      kotlin/juce_cmp/
        UISender.kt            # Sends messages to JUCE host
        input/
          InputReceiver.kt     # Reads binary events from stdin
          InputDispatcher.kt   # Injects events into ComposeScene
          InputMapper.kt       # Maps protocol events to Compose
          InputEvent.kt        # Event data classes
        renderer/
          IOSurfaceRenderer.kt      # Renderer abstraction
          IOSurfaceRendererGPU.kt   # Zero-copy Metal rendering
          IOSurfaceRendererCPU.kt   # Software fallback
          IOSurfaceLib.kt           # JNA bindings for IOSurface
      cpp/
        iosurface_renderer.m   # Native Metal bridge for Skia
      resources/
        libiosurface_renderer.dylib  # Built native library
```

**Usage in your Compose app:**

```kotlin
// settings.gradle.kts
includeBuild("path/to/juce_cmp_ui")

// build.gradle.kts
dependencies {
    implementation("com.github.juce-cmp:lib")
}

// main.kt
import juce_cmp.UISender
import juce_cmp.renderer.runIOSurfaceRenderer

fun main(args: Array<String>) {
    if (args.contains("--embed")) {
        UISender.initialize(args)
        val surfaceID = args.first { it.startsWith("--iosurface-id=") }
            .substringAfter("=").toInt()
        val scale = args.first { it.startsWith("--scale=") }
            .substringAfter("=").toFloat()

        runIOSurfaceRenderer(surfaceID, scale) {
            MyApp()  // Your @Composable UI
        }
    } else {
        // Standalone window mode
        application {
            Window(onCloseRequest = ::exitApplication) {
                MyApp()
            }
        }
    }
}
```

### Demo Application

```
demo/                         # Example plugin using juce_cmp
  PluginProcessor.h/cpp       # Simple synth processor
  PluginEditor.h/cpp          # Editor using IOSurfaceComponent
  ui/                         # Demo Compose UI application
    composeApp/
      src/jvmMain/kotlin/juce_cmp/demo/
        main.kt               # Entry point
        App.kt                # Demo Compose UI
        Knob.kt               # Example rotary knob widget
  scripts/                    # Build and run scripts
    build.sh                  # Build everything
    run_standalone.sh         # Run standalone app
    install_plugin.sh         # Install AU plugin
    run_only_ui_with_hot_reload.sh  # Hot reload for UI development
  CMakeLists.txt              # Builds demo plugin
```

## Build

```bash
./demo/scripts/build.sh
```

This builds:
1. **Native Metal renderer** (`libiosurface_renderer.dylib`)
2. **juce_cmp_ui library** (Compose Multiplatform library)
3. **Demo Compose UI** (`cmpui.app` with bundled JRE)
4. **Demo AU plugin** (`juce-cmp-demo.component`)
5. **Demo Standalone** (`juce-cmp-demo.app`)

## Install Demo Plugin

```bash
./demo/scripts/install_plugin.sh
```

Copies demo AU to `~/Library/Audio/Plug-Ins/Components/` and resets the audio component cache.

To validate: `auval -v aumu CMPh CMPe`

## Command-Line Flags

The UI app supports these flags when launched by the plugin:
- `--embed` - Run as embedded renderer
- `--iosurface-id=<id>` - IOSurface ID to render to
- `--scale=<factor>` - Backing scale factor (e.g., 2.0 for Retina)
- `--input-pipe=<fd>` - File descriptor for input events
- `--ipc-fifo=<path>` - Named pipe for UI→Host messages
- `--disable-gpu` - Use CPU software rendering instead of Metal

## Input Protocol

Events are 16-byte binary structs sent over stdin (see `juce_cmp/juce_cmp/input_protocol.h`):

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

## UI Protocol

Messages sent from UI to host via FIFO (see `juce_cmp/juce_cmp/ui_protocol.h`):

**Header (8 bytes):**
- `opcode` (uint32_t) - Message type
- `payloadSize` (uint32_t) - Payload size in bytes

**Opcodes:**
- `0x01` - `UI_OPCODE_SET_PARAM` - Set parameter value
  - Payload: `paramId` (uint32_t), `value` (float)

## Platform Support

**Current:** macOS 10.15+ (IOSurface + Metal)

**Planned:**
- Windows (DXGI shared textures)
- Linux (shared memory or Vulkan external memory)

See [TODO.md](TODO.md) for roadmap.

## License

MIT
