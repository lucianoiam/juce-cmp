juce-cmp - Proposed Enhancements
==================================

INPUT ENHANCEMENTS
------------------
[ ] Mouse cursor changes (pointer, hand, text) - Compose requests cursor styles, forward back to host
[ ] Drag and drop support
[ ] Text input / IME for international keyboards
[ ] Touch/trackpad gestures (pinch, rotate)

RENDERING
---------
[x] Window resize handling - recreate IOSurface at new size
[x] HiDPI/Retina support - pass scale factor, render at 2x

ARCHITECTURE
------------
[x] Bidirectional IPC - UI sends messages back (setParameter working)
[ ] Shared memory ring buffer instead of pipe for lower latency
[ ] Extract embedding as a library/framework others can use

PLATFORM EXPANSION
------------------
[ ] Windows standalone (Win32 + shared texture via D3D/Vulkan)
[ ] Linux/X11 or Wayland support
[x] JUCE plugin wrapper for audio apps (AU plugin builds)

DEVELOPER EXPERIENCE
--------------------
[ ] Hot reload in embedded mode (currently only standalone Compose UI has it)
[ ] Debug overlay showing frame times
[ ] Example with more complex UI (lists, text fields, navigation)

PRODUCTION READINESS
--------------------
[ ] Error recovery if child crashes
[ ] Graceful shutdown handshake
[ ] Security sandbox considerations
