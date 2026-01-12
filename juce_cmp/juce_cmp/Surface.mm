// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "Surface.h"

#if __APPLE__
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#endif

namespace juce_cmp
{

Surface::Surface() = default;

Surface::~Surface()
{
    release();
}

bool Surface::create(int width, int height)
{
#if __APPLE__
    release();

    width_ = width;
    height_ = height;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(width),
        (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        (id)kIOSurfaceIsGlobal: @YES  // Required for cross-process lookup
    };
    #pragma clang diagnostic pop

    surface_ = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    return surface_ != nullptr;
#else
    (void)width;
    (void)height;
    return false;
#endif
}

uint32_t Surface::resize(int width, int height)
{
#if __APPLE__
    width_ = width;
    height_ = height;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(width),
        (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        (id)kIOSurfaceIsGlobal: @YES
    };
    #pragma clang diagnostic pop

    IOSurfaceRef newSurface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (newSurface != nullptr)
    {
        // Keep previous surface alive - view may still be displaying it
        if (previousSurface_ != nullptr)
            CFRelease((IOSurfaceRef)previousSurface_);
        previousSurface_ = surface_;
        surface_ = newSurface;
        return IOSurfaceGetID((IOSurfaceRef)surface_);
    }
    return 0;
#else
    (void)width;
    (void)height;
    return 0;
#endif
}

void Surface::release()
{
#if __APPLE__
    if (previousSurface_ != nullptr)
    {
        CFRelease((IOSurfaceRef)previousSurface_);
        previousSurface_ = nullptr;
    }
    if (surface_ != nullptr)
    {
        CFRelease((IOSurfaceRef)surface_);
        surface_ = nullptr;
    }
#endif
    width_ = 0;
    height_ = 0;
}

bool Surface::isValid() const
{
    return surface_ != nullptr;
}

uint32_t Surface::getID() const
{
#if __APPLE__
    return surface_ != nullptr ? IOSurfaceGetID((IOSurfaceRef)surface_) : 0;
#else
    return 0;
#endif
}

void* Surface::getNativeHandle() const
{
    return surface_;
}

}  // namespace juce_cmp
