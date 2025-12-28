#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

// Metal context for GPU rendering
typedef struct {
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
} MetalContext;

// Create Metal context for GPU operations
void* createMetalContext(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            fprintf(stderr, "[GPU Native] Failed to create Metal device\n");
            return NULL;
        }
        
        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        if (commandQueue == nil) {
            fprintf(stderr, "[GPU Native] Failed to create command queue\n");
            return NULL;
        }
        
        MetalContext* ctx = (MetalContext*)malloc(sizeof(MetalContext));
        ctx->device = device;
        ctx->commandQueue = commandQueue;
        
        // Prevent ARC from releasing these
        CFRetain((__bridge CFTypeRef)device);
        CFRetain((__bridge CFTypeRef)commandQueue);
        
        fprintf(stdout, "[GPU Native] Metal context created\n");
        fflush(stdout);
        
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
        fprintf(stdout, "[GPU Native] Metal context destroyed\n");
        fflush(stdout);
    }
}

// Render pixel data to IOSurface using Metal
void renderToIOSurface(void* context, int surfaceID, const char* pixelData, int width, int height, int bytesPerRow) {
    if (context == NULL || pixelData == NULL) return;
    
    @autoreleasepool {
        MetalContext* ctx = (MetalContext*)context;
        
        // Lookup IOSurface
        IOSurfaceRef surface = IOSurfaceLookup((IOSurfaceID)surfaceID);
        if (surface == NULL) {
            return;
        }
        
        // Create texture backed by IOSurface
        MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.width = IOSurfaceGetWidth(surface);
        textureDescriptor.height = IOSurfaceGetHeight(surface);
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.usage = MTLTextureUsageShaderWrite;
        textureDescriptor.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> destTexture = [ctx->device newTextureWithDescriptor:textureDescriptor 
                                                                 iosurface:surface 
                                                                     plane:0];
        if (destTexture == nil) {
            CFRelease(surface);
            return;
        }
        
        // Create source texture from pixel data
        MTLTextureDescriptor* srcDescriptor = [[MTLTextureDescriptor alloc] init];
        srcDescriptor.width = width;
        srcDescriptor.height = height;
        srcDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        srcDescriptor.usage = MTLTextureUsageShaderRead;
        srcDescriptor.storageMode = MTLStorageModeShared;
        
        id<MTLTexture> srcTexture = [ctx->device newTextureWithDescriptor:srcDescriptor];
        if (srcTexture == nil) {
            CFRelease(surface);
            return;
        }
        
        // Upload pixel data to source texture
        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [srcTexture replaceRegion:region mipmapLevel:0 withBytes:pixelData bytesPerRow:width * 4];
        
        // Blit from source to destination
        id<MTLCommandBuffer> commandBuffer = [ctx->commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        
        [blitEncoder copyFromTexture:srcTexture
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:(MTLOrigin){0, 0, 0}
                          sourceSize:(MTLSize){(NSUInteger)width, (NSUInteger)height, 1}
                           toTexture:destTexture
                    destinationSlice:0
                    destinationLevel:0
                   destinationOrigin:(MTLOrigin){0, 0, 0}];
        
        [blitEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        
        CFRelease(surface);
    }
}
