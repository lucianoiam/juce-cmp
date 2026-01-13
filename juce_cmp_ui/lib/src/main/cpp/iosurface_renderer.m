// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
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

// Create an IOSurface-backed Metal texture for Skia's BackendRenderTarget.makeMetal()
// Returns the MTLTexture pointer that can be used with BackendRenderTarget.makeMetal()
void* createIOSurfaceTexture(void* context, int surfaceID, int* outWidth, int* outHeight) {
    if (context == NULL) return NULL;

    @autoreleasepool {
        MetalContext* ctx = (MetalContext*)context;

        // Lookup IOSurface by global ID
        IOSurfaceRef surface = IOSurfaceLookup((IOSurfaceID)surfaceID);
        if (surface == NULL) {
            return NULL;
        }

        size_t width = IOSurfaceGetWidth(surface);
        size_t height = IOSurfaceGetHeight(surface);

        if (outWidth) *outWidth = (int)width;
        if (outHeight) *outHeight = (int)height;

        // Create texture descriptor for IOSurface-backed texture
        MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.width = width;
        textureDescriptor.height = height;
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        textureDescriptor.storageMode = MTLStorageModeShared;

        // Create texture backed by the IOSurface - this is the zero-copy magic!
        id<MTLTexture> texture = [ctx->device newTextureWithDescriptor:textureDescriptor
                                                             iosurface:surface
                                                                 plane:0];
        CFRelease(surface);

        if (texture == nil) {
            return NULL;
        }

        // Retain the texture so it survives autorelease
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
