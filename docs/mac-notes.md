# macOS Implementation Notes

## IOSurface Sharing

IOSurface is used for zero-copy GPU texture sharing between the host (JUCE plugin) and child (Compose UI) processes.

### Current Implementation

Uses `kIOSurfaceIsGlobal` flag with `IOSurfaceLookup()`:

```objc
// Host creates surface with global flag
NSDictionary* props = @{
    (id)kIOSurfaceWidth: @(width),
    (id)kIOSurfaceHeight: @(height),
    (id)kIOSurfaceBytesPerElement: @4,
    (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
    (id)kIOSurfaceIsGlobal: @YES  // Deprecated but required
};
IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);

// Host sends 4-byte surface ID via socket
uint32_t surfaceID = IOSurfaceGetID(surface);
write(socketFD, &surfaceID, sizeof(surfaceID));

// Child looks up by ID
IOSurfaceRef surface = IOSurfaceLookup(surfaceID);
```

**Note**: `kIOSurfaceIsGlobal` is deprecated but still functional. The deprecation warning is suppressed with `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`.

### Failed Mach Port Approach

Attempted to eliminate the deprecated flag by passing IOSurface Mach ports via `SCM_RIGHTS`:

1. **Goal**: Use `IOSurfaceCreateMachPort()` to get a Mach port, convert to FD, pass via `SCM_RIGHTS`, convert back to Mach port, use `IOSurfaceLookupFromMachPort()`.

2. **Implementation**:
   ```cpp
   // Host side
   mach_port_t machPort = IOSurfaceCreateMachPort(surface);
   int fd = fileport_makefd(machPort);  // Private API
   // Send fd via SCM_RIGHTS using sendmsg()

   // Child side
   // Receive fd via recvmsg()
   mach_port_t machPort = fileport_makeport(fd);  // Private API
   IOSurfaceRef surface = IOSurfaceLookupFromMachPort(machPort);
   ```

3. **Result**: `fileport_makefd()` returned `-1` despite valid Mach port.

4. **Root cause**: `fileport_makefd/makeport` are designed for wrapping Unix file descriptors as Mach ports (for XPC), not the other way around. SCM_RIGHTS can only pass Unix file descriptors, not Mach ports directly.

### Proper Alternatives (Future Work)

To properly share IOSurfaces without the deprecated global flag:

1. **XPC** (Recommended by Apple)
   - Use `IOSurfaceCreateXPCObject()` to wrap surface
   - Requires XPC service with launchd plist
   - Significant architecture change

2. **Direct Mach IPC**
   - Use `mach_msg()` to send port rights directly
   - Requires bootstrap server registration
   - Complex low-level API

3. **MIG (Mach Interface Generator)**
   - Define custom Mach interface
   - Auto-generates client/server stubs
   - Overkill for this use case

For now, the global ID approach works reliably and the deprecation is cosmetic - Apple hasn't removed the functionality.

## IPC Channel

Uses `socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)` for bidirectional communication:

- Single socket pair replaces previous stdin/stdout pipes
- Bidirectional: host and child can send/receive on same FD
- Simpler than managing two separate pipes
- Child receives socket FD via `--socket-fd=N` argument

## References

- [IOSurface Programming Guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/IOSurface/)
- [Cross-process Rendering (Russ Bishop)](http://www.russbishop.net/cross-process-rendering)
- [Mach Ports (fdiv.net)](https://fdiv.net/category/apple/mach-ports)
