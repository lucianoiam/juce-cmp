// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#import <stdlib.h>
#import <unistd.h>
#import <mach/mach.h>
#import <servers/bootstrap.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

/**
 * Zero-copy Metal renderer for Compose IOSurface integration.
 *
 * This library provides the Metal device, command queue, and IOSurface-backed
 * texture that Skia can render to directly via DirectContext.makeMetal() and
 * BackendRenderTarget.makeMetal().
 *
 * Architecture:
 * - Kotlin creates a Metal context via createMetalContext()
 * - Kotlin creates an IOSurface-backed texture via createIOSurfaceTexture()
 * - Skia's DirectContext and BackendRenderTarget use these Metal resources
 * - Compose renders directly to the IOSurface - zero CPU pixel copies!
 */

// Metal context holding device and queue
typedef struct {
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
} MetalContext;

// Mach port channel for receiving IOSurface ports from parent
typedef struct {
    mach_port_t receivePort;  // Our receive port
    int connected;            // Whether channel is established
} MachChannel;

// Create Metal context for GPU operations
void* createMetalContext(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            return NULL;
        }

        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        if (commandQueue == nil) {
            return NULL;
        }

        MetalContext* ctx = (MetalContext*)malloc(sizeof(MetalContext));
        ctx->device = device;
        ctx->commandQueue = commandQueue;

        // Prevent ARC from releasing these
        CFRetain((__bridge CFTypeRef)device);
        CFRetain((__bridge CFTypeRef)commandQueue);

        return ctx;
    }
}

// Destroy Metal context
void destroyMetalContext(void* context) {
    if (context == NULL) return;

    @autoreleasepool {
        MetalContext* ctx = (MetalContext*)context;

        CFRelease((__bridge CFTypeRef)ctx->commandQueue);
        CFRelease((__bridge CFTypeRef)ctx->device);

        free(ctx);
    }
}

// Get the MTLDevice pointer for Skia's DirectContext.makeMetal()
void* getMetalDevice(void* context) {
    if (context == NULL) return NULL;
    MetalContext* ctx = (MetalContext*)context;
    return (__bridge void*)ctx->device;
}

// Get the MTLCommandQueue pointer for Skia's DirectContext.makeMetal()
void* getMetalQueue(void* context) {
    if (context == NULL) return NULL;
    MetalContext* ctx = (MetalContext*)context;
    return (__bridge void*)ctx->commandQueue;
}

// Flush pending GPU work (call after Skia renders)
void flushAndSync(void* context) {
    if (context == NULL) return;

    @autoreleasepool {
        MetalContext* ctx = (MetalContext*)context;

        // Create a command buffer just to synchronize
        id<MTLCommandBuffer> commandBuffer = [ctx->commandQueue commandBuffer];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }
}

// Read data from a socket file descriptor
// Returns number of bytes read, or -1 on error
ssize_t socketRead(int socketFD, void* buffer, size_t length) {
    return read(socketFD, buffer, length);
}

// Write data to a socket file descriptor
// Returns number of bytes written, or -1 on error
ssize_t socketWrite(int socketFD, const void* buffer, size_t length) {
    return write(socketFD, buffer, length);
}

// Connect to parent's Mach service and establish bidirectional channel
// Returns opaque channel handle or NULL on failure
void* machChannelConnect(const char* serviceName) {
    if (serviceName == NULL || serviceName[0] == '\0')
        return NULL;

    // Look up the parent's service port
    mach_port_t serverPort;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, (char*)serviceName, &serverPort);
    if (kr != KERN_SUCCESS)
        return NULL;

    // Create our receive port for incoming surface ports
    mach_port_t receivePort;
    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &receivePort);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), serverPort);
        return NULL;
    }

    // Add send right so parent can send to us
    kr = mach_port_insert_right(mach_task_self(), receivePort, receivePort, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), receivePort);
        mach_port_deallocate(mach_task_self(), serverPort);
        return NULL;
    }

    // Send our receive port to parent (as a send right)
    struct {
        mach_msg_header_t header;
        mach_msg_body_t body;
        mach_msg_port_descriptor_t portDescriptor;
    } connectMsg = {};

    connectMsg.header.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    connectMsg.header.msgh_size = sizeof(connectMsg);
    connectMsg.header.msgh_remote_port = serverPort;
    connectMsg.header.msgh_local_port = MACH_PORT_NULL;
    connectMsg.header.msgh_id = 1;

    connectMsg.body.msgh_descriptor_count = 1;

    connectMsg.portDescriptor.name = receivePort;
    connectMsg.portDescriptor.disposition = MACH_MSG_TYPE_COPY_SEND;  // Send a send right
    connectMsg.portDescriptor.type = MACH_MSG_PORT_DESCRIPTOR;

    kr = mach_msg(
        &connectMsg.header,
        MACH_SEND_MSG,
        sizeof(connectMsg),
        0,
        MACH_PORT_NULL,
        MACH_MSG_TIMEOUT_NONE,
        MACH_PORT_NULL
    );

    mach_port_deallocate(mach_task_self(), serverPort);  // Done with bootstrap port

    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), receivePort);
        return NULL;
    }

    MachChannel* channel = (MachChannel*)malloc(sizeof(MachChannel));
    channel->receivePort = receivePort;
    channel->connected = 1;

    return channel;
}

// Receive an IOSurface port from parent (blocking)
// Returns IOSurfaceRef (caller must CFRelease) or NULL on failure/disconnect
IOSurfaceRef machChannelReceiveSurface(void* channelPtr) {
    if (channelPtr == NULL) return NULL;

    MachChannel* channel = (MachChannel*)channelPtr;
    if (!channel->connected) return NULL;

    // Receive message with port descriptor
    struct {
        mach_msg_header_t header;
        mach_msg_body_t body;
        mach_msg_port_descriptor_t portDescriptor;
        mach_msg_trailer_t trailer;
    } msg = {};

    kern_return_t kr = mach_msg(
        &msg.header,
        MACH_RCV_MSG,
        0,
        sizeof(msg),
        channel->receivePort,
        MACH_MSG_TIMEOUT_NONE,
        MACH_PORT_NULL
    );

    if (kr != KERN_SUCCESS)
        return NULL;

    mach_port_t surfacePort = msg.portDescriptor.name;

    // Convert Mach port to IOSurface
    IOSurfaceRef surface = IOSurfaceLookupFromMachPort(surfacePort);
    mach_port_deallocate(mach_task_self(), surfacePort);

    if (surface == NULL)
        return NULL;

    return surface;  // Caller must CFRelease
}

// Close the Mach channel
void machChannelClose(void* channelPtr) {
    if (channelPtr == NULL) return;

    MachChannel* channel = (MachChannel*)channelPtr;
    if (channel->receivePort != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), channel->receivePort);
    }
    free(channel);
}

// Create a Metal texture from an IOSurface
// Returns MTLTexture pointer (caller must release via releaseIOSurfaceTexture)
void* createTextureFromIOSurface(void* context, IOSurfaceRef surface, int* outWidth, int* outHeight) {
    if (context == NULL || surface == NULL) return NULL;

    @autoreleasepool {
        MetalContext* ctx = (MetalContext*)context;

        size_t width = IOSurfaceGetWidth(surface);
        size_t height = IOSurfaceGetHeight(surface);

        if (outWidth) *outWidth = (int)width;
        if (outHeight) *outHeight = (int)height;

        MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.width = width;
        textureDescriptor.height = height;
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        textureDescriptor.storageMode = MTLStorageModeShared;

        id<MTLTexture> texture = [ctx->device newTextureWithDescriptor:textureDescriptor
                                                             iosurface:surface
                                                                 plane:0];

        if (texture == nil) {
            return NULL;
        }

        CFRetain((__bridge CFTypeRef)texture);
        return (__bridge void*)texture;
    }
}

// Release an IOSurface-backed texture
void releaseIOSurfaceTexture(void* texturePtr) {
    if (texturePtr == NULL) return;

    @autoreleasepool {
        id<MTLTexture> texture = (__bridge id<MTLTexture>)texturePtr;
        CFRelease((__bridge CFTypeRef)texture);
    }
}
