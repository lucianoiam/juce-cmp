# KMP Embed

Embeds a Kotlin Multiplatform (Compose Desktop) UI inside a native macOS application using IOSurface for zero-copy GPU rendering.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Host (native macOS app)                                │
│  - Creates IOSurface (shared GPU memory)                │
│  - Displays it via CALayer                              │
│  - Launches UI as child process                         │
└─────────────────┬───────────────────────────────────────┘
                  │ IOSurface ID
                  ▼
┌─────────────────────────────────────────────────────────┐
│  UI (Compose Desktop / Skia / Metal)                    │
│  - Renders directly to IOSurface-backed Metal texture   │
│  - Zero CPU pixel copies                                │
└─────────────────────────────────────────────────────────┘
```

The host creates an IOSurface and passes its ID to the child process. The Compose UI uses Skia's Metal backend to render directly to the shared surface—no CPU copies involved.

## Requirements

- macOS 10.15+
- JDK 17+ (for building; the app bundles its own JRE)
- CMake 3.10+
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
./scripts/build.sh
```

This builds:
1. **Native Metal renderer** (`libiosurface_renderer.dylib`)
2. **Compose UI app** (`kmpui.app` with bundled JRE)
3. **Host app** (`host.app`)

## Run

```bash
./scripts/run.sh
```

Or after building:
```bash
./host/build/host.app/Contents/MacOS/host
```

## Project Structure

```
host/                  # Native macOS host application
  main.m               # Window, IOSurface display, child process launch
  iosurface_provider.m # IOSurface creation and IPC

ui/composeApp/         # Kotlin Multiplatform Compose application
  src/jvmMain/
    kotlin/kmpui/
      main.kt          # Entry point (standalone or embedded mode)
      App.kt           # Compose UI
      renderer/        # IOSurface rendering
        IOSurfaceRendererGPU.kt  # Zero-copy Metal path (default)
        IOSurfaceRendererCPU.kt  # CPU fallback (--disable-gpu)
    cpp/
      iosurface_renderer.m       # Native Metal bridge for Skia

scripts/
  build.sh             # Build everything
  run.sh               # Build and run
```

## Flags

The UI app supports:
- `--embed` - Run as embedded renderer (required when launched by host)
- `--iosurface-id=<id>` - IOSurface to render to
- `--disable-gpu` - Use CPU software rendering instead of Metal

## License

MIT
