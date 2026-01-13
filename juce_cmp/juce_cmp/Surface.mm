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

    // Initial surface: No kIOSurfaceIsGlobal needed - Mach port is passed via bootstrap IPC
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(width),
        (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA')
    };

    surface_ = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    return surface_ != nullptr;
#else
    (void)width;
    (void)height;
    return false;
#endif
}

bool Surface::resize(int width, int height)
{
#if __APPLE__
    width_ = width;
    height_ = height;

    // No kIOSurfaceIsGlobal - surface is shared via Mach port IPC
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(width),
        (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA')
    };

    IOSurfaceRef newSurface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (newSurface != nullptr)
    {
        // Keep previous surface alive - view may still be displaying it
        if (previousSurface_ != nullptr)
            CFRelease((IOSurfaceRef)previousSurface_);
        previousSurface_ = surface_;
        surface_ = newSurface;
        return true;
    }
    return false;
#else
    (void)width;
    (void)height;
    return false;
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

uint32_t Surface::createMachPort() const
{
#if __APPLE__
    if (surface_ == nullptr)
        return 0;
    mach_port_t port = IOSurfaceCreateMachPort((IOSurfaceRef)surface_);
    return (uint32_t)port;
#else
    return 0;
#endif
}

void* Surface::getNativeHandle() const
{
    return surface_;
}

}  // namespace juce_cmp
