# macOS Implementation Notes

## IOSurface Sharing

IOSurface is used for zero-copy GPU texture sharing between the host (JUCE plugin) and child (Compose UI) processes.

### Current Implementation

Uses Mach port IPC via `bootstrap_check_in()` and `mach_msg()`:

```objc
// Host: Create surface (no kIOSurfaceIsGlobal!)
NSDictionary* props = @{
    (id)kIOSurfaceWidth: @(width),
    (id)kIOSurfaceHeight: @(height),
    (id)kIOSurfaceBytesPerElement: @4,
    (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA')
};
IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);

// Host: Create Mach port and send via bootstrap channel
mach_port_t surfacePort = IOSurfaceCreateMachPort(surface);
// ... send via mach_msg() to child's receive port

// Child: Receive Mach port and look up IOSurface
mach_port_t surfacePort = /* received via mach_msg() */;
IOSurfaceRef surface = IOSurfaceLookupFromMachPort(surfacePort);
```

**Key components:**
- `MachPort` class (C++): Handles bootstrap registration and port sending
- Client-side: Kotlin/JNI receives IOSurface ports via `Library.init()`

**Flow:**
1. Host registers service via `bootstrap_check_in()` with unique name
2. Host passes service name to child via `--mach-service=<name>`
3. Child looks up service via `bootstrap_look_up()`
4. Child creates receive port and sends it to host
5. Host receives child's port, establishing bidirectional channel
6. Host sends IOSurface Mach ports for initial surface and resizes
7. Child receives ports and looks up IOSurfaces

**Advantages:**
- No deprecated APIs (`kIOSurfaceIsGlobal` not used)
- No special entitlements required
- Works in sandboxed environments
- Bidirectional: host pushes new surfaces on resize

### Failed Alternatives

Several approaches were investigated before the Mach IPC solution:

#### 1. SCM_RIGHTS with fileport (Failed)

**Goal**: Convert Mach port to FD, pass via `SCM_RIGHTS`, convert back.

```cpp
// Host side
mach_port_t machPort = IOSurfaceCreateMachPort(surface);
int fd = fileport_makefd(machPort);  // Private API
// Send fd via SCM_RIGHTS using sendmsg()

// Child side
mach_port_t machPort = fileport_makeport(fd);  // Private API
IOSurfaceRef surface = IOSurfaceLookupFromMachPort(machPort);
```

**Result**: `fileport_makefd()` returned `-1`.

**Root cause**: `fileport_makefd/makeport` wrap Unix FDs as Mach ports (for XPC), not vice versa. SCM_RIGHTS only passes Unix file descriptors.

#### 2. task_set_special_port / task_get_special_port (Failed)

**Goal**: Parent sets IOSurface Mach port in child's task, child retrieves it.

```cpp
// Host side (after fork)
mach_port_t childTask;
task_for_pid(mach_task_self(), childPid, &childTask);
mach_port_t surfacePort = IOSurfaceCreateMachPort(surface);
task_set_special_port(childTask, TASK_BOOTSTRAP_PORT, surfacePort);

// Child side
mach_port_t surfacePort;
task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &surfacePort);
IOSurfaceRef surface = IOSurfaceLookupFromMachPort(surfacePort);
```

**Result**: `task_for_pid()` failed with `KERN_FAILURE` (kr=5).

**Root cause**: `task_for_pid()` requires the `com.apple.security.cs.debugger` entitlement on modern macOS. Despite the name, this entitlement controls access to another process's task port (used by debuggers but also needed for Mach port manipulation). Even parent→child access after fork requires this entitlement, which must be code-signed by Apple or with SIP disabled.

#### 3. XPC (Considered - overkill)

- Use `IOSurfaceCreateXPCObject()` to wrap surface
- Requires XPC service with launchd plist (for non-anonymous XPC)
- Anonymous XPC requires existing connection to share endpoint
- Significant architecture change for cross-platform project

#### 4. kIOSurfaceIsGlobal (Deprecated)

The original approach that was replaced:

```objc
// Host creates surface with global flag (DEPRECATED)
NSDictionary* props = @{
    ...
    (id)kIOSurfaceIsGlobal: @YES  // Deprecated!
};
IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);

// Host sends 4-byte surface ID via socket
uint32_t surfaceID = IOSurfaceGetID(surface);
write(socketFD, &surfaceID, sizeof(surfaceID));

// Child looks up by ID
IOSurfaceRef surface = IOSurfaceLookup(surfaceID);
```

This approach worked but used a deprecated API. The Mach IPC solution avoids this.

## Resize Flow

Resize is synchronized to avoid jitter from displaying old surface in new frame size.

**Host side (C++):**
1. `ComposeComponent::resized()` calls `provider_.resize(width, height, viewX, viewY)`
2. `ComposeProvider::resize()`:
   - Creates new IOSurface at new size
   - Stores pending view bounds (does NOT apply them yet)
   - Sends resize event to child via socket
   - Sends new IOSurface via Mach port
3. When `SURFACE_READY` received from child:
   - Applies pending view bounds (`view_.setFrame()`)
   - Sets pending surface for swap (`view_.setPendingSurface()`)
4. `displayLinkFired` (every vsync):
   - If pending surface exists, swaps it in
   - Always calls `setNeedsDisplay` to refresh IOSurface content

**Child side (Kotlin):**
1. Receives new IOSurface via Mach port (blocking receive thread)
2. Receives resize event via socket
3. Render loop detects `newSurface != null`:
   - Swaps in new surface resources
   - Updates scene size
   - Sets `surfaceChanged = true`
4. After render: if `surfaceChanged`, sends `SURFACE_READY` via socket

**Key points:**
- View bounds and surface swap happen atomically when SURFACE_READY arrives
- Old surface stays displayed at old size until new one is ready
- IOSurface content refreshes every vsync (child renders continuously)

## IPC Channel

Uses `socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)` for bidirectional communication:

- Single socket pair for input events, resize notifications, ValueTree messages
- Bidirectional: host and child can send/receive on same FD
- Child receives socket FD via `--socket-fd=N` argument
- IOSurface sharing uses separate Mach port channel (not socket)

## References

- [IOSurface Programming Guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/IOSurface/)
- [Cross-process Rendering (Russ Bishop)](http://www.russbishop.net/cross-process-rendering)
- [Mach Ports (fdiv.net)](https://fdiv.net/category/apple/mach-ports)
- [Example of IOSurfaceCreateMachPort/IOSurfaceLookupFromMachPort](https://fdiv.net/2011/01/27/example-iosurfacecreatemachport-and-iosurfacelookupfrommachport)
