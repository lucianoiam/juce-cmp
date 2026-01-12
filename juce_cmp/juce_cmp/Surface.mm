// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "Surface.h"

#if JUCE_MAC
#import <IOSurface/IOSurface.h>
#import <Foundation/Foundation.h>
#endif

namespace juce_cmp
{

Surface::Surface() = default;

Surface::~Surface()
{
    release();
}

bool Surface::create(int w, int h)
{
#if JUCE_MAC
    release();

    width = w;
    height = h;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(w),
        (id)kIOSurfaceHeight: @(h),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        (id)kIOSurfaceIsGlobal: @YES
    };
    #pragma clang diagnostic pop

    surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    return surface != nullptr;
#else
    juce::ignoreUnused(w, h);
    return false;
#endif
}

uint32_t Surface::resize(int w, int h)
{
#if JUCE_MAC
    width = w;
    height = h;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSDictionary* props = @{
        (id)kIOSurfaceWidth: @(w),
        (id)kIOSurfaceHeight: @(h),
        (id)kIOSurfaceBytesPerElement: @4,
        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
        (id)kIOSurfaceIsGlobal: @YES
    };
    #pragma clang diagnostic pop

    IOSurfaceRef newSurface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (newSurface != nullptr)
    {
        // Keep previous surface alive - view may still be displaying it
        if (previousSurface != nullptr)
            CFRelease(previousSurface);
        previousSurface = surface;
        surface = newSurface;
        return IOSurfaceGetID(static_cast<IOSurfaceRef>(surface));
    }
    return 0;
#else
    juce::ignoreUnused(w, h);
    return 0;
#endif
}

void Surface::release()
{
#if JUCE_MAC
    if (previousSurface != nullptr)
    {
        CFRelease(previousSurface);
        previousSurface = nullptr;
    }
    if (surface != nullptr)
    {
        CFRelease(surface);
        surface = nullptr;
    }
#endif
    width = 0;
    height = 0;
}

uint32_t Surface::getID() const
{
#if JUCE_MAC
    return surface != nullptr ? IOSurfaceGetID(static_cast<IOSurfaceRef>(surface)) : 0;
#else
    return 0;
#endif
}

void* Surface::getNativeHandle() const
{
    return surface;
}

}  // namespace juce_cmp
