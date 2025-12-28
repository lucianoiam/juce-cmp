// IOSurface IPC - Cross-process sharing via parent-child
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>

static IOSurfaceRef g_surface = NULL;
static NSTask *g_child_task = nil;

// Host (parent) API
void iosurface_ipc_create_surface(int width, int height) {
    NSDictionary *props = @{
        (id)kIOSurfaceWidth: @(width),
        (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        (id)kIOSurfaceIsGlobal: @YES  // Deprecated but may still work
    };
    g_surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    NSLog(@"IPC: Created GLOBAL surface %p, ID=%u", g_surface, IOSurfaceGetID(g_surface));
}

IOSurfaceRef iosurface_ipc_get_surface(void) {
    return g_surface;
}

uint32_t iosurface_ipc_get_surface_id(void) {
    return g_surface ? IOSurfaceGetID(g_surface) : 0;
}

void iosurface_ipc_launch_child(const char *executable, const char *const *args, const char *workingDir) {
    if (!g_surface) {
        NSLog(@"IPC: No surface created, cannot launch child");
        return;
    }
    
    g_child_task = [[NSTask alloc] init];
    g_child_task.executableURL = [NSURL fileURLWithPath:@(executable)];
    
    // Build arguments array
    NSMutableArray *argsArray = [NSMutableArray array];
    if (args) {
        for (int i = 0; args[i] != NULL; i++) {
            [argsArray addObject:@(args[i])];
        }
    }
    // Pass surface ID as argument
    [argsArray addObject:[NSString stringWithFormat:@"--iosurface-id=%u", IOSurfaceGetID(g_surface)]];
    g_child_task.arguments = argsArray;
    
    if (workingDir) {
        g_child_task.currentDirectoryURL = [NSURL fileURLWithPath:@(workingDir)];
    }
    
    NSError *error = nil;
    [g_child_task launchAndReturnError:&error];
    if (error) {
        NSLog(@"IPC: Failed to launch child: %@", error);
    } else {
        NSLog(@"IPC: Launched child with IOSurface ID %u", IOSurfaceGetID(g_surface));
    }
}

void iosurface_ipc_stop(void) {
    if (g_child_task && g_child_task.isRunning) {
        [g_child_task terminate];
    }
    g_child_task = nil;
    if (g_surface) {
        CFRelease(g_surface);
        g_surface = NULL;
    }
}

// Client (child) API
IOSurfaceRef iosurface_ipc_lookup(uint32_t surfaceID) {
    IOSurfaceRef surface = IOSurfaceLookup(surfaceID);
    NSLog(@"IPC: Lookup ID %u -> %p", surfaceID, surface);
    return surface;
}
