#import <stdio.h>
#import <stdlib.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

void copyToIOSurface(long surfaceId, long layerPtr) {
    @autoreleasepool {
        CAMetalLayer *layer = (CAMetalLayer *)layerPtr;
        if (layer == nil || ![layer isKindOfClass:[CAMetalLayer class]]) {
            return; // Layer not a CAMetalLayer
        }

        id<MTLDevice> device = layer.device;
        if (device == nil) {
            return; // No Metal device
        }

        IOSurfaceRef surface = IOSurfaceLookup((IOSurfaceID)surfaceId);
        if (surface == NULL) {
            return; // Surface not found
        }

        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor new];
        textureDescriptor.width = IOSurfaceGetWidth(surface);
        textureDescriptor.height = IOSurfaceGetHeight(surface);
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderWrite;

        id<MTLTexture> destTexture = [device newTextureWithDescriptor:textureDescriptor iosurface:surface plane:0];
        if (destTexture == nil) {
            CFRelease(surface);
            return; // Failed to create destination texture
        }

        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (drawable == nil) {
            CFRelease(surface);
            return; // No drawable available yet
        }
        id<MTLTexture> srcTexture = drawable.texture;

        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];

        MTLOrigin origin = {0, 0, 0};
        MTLSize size = {srcTexture.width, srcTexture.height, 1};

        [blitEncoder copyFromTexture:srcTexture sourceSlice:0 sourceLevel:0 sourceOrigin:origin sourceSize:size toTexture:destTexture destinationSlice:0 destinationLevel:0 destinationOrigin:origin];

        [blitEncoder endEncoding];
        [commandBuffer commit];
        
        CFRelease(surface);
    }
}
