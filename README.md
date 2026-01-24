# juce-cmp

A JUCE module for embedding Compose Multiplatform UI in audio plugins.

https://github.com/user-attachments/assets/1a56b7d8-f1eb-4f5d-bcfa-0890e39a7270

**Note:** This project was entirely vibe-coded by [Claude](https://claude.ai) under human supervision. Final code review pending.

## Status

Alpha software.

- macOS implementation complete
- Bidirectional ValueTree message passing
- Bidirectional MIDI message passing

## Example Project

[Sfarzo](https://github.com/lucianoiam/sfarzo) - An SFZ sampler plugin built with juce-cmp (also vibe-coded with Claude).

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

```
┌─────────────────────────────────────────────────────────┐
│  JUCE Plugin (uses juce_cmp module)                     │
│  - ComposeComponent creates shared IOSurface            │
│  - SurfaceView (NSView/CALayer) displays surface        │
│  - Transparent JUCE component captures input events     │
│  - Launches Compose UI as child process                 │
└─────────────────┬───────────────────────────────────────┘
                  │ Mach port (IOSurface sharing)
                  │ Unix socket (input, messages)
                  ▼
┌─────────────────────────────────────────────────────────┐
│  Child Process (Compose Desktop / Skia / Metal)         │
│  - Renders to shared IOSurface via Metal backend        │
│  - Receives input events, injects into ComposeScene     │
│  - Sends messages back to host via socket               │
│  - Zero CPU pixel copies                                │
└─────────────────────────────────────────────────────────┘
```

**Rendering:** The plugin creates an IOSurface and sends it to the child via Mach port. The Compose UI uses Skia's Metal backend to render directly to the shared surface. The host's CALayer displays the surface content.

**Input:** Mouse/keyboard events are captured by the JUCE component and sent to the child via a 16-byte binary protocol over a Unix socket. The child deserializes and injects them into the Compose scene.

**IPC:** A single multiplexed Unix socket handles all communication: input events (host→child), resize notifications (host→child), and ValueTree messages (bidirectional). IOSurface sharing uses a separate Mach port channel.

## Project Structure

### JUCE Module

```
juce_cmp/                     # JUCE module (include in your plugin)
  juce_cmp.h                  # Module header with metadata
  juce_cmp.cpp                # Unity build (C++ implementations)
  juce_cmp.mm                 # Unity build (Objective-C++ implementations)
  juce_cmp/                   # Implementation files
    ComposeComponent.h/cpp    # JUCE Component displaying Compose UI
    ComposeProvider.h/cpp     # Orchestrates embedding lifecycle
    ChildProcess.h/cpp        # Child process lifecycle (posix_spawn)
    Surface.h/mm              # IOSurface management (macOS)
    SurfaceView.h/mm          # NSView/CALayer for display (macOS)
    MachPort.h/mm             # Mach port IPC for IOSurface sharing
    Ipc.h/cpp                 # Bidirectional socket IPC
    input_event.h             # 16-byte binary input protocol
    ipc_protocol.h            # IPC protocol constants
    ui_helpers.h              # UI utilities
```

**Usage in your plugin:**

```cpp
#include <juce_cmp/juce_cmp.h>

class MyEditor : public juce::AudioProcessorEditor {
    juce_cmp::ComposeComponent composeComponent;

    MyEditor(AudioProcessor& p) : AudioProcessorEditor(p) {
        addAndMakeVisible(composeComponent);

        // Handle ValueTree messages from UI
        composeComponent.onEvent([&](const juce::ValueTree& tree) {
            if (tree.getType() == juce::Identifier("param")) {
                auto paramId = (int)tree.getProperty("id");
                auto value = (float)(double)tree.getProperty("value");
                // Update your processor parameters
            }
        });

        // Handle MIDI from UI (e.g., soft keyboard)
        composeComponent.onMidi([&](const juce::MidiMessage& message) {
            // Forward to your processor's MIDI buffer
        });

        // Send ValueTree message to UI
        juce::ValueTree tree("param");
        tree.setProperty("id", 0, nullptr);
        tree.setProperty("value", 0.5, nullptr);
        composeComponent.sendEvent(tree);

        // Send MIDI to UI
        composeComponent.sendMidi(juce::MidiMessage::noteOn(1, 60, 0.8f));
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
        Library.kt            # Library initialization
        ipc/
          Ipc.kt              # Socket IPC channel
          JuceValueTree.kt    # JUCE-compatible ValueTree
        input/
          InputDispatcher.kt  # Injects events into ComposeScene
          InputMapper.kt      # Maps key codes to Compose
          InputEvent.kt       # Event data classes
        renderer/
          IOSurfaceRenderer.kt # Metal rendering to IOSurface
      cpp/
        iosurface_renderer.m  # Native Metal/Mach bridge
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
import juce_cmp.Library
import juce_cmp.ipc.JuceValueTree
import javax.sound.midi.ShortMessage

fun main(args: Array<String>) {
    Library.init(args)  // MUST be first - parses args, sets up IPC

    if (Library.hasHost) {
        // Embedded mode - render to host's shared surface
        Library.host(
            onJuceEvent = { tree -> /* handle ValueTree from host */ },
            onMidiEvent = { message -> /* handle MIDI from host */ }
        ) {
            MyApp()
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

// Send ValueTree to host
Library.sendJuceEvent(JuceValueTree("param").apply {
    this["id"] = 0
    this["value"] = 0.5
})

// Send MIDI to host
Library.sendMidiEvent(ShortMessage(ShortMessage.NOTE_ON, 0, 60, 127))
```

### Demo Application

```
demo/                         # Example plugin using juce_cmp
  PluginProcessor.h/cpp       # Simple synth processor
  PluginEditor.h/cpp          # Editor using ComposeComponent
  ui/                         # Demo Compose UI application
  scripts/                    # Build and run scripts
  CMakeLists.txt              # Builds demo plugin
```

## IPC Protocol

### Socket Messages

All messages have a 1-byte type prefix:

| Type | Value | Direction | Content |
|------|-------|-----------|---------|
| INPUT | 0x00 | Host→Child | 16-byte input event |
| CMP | 0x01 | Child→Host | 1-byte subtype (SURFACE_READY=0) |
| MIDI | 0x02 | Bidirectional | 1-byte size + raw MIDI bytes |
| JUCE | 0x03 | Bidirectional | 4-byte size + ValueTree data |

### Input Event (16 bytes)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | type | 0=mouse, 1=key, 2=focus, 3=resize |
| 1 | 1 | action | 0=press, 1=release, 2=move, 3=scroll |
| 2 | 1 | button | 1=left, 2=right, 3=middle |
| 3 | 1 | modifiers | 1=shift, 2=ctrl, 4=alt, 8=meta |
| 4 | 2 | x | Mouse X, key code, or width |
| 6 | 2 | y | Mouse Y or height |
| 8 | 2 | data1 | Scroll delta X (×10000) or codepoint low |
| 10 | 2 | data2 | Scroll delta Y (×10000) or codepoint high |
| 12 | 4 | timestamp | Milliseconds since process start |

### MIDI Messages

Raw MIDI bytes prefixed by a 1-byte size. Supports standard MIDI messages (note on/off, CC, etc.) and SysEx. Uses `juce::MidiMessage` on the C++ side and `javax.sound.midi` classes on the Kotlin side.

### ValueTree Messages

Binary format compatible with JUCE's `ValueTree::writeToStream()`. The library passes ValueTree blobs opaquely—apps define their own schema.

## Command-Line Flags

The UI app accepts these flags when launched by the plugin:
- `--socket-fd=<fd>` - Unix socket file descriptor for IPC
- `--mach-service=<name>` - Mach service name for IOSurface sharing
- `--scale=<factor>` - Display scale factor (e.g., 2.0 for Retina)

## Platform Support

**Current:** macOS 10.15+ (IOSurface + Metal)

**Planned:**
- Windows (DXGI shared textures)
- Linux (shared memory or Vulkan external memory)

## License

MIT
